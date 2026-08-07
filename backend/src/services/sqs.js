const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');
const config = require('../config');

const client = new SQSClient({ region: config.awsRegion });

// review_pipeline(Terraform)의 SQS 큐 -> EventBridge Pipe -> Step Functions -> worker Lambda로
// 이어지는 비동기 검열 체인의 진입점. photoKey를 안 보내면(사진을 새로 안 올린 경우) worker가
// 이미지 재검열을 건너뛰고 기존 photoUrl을 그대로 둠
async function sendReviewModerationMessage({ userId, productId, text, photoKey }) {
  await client.send(
    new SendMessageCommand({
      QueueUrl: config.reviewModerationQueueUrl,
      MessageBody: JSON.stringify({ userId, productId, text, photoKey }),
    })
  );
}

module.exports = { sendReviewModerationMessage };
