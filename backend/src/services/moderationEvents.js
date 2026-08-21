const crypto = require('crypto');
const { GetCommand, PutCommand, ScanCommand, QueryCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const config = require('../config');
const client = require('./dynamoClient');

// review_pipeline의 worker Lambda(dambda/modules/review_pipeline/src/worker/index.js)가
// 검열에 걸린 리뷰만 이 테이블에 씀 - eventId/userId/productId/reviewText/status(PENDING)/
// detectedAt/blockReasons/comprehendScores/rekognitionLabels/quarantinePhotoKey/expiresAt.
// 여기 status는 리뷰 자체의 moderationStatus(REVIEW_REQUIRED)와 별개로, "관리자가 이 검열
// 건을 처리했는지"를 나타냄(PENDING -> REVIEWED/DISMISSED/DELETED)

// worker Lambda(DynamoDB 네이티브 타입만 다루는 저수준 SDK)는 blockReasons/comprehendScores/
// rekognitionLabels를 JSON.stringify한 문자열로 저장함 - 관리자 페이지에는 실제 배열/객체로
// 풀어서 내려줘야 Flutter 쪽이 그대로 리스트 렌더링할 수 있음
function parseEvent(item) {
  if (!item) return item;
  const parsed = { ...item };
  for (const field of ['blockReasons', 'comprehendScores', 'rekognitionLabels']) {
    if (typeof parsed[field] === 'string') {
      try {
        parsed[field] = JSON.parse(parsed[field]);
      } catch (_) {
        parsed[field] = [];
      }
    }
  }
  return parsed;
}

async function createEvent(input) {
  const now = new Date();
  const event = {
    eventId: crypto.randomUUID(),
    status: 'PENDING',
    detectedAt: now.toISOString(),
    expiresAt: Math.floor(now.getTime() / 1000) + 30 * 24 * 60 * 60,
    ...input,
  };
  await client.send(new PutCommand({ TableName: config.moderationEventsTableName, Item: event }));
  return event;
}

async function getEvent(eventId) {
  const result = await client.send(
    new GetCommand({ TableName: config.moderationEventsTableName, Key: { eventId } })
  );
  return parseEvent(result.Item) || null;
}

// DELETED는 소프트 삭제된 알림 전용 상태라 관리자 검열 큐에는 더 이상 안 보여줌
// (listUnreadNotifications가 이 상태를 사용자 알림함에서 대신 노출함)
async function listEvents() {
  const items = [];
  let ExclusiveStartKey;
  do {
    const result = await client.send(
      new ScanCommand({ TableName: config.moderationEventsTableName, ExclusiveStartKey })
    );
    items.push(...(result.Items || []));
    ExclusiveStartKey = result.LastEvaluatedKey;
  } while (ExclusiveStartKey);
  return items
    .map(parseEvent)
    .filter((item) => item.status !== 'DELETED')
    .sort((a, b) => String(b.detectedAt).localeCompare(String(a.detectedAt)));
}

async function updateStatus(eventId, status) {
  const result = await client.send(
    new UpdateCommand({
      TableName: config.moderationEventsTableName,
      Key: { eventId },
      UpdateExpression: 'SET #status = :status, reviewedAt = :reviewedAt',
      ExpressionAttributeNames: { '#status': 'status' },
      ExpressionAttributeValues: { ':status': status, ':reviewedAt': new Date().toISOString() },
      ReturnValues: 'ALL_NEW',
    })
  );
  return result.Attributes;
}

// 검열 큐에 이미 있던 항목(리뷰 사진 등)을 관리자가 삭제 처리 - 레코드 자체는 지우지 않고
// DELETED로 남겨서 작성자 알림함(GET /notifications)에 뜨게 함. 격리 이미지 참조는 이미
// s3에서 지워졌으므로 같이 정리
async function markDeleted(eventId) {
  const result = await client.send(
    new UpdateCommand({
      TableName: config.moderationEventsTableName,
      Key: { eventId },
      UpdateExpression:
        'SET #status = :status, notificationMessage = :message, notificationRead = :unread, reviewedAt = :reviewedAt REMOVE quarantinePhotoKey',
      ExpressionAttributeNames: { '#status': 'status' },
      ExpressionAttributeValues: {
        ':status': 'DELETED',
        ':message': '해당 게시물은 관리자에 의해 삭제되었습니다.',
        ':unread': false,
        ':reviewedAt': new Date().toISOString(),
      },
      ReturnValues: 'ALL_NEW',
    })
  );
  return result.Attributes;
}

// 검열 큐를 거치지 않은 정상 리뷰를 관리자가 직접 삭제한 경우 - 기존 moderation_events
// 행이 없으므로 알림 전달용으로 새로 하나 만듦 (routes/admin.js DELETE /reviews/:userId/:productId)
async function createDeletionNotification(review) {
  return createEvent({
    userId: review.userId,
    productId: review.productId,
    reviewText: review.text,
    requestType: 'ADMIN_REVIEW_DELETE',
    status: 'DELETED',
    notificationMessage: '해당 게시물은 관리자에 의해 삭제되었습니다.',
    notificationRead: false,
    blockReasons: ['admin_deleted'],
  });
}

async function listUnreadNotifications(userId) {
  const result = await client.send(
    new QueryCommand({
      TableName: config.moderationEventsTableName,
      IndexName: 'moderation-events-by-user',
      KeyConditionExpression: 'userId = :userId',
      FilterExpression: '#status = :deleted AND notificationRead = :unread',
      ExpressionAttributeNames: { '#status': 'status' },
      ExpressionAttributeValues: { ':userId': userId, ':deleted': 'DELETED', ':unread': false },
      ScanIndexForward: false,
    })
  );
  return (result.Items || []).map(parseEvent);
}

async function markNotificationRead(eventId, userId) {
  await client.send(
    new UpdateCommand({
      TableName: config.moderationEventsTableName,
      Key: { eventId },
      UpdateExpression: 'SET notificationRead = :read, notificationReadAt = :readAt',
      ConditionExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':read': true,
        ':readAt': new Date().toISOString(),
        ':userId': userId,
      },
    })
  );
}

module.exports = {
  getEvent,
  listEvents,
  updateStatus,
  markDeleted,
  createDeletionNotification,
  listUnreadNotifications,
  markNotificationRead,
};
