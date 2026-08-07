const crypto = require('crypto');
const { S3Client, PutObjectCommand, DeleteObjectCommand } = require('@aws-sdk/client-s3');
const config = require('../config');

const client = new S3Client({ region: config.awsRegion });

function extensionFor(mimeType) {
  if (mimeType === 'image/png') return 'png';
  if (mimeType === 'image/webp') return 'webp';
  return 'jpg';
}

async function uploadReviewPhoto(buffer, mimeType) {
  const key = `reviews/${crypto.randomUUID()}.${extensionFor(mimeType)}`;
  await client.send(
    new PutObjectCommand({
      Bucket: config.reviewPhotosBucket,
      Key: key,
      Body: buffer,
      ContentType: mimeType,
    })
  );
  return {
    bucket: config.reviewPhotosBucket,
    key,
    url: `https://${config.reviewPhotosDomain}/${key}`,
  };
}

async function deleteReviewPhoto(key) {
  await client.send(
    new DeleteObjectCommand({
      Bucket: config.reviewPhotosBucket,
      Key: key,
    })
  );
}

// 검열 전 리뷰 사진이 임시로 올라가는 곳(비공개) - review_pipeline의 worker Lambda가 승인 시
// review_photos(공개)로 옮기고 여기서는 지움. 반려되면 여기 그대로 남았다가 30일 후 자동 삭제됨
async function uploadToQuarantine(buffer, mimeType) {
  const key = `reviews/${crypto.randomUUID()}.${extensionFor(mimeType)}`;
  await client.send(
    new PutObjectCommand({
      Bucket: config.quarantineBucket,
      Key: key,
      Body: buffer,
      ContentType: mimeType,
    })
  );
  return key;
}

async function deleteQuarantinePhoto(key) {
  await client.send(
    new DeleteObjectCommand({
      Bucket: config.quarantineBucket,
      Key: key,
    })
  );
}

module.exports = { uploadReviewPhoto, deleteReviewPhoto, uploadToQuarantine, deleteQuarantinePhoto };
