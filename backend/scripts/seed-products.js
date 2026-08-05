// 1회성 수동 스크립트. terraform apply로 product_catalog 테이블을 만든 뒤
// `AWS_REGION=ap-northeast-2 node backend/scripts/seed-products.js`로 직접 실행
// (AWS 자격증명 필요, translate:TranslateText 권한 포함).
const fs = require('fs');
const path = require('path');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { translateText } = require('../src/services/translate');

const TABLE_NAME = process.env.PRODUCT_CATALOG_TABLE_NAME;
const ITEMS_JSON_PATH = path.join(__dirname, '..', '..', 'json', 'items.json');
// 한국어는 원문이라 제외 - 영어/일본어/중국어로 배치 번역
const TARGET_LANGS = ['en', 'ja', 'zh'];
const CONCURRENCY = 10;

if (!TABLE_NAME) {
  console.error('PRODUCT_CATALOG_TABLE_NAME env var is required');
  process.exit(1);
}

// 상품 리스트를 동시에 CONCURRENCY개씩만 처리 (Translate 쓰로틀링 방지)
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

// category는 클라이언트에서 l10n 키로 이미 처리 중이라 여기서 손댈 필요 없음
async function translateFields(item) {
  const translations = {};
  await Promise.all(
    TARGET_LANGS.map(async (lang) => {
      const [name, reason, store, discountInfo] = await Promise.all([
        translateText(item.name, lang).then((r) => r.translatedText),
        translateText(item.reason, lang).then((r) => r.translatedText),
        translateText(item.store, lang).then((r) => r.translatedText),
        item.discountInfo
          ? translateText(item.discountInfo, lang).then((r) => r.translatedText)
          : Promise.resolve(undefined),
      ]);
      translations[lang] = discountInfo ? { name, reason, store, discountInfo } : { name, reason, store };
    })
  );
  return translations;
}

// items.json은 유효한 단일 JSON이 아니라 배열 [...] 3개가 그냥 이어붙여진 텍스트라서
// ']' 다음에 '[' 가 나오는 지점을 기준으로 쪼개 각각 파싱한다.
function parseConcatenatedArrays(text) {
  const chunks = text.trim().split(/\]\s*\[/);
  return chunks.flatMap((chunk, index) => {
    const withOpen = index === 0 ? chunk : `[${chunk}`;
    const withClose = index === chunks.length - 1 ? withOpen : `${withOpen}]`;
    return JSON.parse(withClose);
  });
}

async function main() {
  const raw = fs.readFileSync(ITEMS_JSON_PATH, 'utf8');
  const items = parseConcatenatedArrays(raw);

  const client = DynamoDBDocumentClient.from(new DynamoDBClient({}));

  console.log(`translating ${items.length} products into ${TARGET_LANGS.join(', ')}...`);
  await mapWithConcurrency(items, CONCURRENCY, async (item) => {
    const translations = await translateFields(item);

    const record = {
      itemId: item.itemId,
      category: item.category,
      name: item.name,
      price: item.price,
      store: item.store,
      reason: item.reason,
      imageUrl: item.imageUrl,
      translations,
    };
    if (item.discountInfo) record.discountInfo = item.discountInfo;

    await client.send(new PutCommand({ TableName: TABLE_NAME, Item: record }));
    console.log(`seeded ${record.itemId}`);
  });

  console.log(`done - ${items.length} products written to ${TABLE_NAME}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
