const { GetCommand, ScanCommand, UpdateCommand, DeleteCommand } = require('@aws-sdk/lib-dynamodb');
const config = require('../config');
const client = require('./dynamoClient');

// review_pipeline의 worker Lambda(dambda/modules/review_pipeline/src/worker/index.js)가
// 검열에 걸린 리뷰만 이 테이블에 씀 - eventId/userId/productId/reviewText/status(PENDING)/
// detectedAt/blockReasons/comprehendScores/rekognitionLabels/quarantinePhotoKey/expiresAt.
// 여기 status는 리뷰 자체의 moderationStatus(REVIEW_REQUIRED)와 별개로, "관리자가 이 검열
// 건을 처리했는지"를 나타냄(PENDING -> REVIEWED/DISMISSED)

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

async function getEvent(eventId) {
  const result = await client.send(
    new GetCommand({ TableName: config.moderationEventsTableName, Key: { eventId } })
  );
  return parseEvent(result.Item) || null;
}

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

// dambda-sub 원본은 소프트 삭제(상태만 DELETED로 바꾸고 작성자에게 알림)였는데, 그 알림
// 기능(userId 기준 GSI 필요)은 이번 범위에서 뺐으므로 그냥 완전히 지움
async function deleteEvent(eventId) {
  await client.send(
    new DeleteCommand({ TableName: config.moderationEventsTableName, Key: { eventId } })
  );
}

module.exports = { getEvent, listEvents, updateStatus, deleteEvent };
