const { TranslateClient, TranslateTextCommand } = require('@aws-sdk/client-translate');
const { ComprehendClient, DetectToxicContentCommand } = require('@aws-sdk/client-comprehend');
const { RekognitionClient, DetectModerationLabelsCommand } = require('@aws-sdk/client-rekognition');
const { S3Client, CopyObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const { DynamoDBClient, UpdateItemCommand, PutItemCommand } = require('@aws-sdk/client-dynamodb');
const crypto = require('crypto');

const translate = new TranslateClient({});
const comprehend = new ComprehendClient({ region: 'us-east-1' });
const rekognition = new RekognitionClient({});
const s3 = new S3Client({});
const dynamodb = new DynamoDBClient({});

function message(input) {
  return typeof input.body === 'string' ? JSON.parse(input.body) : input;
}

// DetectToxicContent는 영어만 지원하고, SourceLanguageCode: 'auto'는 내부적으로
// comprehend:DetectDominantLanguage를 호출함 - 짧거나 애매한 텍스트("hi", 자모 하나 등)는
// 신뢰도가 낮아 DetectedLanguageLowConfidenceException을 던지므로, 예외에 실려오는 감지
// 언어로 한 번 더 시도함(review_moderation Lambda와 동일 이슈/동일 해법)
async function translateToEnglish(text) {
  try {
    const result = await translate.send(new TranslateTextCommand({
      Text: text,
      SourceLanguageCode: 'auto',
      TargetLanguageCode: 'en',
    }));
    return result.TranslatedText;
  } catch (err) {
    if (err.name === 'DetectedLanguageLowConfidenceException' && err.DetectedLanguageCode) {
      if (err.DetectedLanguageCode === 'en') return text;
      const retry = await translate.send(new TranslateTextCommand({
        Text: text,
        SourceLanguageCode: err.DetectedLanguageCode,
        TargetLanguageCode: 'en',
      }));
      return retry.TranslatedText;
    }
    throw err;
  }
}

async function textResult(text) {
  const translatedText = await translateToEnglish(text);
  const result = await comprehend.send(new DetectToxicContentCommand({
    LanguageCode: 'en',
    TextSegments: [{ Text: translatedText }],
  }));
  const labels = (result.ResultList || []).flatMap((segment) => segment.Labels || []);
  const threshold = Number(process.env.TOXICITY_THRESHOLD);
  return { translatedText, labels, blocked: labels.some((label) => label.Score >= threshold) };
}

async function imageResult(photoKey) {
  if (!photoKey) return { labels: [], blocked: false };
  const result = await rekognition.send(new DetectModerationLabelsCommand({
    Image: { S3Object: { Bucket: process.env.QUARANTINE_BUCKET, Name: photoKey } },
    MinConfidence: Number(process.env.IMAGE_CONFIDENCE_THRESHOLD),
  }));
  return { labels: result.ModerationLabels || [], blocked: (result.ModerationLabels || []).length > 0 };
}

function av(value) { return { S: value }; }

exports.handler = async (input) => {
  const review = message(input);
  if (!review.userId || !review.productId || !review.text) throw new Error('Invalid review moderation message');

  const [text, image] = await Promise.all([textResult(review.text), imageResult(review.photoKey)]);
  const detectedAt = new Date().toISOString();
  const blocked = text.blocked || image.blocked;

  if (!blocked && review.photoKey) {
    await s3.send(new CopyObjectCommand({
      Bucket: process.env.PUBLIC_REVIEW_BUCKET,
      Key: review.photoKey,
      CopySource: `${process.env.QUARANTINE_BUCKET}/${encodeURIComponent(review.photoKey)}`,
    }));
    await s3.send(new DeleteObjectCommand({ Bucket: process.env.QUARANTINE_BUCKET, Key: review.photoKey }));
  }

  if (blocked) {
    const eventId = crypto.randomUUID();
    const expiresAt = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60);
    await dynamodb.send(new PutItemCommand({
      TableName: process.env.MODERATION_EVENTS_TABLE,
      Item: {
        eventId: av(eventId), userId: av(review.userId), productId: av(review.productId),
        reviewText: av(review.text), status: av('PENDING'), detectedAt: av(detectedAt),
        blockReasons: av(JSON.stringify([
          ...text.labels.filter((label) => label.Score >= Number(process.env.TOXICITY_THRESHOLD)).map((label) => `text:${label.Name}`),
          ...image.labels.map((label) => `image:${label.Name}`),
        ])),
        comprehendScores: av(JSON.stringify(text.labels)), rekognitionLabels: av(JSON.stringify(image.labels)),
        quarantinePhotoKey: av(review.photoKey || ''), expiresAt: { N: String(expiresAt) },
      },
    }));
  }

  const status = blocked ? 'REVIEW_REQUIRED' : 'APPROVED';
  const values = { ':status': av(status), ':visible': { BOOL: !blocked }, ':at': av(detectedAt) };
  let expression = 'SET moderationStatus = :status, isVisible = :visible, moderationUpdatedAt = :at';
  if (!blocked && review.photoKey) {
    values[':photoUrl'] = av(`https://${process.env.PUBLIC_REVIEW_BUCKET_DOMAIN}/${review.photoKey}`);
    expression += ', photoUrl = :photoUrl';
  }
  await dynamodb.send(new UpdateItemCommand({
    TableName: process.env.REVIEW_TABLE_NAME,
    Key: { userId: av(review.userId), productId: av(review.productId) },
    UpdateExpression: expression,
    ExpressionAttributeValues: values,
  }));

  return { reviewId: `${review.userId}#${review.productId}`, status, detectedAt };
};
