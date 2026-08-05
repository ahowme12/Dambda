// 1회성 수동 스크립트. terraform apply로 product_catalog 테이블을 만든 뒤
// `node backend/scripts/seed-products.js`로 직접 실행 (AWS 자격증명 필요).
const fs = require('fs');
const path = require('path');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, PutCommand } = require('@aws-sdk/lib-dynamodb');

const TABLE_NAME = process.env.PRODUCT_CATALOG_TABLE_NAME;
const ITEMS_JSON_PATH = path.join(__dirname, '..', '..', 'json', 'items.json');

if (!TABLE_NAME) {
  console.error('PRODUCT_CATALOG_TABLE_NAME env var is required');
  process.exit(1);
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

  for (const item of items) {
    const record = {
      itemId: item.itemId,
      category: item.category,
      name: item.name,
      price: item.price,
      store: item.store,
      reason: item.reason,
      imageUrl: item.imageUrl,
    };
    if (item.discountInfo) record.discountInfo = item.discountInfo;

    await client.send(new PutCommand({ TableName: TABLE_NAME, Item: record }));
    console.log(`seeded ${record.itemId}`);
  }

  console.log(`done - ${items.length} products written to ${TABLE_NAME}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
