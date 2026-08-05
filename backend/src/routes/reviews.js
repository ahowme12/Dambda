const express = require('express');
const multer = require('multer');
const reviews = require('../services/reviews');
const dynamodb = require('../services/dynamodb');
const s3 = require('../services/s3');
const lambda = require('../services/lambda');
const authenticate = require('../middleware/authenticate');
const asyncHandler = require('../middleware/asyncHandler');

const router = express.Router({ mergeParams: true });

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowed = ['image/jpeg', 'image/png', 'image/webp'];
    if (allowed.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('invalid_file_type'));
    }
  },
});

function handleUpload(req, res, next) {
  upload.single('photo')(req, res, (err) => {
    if (err) {
      const isSizeError = err.code === 'LIMIT_FILE_SIZE';
      return res.status(400).json({ error: isSizeError ? 'file_too_large' : 'invalid_file_type' });
    }
    next();
  });
}

router.get('/', asyncHandler(async (req, res) => {
  const items = await reviews.queryReviewsByProduct(req.params.productId);
  const reviewCount = items.length;
  const averageRating = reviewCount === 0
    ? 0
    : items.reduce((sum, r) => sum + r.rating, 0) / reviewCount;

  res.status(200).json({ reviews: items, averageRating, reviewCount });
}));

router.post('/', authenticate, handleUpload, asyncHandler(async (req, res) => {
  const productId = req.params.productId;
  const rating = Number(req.body.rating);
  const text = (req.body.text || '').trim();

  if (!Number.isInteger(rating) || rating < 1 || rating > 5 || !text) {
    return res.status(400).json({ error: 'rating (1-5) and text are required' });
  }

  const existing = await reviews.getReview(req.user.sub, productId);
  if (existing) {
    return res.status(409).json({ error: 'already reviewed this product' });
  }

  const profile = await dynamodb.getProfile(req.user.sub);
  const authorNickname = profile ? profile.nickname : req.user.email;

  let photo;
  if (req.file) {
    photo = await s3.uploadReviewPhoto(req.file.buffer, req.file.mimetype);
  }

  const moderation = await lambda.invokeModeration({
    text,
    imageBucket: photo?.bucket,
    imageKey: photo?.key,
  });

  if (!moderation.approved) {
    if (photo) await s3.deleteReviewPhoto(photo.key).catch(() => {});
    return res.status(422).json({ error: 'content_rejected', reasons: moderation.reasons });
  }

  const review = {
    userId: req.user.sub,
    productId,
    rating,
    text,
    photoUrl: photo?.url ?? null,
    photoKey: photo?.key ?? null,
    authorNickname,
    createdAt: new Date().toISOString(),
  };

  try {
    await reviews.putReview(review);
  } catch (err) {
    if (photo) await s3.deleteReviewPhoto(photo.key).catch(() => {});
    if (err.name === 'ConditionalCheckFailedException') {
      return res.status(409).json({ error: 'already reviewed this product' });
    }
    return res.status(500).json({ error: 'failed to save review' });
  }

  res.status(201).json(review);
}));

router.put('/', authenticate, handleUpload, asyncHandler(async (req, res) => {
  const productId = req.params.productId;
  const rating = Number(req.body.rating);
  const text = (req.body.text || '').trim();
  const removePhoto = req.body.removePhoto === 'true';

  if (!Number.isInteger(rating) || rating < 1 || rating > 5 || !text) {
    return res.status(400).json({ error: 'rating (1-5) and text are required' });
  }

  const existing = await reviews.getReview(req.user.sub, productId);
  if (!existing) {
    return res.status(404).json({ error: 'review not found' });
  }

  let photo;
  if (req.file) {
    photo = await s3.uploadReviewPhoto(req.file.buffer, req.file.mimetype);
  }
  // 새 사진을 올렸거나 명시적으로 제거를 요청한 경우에만 기존 사진을 나중에 지움 -
  // 둘 다 아니면(그냥 별점/텍스트만 수정) 기존 사진은 그대로 둠
  const shouldDeleteOldPhoto = !!existing.photoKey && (!!photo || removePhoto);

  // 검열은 바뀐 것만 다시 확인 - 텍스트는 항상, 이미지는 새로 첨부했을 때만
  // (안 바뀐 기존 사진을 매번 재검열하지 않음)
  const moderation = await lambda.invokeModeration({
    text,
    imageBucket: photo?.bucket,
    imageKey: photo?.key,
  });

  if (!moderation.approved) {
    if (photo) await s3.deleteReviewPhoto(photo.key).catch(() => {});
    return res.status(422).json({ error: 'content_rejected', reasons: moderation.reasons });
  }

  const updated = {
    ...existing,
    rating,
    text,
    photoUrl: photo ? photo.url : removePhoto ? null : existing.photoUrl,
    photoKey: photo ? photo.key : removePhoto ? null : existing.photoKey,
    updatedAt: new Date().toISOString(),
  };

  try {
    await reviews.updateReview(updated);
  } catch (err) {
    if (photo) await s3.deleteReviewPhoto(photo.key).catch(() => {});
    return res.status(500).json({ error: 'failed to update review' });
  }

  if (shouldDeleteOldPhoto) {
    await s3.deleteReviewPhoto(existing.photoKey).catch(() => {});
  }

  res.status(200).json(updated);
}));

router.delete('/', authenticate, asyncHandler(async (req, res) => {
  const productId = req.params.productId;
  const existing = await reviews.getReview(req.user.sub, productId);
  if (!existing) {
    return res.status(404).json({ error: 'review not found' });
  }

  await reviews.deleteReview(req.user.sub, productId);
  if (existing.photoKey) {
    await s3.deleteReviewPhoto(existing.photoKey).catch(() => {});
  }

  res.status(204).send();
}));

module.exports = router;
