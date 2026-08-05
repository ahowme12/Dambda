const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient } = require('@aws-sdk/lib-dynamodb');
const config = require('../config');

module.exports = DynamoDBDocumentClient.from(new DynamoDBClient({ region: config.awsRegion }));
