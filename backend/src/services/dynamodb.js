const { PutCommand, GetCommand } = require('@aws-sdk/lib-dynamodb');
const config = require('../config');
const client = require('./dynamoClient');

async function putProfile(profile) {
  await client.send(
    new PutCommand({
      TableName: config.dynamodbTableName,
      Item: profile,
    })
  );
}

async function getProfile(userId) {
  const result = await client.send(
    new GetCommand({
      TableName: config.dynamodbTableName,
      Key: { userId },
    })
  );
  return result.Item;
}

module.exports = { putProfile, getProfile };
