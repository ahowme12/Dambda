// 1회성 수동 스크립트. dambda 인프라의 product_images 버킷을 apply한 뒤
// `PRODUCT_IMAGES_BUCKET=my-app-dev-product-images-<account_id> AWS_REGION=ap-northeast-2 node backend/scripts/migrate-product-images.js`로 직접 실행
// (AWS 자격증명 필요, s3:PutObject 권한 포함).
//
// json/items.json의 imageUrl이 우리가 관리하지 않는 남의 계정 버킷(dambda-images.s3...)을
// 가리키고 있었는데 CORS가 없어서 Flutter 웹(CanvasKit)에서 이미지가 안 보였음(모바일은
// 브라우저 CORS 제약이 없어서 멀쩡했음) - 이미지를 우리 소유 버킷으로 옮기고 items.json의
// imageUrl을 새 주소로 갱신한다. 실행 후 seed-products.js를 다시 돌려야 DynamoDB에도 반영됨.
const fs = require('fs');
const path = require('path');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

const BUCKET = process.env.PRODUCT_IMAGES_BUCKET;
const REGION = process.env.AWS_REGION || 'ap-northeast-2';
const ITEMS_JSON_PATH = path.join(__dirname, '..', '..', 'json', 'items.json');
const CONCURRENCY = 10;

if (!BUCKET) {
  console.error('PRODUCT_IMAGES_BUCKET env var is required');
  process.exit(1);
}

const s3 = new S3Client({ region: REGION });

// items.json은 유효한 단일 JSON이 아니라 배열 [...] 여러 개가 그냥 이어붙여진 텍스트라서
// (seed-products.js 참고) ']' 다음에 '[' 가 나오는 지점을 기준으로 쪼개 각각 파싱한다.
function parseConcatenatedArrays(text) {
  const chunks = text.trim().split(/\]\s*\[/);
  return chunks.flatMap((chunk, index) => {
    const withOpen = index === 0 ? chunk : `[${chunk}`;
    const withClose = index === chunks.length - 1 ? withOpen : `${withOpen}]`;
    return JSON.parse(withClose);
  });
}

function contentTypeFor(key) {
  if (key.endsWith('.png')) return 'image/png';
  if (key.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

async function mapWithConcurrency(items, limit, fn) {
  const results = new Array(items.length);
  let index = 0;
  async function worker() {
    while (index < items.length) {
      const i = index++;
      results[i] = await fn(items[i]);
    }
  }
  await Promise.all(Array.from({ length: limit }, worker));
  return results;
}

async function migrateOne(item) {
  if (!item.imageUrl) return item;

  const key = new URL(item.imageUrl).pathname.replace(/^\//, '');
  const res = await fetch(item.imageUrl);
  if (!res.ok) throw new Error(`failed to download ${item.imageUrl}: ${res.status}`);
  const buffer = Buffer.from(await res.arrayBuffer());

  await s3.send(
    new PutObjectCommand({
      Bucket: BUCKET,
      Key: key,
      Body: buffer,
      ContentType: contentTypeFor(key),
    })
  );

  console.log(`migrated ${item.itemId}: ${key}`);
  return { ...item, imageUrl: `https://${BUCKET}.s3.${REGION}.amazonaws.com/${key}` };
}

async function main() {
  const raw = fs.readFileSync(ITEMS_JSON_PATH, 'utf8');
  const items = parseConcatenatedArrays(raw);

  const migrated = await mapWithConcurrency(items, CONCURRENCY, migrateOne);

  fs.writeFileSync(ITEMS_JSON_PATH, JSON.stringify(migrated, null, 2) + '\n');
  console.log(`done - ${migrated.length} items updated in ${ITEMS_JSON_PATH}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
