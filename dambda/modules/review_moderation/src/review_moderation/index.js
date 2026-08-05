const { ComprehendClient, DetectToxicContentCommand } = require('@aws-sdk/client-comprehend');
const { RekognitionClient, DetectModerationLabelsCommand } = require('@aws-sdk/client-rekognition');

const region = process.env.AWS_REGION;
// DetectToxicContent는 이 프로젝트가 쓰는 리전(ap-northeast-2)에서 NotAuthorizedException으로
// 막혀있음이 확인됨(계정/리전 단위 미지원) - Lambda 자체는 그대로 두고 Comprehend 호출만
// 지원되는 리전(us-east-1)으로 보냄. Rekognition은 ap-northeast-2에서 정상 동작 확인됨
const comprehend = new ComprehendClient({ region: 'us-east-1' });
const rekognition = new RekognitionClient({ region });

const TOXICITY_THRESHOLD = 0.7;
const MIN_MODERATION_CONFIDENCE = 70;

async function checkText(text) {
  if (!text || !text.trim()) return { approved: true, reasons: [] };

  const result = await comprehend.send(
    new DetectToxicContentCommand({
      TextSegments: [{ Text: text }],
      LanguageCode: 'en',
    })
  );

  const reasons = [];
  for (const segment of result.ResultList || []) {
    for (const label of segment.Labels || []) {
      if (label.Score >= TOXICITY_THRESHOLD) {
        reasons.push(`text:${label.Name}`);
      }
    }
  }
  return { approved: reasons.length === 0, reasons };
}

async function checkImage(imageBucket, imageKey) {
  if (!imageBucket || !imageKey) return { approved: true, reasons: [] };

  const result = await rekognition.send(
    new DetectModerationLabelsCommand({
      Image: { S3Object: { Bucket: imageBucket, Name: imageKey } },
      MinConfidence: MIN_MODERATION_CONFIDENCE,
    })
  );

  const reasons = (result.ModerationLabels || []).map((label) => `image:${label.Name}`);
  return { approved: reasons.length === 0, reasons };
}

exports.handler = async (event) => {
  const { text, imageBucket, imageKey } = event || {};

  try {
    const [textResult, imageResult] = await Promise.all([
      checkText(text),
      checkImage(imageBucket, imageKey),
    ]);

    return {
      approved: textResult.approved && imageResult.approved,
      reasons: [...textResult.reasons, ...imageResult.reasons],
    };
  } catch (err) {
    // 검열 자체가 실패하면(쓰로틀링 등) 우회시키지 않고 막음 - fail-closed
    console.error('moderation check failed', err);
    return { approved: false, reasons: ['moderation_service_error'] };
  }
};
