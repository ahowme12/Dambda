const { ScanCommand, GetCommand, PutCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const config = require('../config');
const client = require('./dynamoClient');

async function listProducts() {
  const result = await client.send(
    new ScanCommand({ TableName: config.productCatalogTableName })
  );
  return (result.Items || []).sort(
    (a, b) => a.category.localeCompare(b.category) || a.name.localeCompare(b.name)
  );
}

async function getProduct(itemId) {
  const result = await client.send(
    new GetCommand({ TableName: config.productCatalogTableName, Key: { itemId } })
  );
  return result.Item || null;
}

// 관리자 페이지의 상품 등록. 시딩 스크립트가 만든 itemId와 안 겹치게 라우트에서
// "admin_" 접두어로 새 id를 만들어서 넘겨줌
async function putProduct(product) {
  await client.send(
    new PutCommand({
      TableName: config.productCatalogTableName,
      Item: product,
      ConditionExpression: 'attribute_not_exists(itemId)',
    })
  );
}

async function updateProduct(product) {
  await client.send(
    new PutCommand({
      TableName: config.productCatalogTableName,
      Item: product,
      ConditionExpression: 'attribute_exists(itemId)',
    })
  );
}

async function deleteProduct(itemId) {
  await client.send(
    new DeleteCommand({
      TableName: config.productCatalogTableName,
      Key: { itemId },
      ConditionExpression: 'attribute_exists(itemId)',
    })
  );
}

module.exports = { listProducts, getProduct, putProduct, updateProduct, deleteProduct };
