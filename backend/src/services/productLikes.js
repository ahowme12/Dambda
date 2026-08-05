const { PutCommand, DeleteCommand, GetCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const config = require('../config');
const client = require('./dynamoClient');

async function isLiked(userId, productId) {
  const result = await client.send(
    new GetCommand({
      TableName: config.productLikesTableName,
      Key: { userId, productId },
    })
  );
  return !!result.Item;
}

async function like(userId, productId) {
  await client.send(
    new PutCommand({
      TableName: config.productLikesTableName,
      Item: { userId, productId, createdAt: new Date().toISOString() },
    })
  );
}

async function unlike(userId, productId) {
  await client.send(
    new DeleteCommand({
      TableName: config.productLikesTableName,
      Key: { userId, productId },
    })
  );
}

async function likedProductIdsForUser(userId) {
  const result = await client.send(
    new QueryCommand({
      TableName: config.productLikesTableName,
      KeyConditionExpression: 'userId = :u',
      ExpressionAttributeValues: { ':u': userId },
    })
  );
  return (result.Items || []).map((item) => item.productId);
}

module.exports = { isLiked, like, unlike, likedProductIdsForUser };
