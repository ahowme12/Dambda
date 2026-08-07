const crypto = require('crypto');
const {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} = require('@aws-sdk/client-s3');
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

// 관리자 페이지가 차단된 검열 내역의 격리 이미지를 미리보기로 스트리밍할 때 씀
// (Body가 Node.js Readable이라 라우트에서 res로 그대로 pipe함)
async function getQuarantinePhoto(key) {
  return client.send(
    new GetObjectCommand({
      Bucket: config.quarantineBucket,
      Key: key,
    })
  );
}

// 관리자가 상품 등록/수정 시 올리는 이미지. 검열 없이 바로 공개 버킷에 저장됨
// (관리자가 직접 올리는 콘텐츠라 리뷰 사진과 달리 quarantine을 거치지 않음)
async function uploadProductImage(buffer, mimeType) {
  const key = `products/${crypto.randomUUID()}.${extensionFor(mimeType)}`;
  await client.send(
    new PutObjectCommand({
      Bucket: config.productImagesBucket,
      Key: key,
      Body: buffer,
      ContentType: mimeType,
    })
  );
  return {
    key,
    url: `https://${config.productImagesDomain}/${key}`,
  };
}

async function deleteProductImage(key) {
  if (!key) return;
  await client.send(
    new DeleteObjectCommand({
      Bucket: config.productImagesBucket,
      Key: key,
    })
  );
}

module.exports = {
  uploadReviewPhoto,
  deleteReviewPhoto,
  uploadToQuarantine,
  deleteQuarantinePhoto,
  getQuarantinePhoto,
  uploadProductImage,
  deleteProductImage,
};
