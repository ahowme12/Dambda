const { PutCommand, GetCommand, QueryCommand, ScanCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const config = require('../config');
const client = require('./dynamoClient');

async function getReview(userId, productId) {
  const result = await client.send(
    new GetCommand({
      TableName: config.productReviewsTableName,
      Key: { userId, productId },
    })
  );
  return result.Item;
}

// ConditionExpression으로 "유저당 상품 1개 리뷰"를 원자적으로 강제 - 사전 getReview 체크만으로는
// 경합 상태(동시에 두 요청이 들어오는 경우)를 막을 수 없어서 실제 방어선은 이쪽
async function putReview(review) {
  await client.send(
    new PutCommand({
      TableName: config.productReviewsTableName,
      Item: review,
      ConditionExpression: 'attribute_not_exists(userId)',
    })
  );
}

// putReview와 달리 조건 없는 순수 덮어쓰기 - 수정은 이미 있는 아이템을 덮어써야 해서
// attribute_not_exists 조건을 걸면 안 됨 (그래서 putReview와 함수를 분리함)
async function updateReview(review) {
  await client.send(
    new PutCommand({
      TableName: config.productReviewsTableName,
      Item: review,
    })
  );
}

async function deleteReview(userId, productId) {
  await client.send(
    new DeleteCommand({
      TableName: config.productReviewsTableName,
      Key: { userId, productId },
    })
  );
}

async function queryReviewsByProduct(productId) {
  const result = await client.send(
    new QueryCommand({
      TableName: config.productReviewsTableName,
      IndexName: 'product-reviews-by-product',
      KeyConditionExpression: 'productId = :p',
      ExpressionAttributeValues: { ':p': productId },
      ScanIndexForward: false,
    })
  );
  return result.Items || [];
}

// 관리자 페이지의 "리뷰 관리" 탭 전체 목록용 - 상품 단위 조회(queryReviewsByProduct)와
// 달리 검열 상태와 무관하게 전부 보여줌(PENDING/REVIEW_REQUIRED도 관리자에게는 보여야 함)
async function listAllReviews() {
  const items = [];
  let ExclusiveStartKey;
  do {
    const result = await client.send(
      new ScanCommand({ TableName: config.productReviewsTableName, ExclusiveStartKey })
    );
    items.push(...(result.Items || []));
    ExclusiveStartKey = result.LastEvaluatedKey;
  } while (ExclusiveStartKey);
  return items.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
}

module.exports = {
  getReview,
  putReview,
  updateReview,
  deleteReview,
  queryReviewsByProduct,
  listAllReviews,
};
