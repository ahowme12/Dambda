import { RekognitionClient, DetectModerationLabelsCommand } from "@aws-sdk/client-rekognition";
import { ComprehendClient, DetectToxicContentCommand } from "@aws-sdk/client-comprehend";
import { DynamoDBClient, UpdateItemCommand } from "@aws-sdk/client-dynamodb";

const rekognition = new RekognitionClient({});
const comprehend = new ComprehendClient({});
const dynamodb = new DynamoDBClient({});

const MODERATION_CONFIDENCE_THRESHOLD = 75;

// updated_at은 건드리지 않음: Translations 테이블은 updated_at을 버전으로 캐시 키를 잡으므로
// 검열이 통과할 때마다 여기서 같이 갱신하면 번역 캐시가 불필요하게 무효화됨
async function setModerationStatus(contentId, status) {
  await dynamodb.send(
    new UpdateItemCommand({
      TableName: process.env.CONTENT_TABLE_NAME,
      Key: { content_id: { S: contentId } },
      UpdateExpression: "SET moderation_status = :status",
      ExpressionAttributeValues: { ":status": { S: status } },
    })
  );
}

async function moderateImage(record) {
  const bucket = record.s3.bucket.name;
  const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));

  // 업로드 키 규칙: "{content_id}/파일명" - 업로드 API가 이 규칙을 지켜야 함
  const contentId = key.split("/")[0];

  const { ModerationLabels = [] } = await rekognition.send(
    new DetectModerationLabelsCommand({
      Image: { S3Object: { Bucket: bucket, Name: key } },
      MinConfidence: MODERATION_CONFIDENCE_THRESHOLD,
    })
  );

  await setModerationStatus(contentId, ModerationLabels.length > 0 ? "flagged" : "clean");
}

async function moderateText(record) {
  const image = record.dynamodb.NewImage;
  const contentId = image.content_id?.S;
  const text = image.text?.S;

  if (!contentId || !text) return;

  // Comprehend 유해성 탐지는 영어 위주 지원이라 다국어 콘텐츠 정확도는 제한적 - 1차 구현
  const { ResultList = [] } = await comprehend.send(
    new DetectToxicContentCommand({
      TextSegments: [{ Text: text.slice(0, 5000) }],
      LanguageCode: "en",
    })
  );

  const isToxic = ResultList.some((result) => result.Toxicity > 0.7);
  await setModerationStatus(contentId, isToxic ? "flagged" : "clean");
}

export const handler = async (event) => {
  for (const record of event.Records) {
    if (record.eventSource === "aws:s3") {
      await moderateImage(record);
    } else if (record.eventSource === "aws:dynamodb" && record.eventName === "INSERT") {
      await moderateText(record);
    }
  }
};
