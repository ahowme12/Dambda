const { LambdaClient, InvokeCommand } = require('@aws-sdk/client-lambda');
const config = require('../config');

const client = new LambdaClient({ region: config.awsRegion });

// 검열 Lambda를 동기 호출. Lambda 쪽이 이미 fail-closed로 설계되어 있어서, 여기서 호출 자체가
// 실패하는 경우(타임아웃 등)도 같은 원칙으로 승인하지 않음
async function invokeModeration({ text, imageBucket, imageKey }) {
  try {
    const result = await client.send(
      new InvokeCommand({
        FunctionName: config.moderationLambdaName,
        InvocationType: 'RequestResponse',
        Payload: Buffer.from(JSON.stringify({ text, imageBucket, imageKey })),
      })
    );
    const payload = JSON.parse(Buffer.from(result.Payload).toString('utf-8'));
    if (result.FunctionError || typeof payload.approved !== 'boolean') {
      return { approved: false, reasons: ['moderation_service_error'] };
    }
    return payload;
  } catch (err) {
    return { approved: false, reasons: ['moderation_service_error'] };
  }
}

module.exports = { invokeModeration };
