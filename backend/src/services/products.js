const { ScanCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');
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

module.exports = { listProducts, getProduct };
