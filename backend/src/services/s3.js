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

module.exports = { uploadReviewPhoto, deleteReviewPhoto };
