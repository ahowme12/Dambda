const { ScanCommand } = require('@aws-sdk/lib-dynamodb');
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

module.exports = { listProducts };
