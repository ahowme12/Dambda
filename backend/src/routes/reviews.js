const express = require('express');
const multer = require('multer');
const reviews = require('../services/reviews');
const dynamodb = require('../services/dynamodb');
const s3 = require('../services/s3');
const sqs = require('../services/sqs');
const translate = require('../services/translate');
const authenticate = require('../middleware/authenticate');
const { optionalAuthenticate } = authenticate;
const asyncHandler = require('../middleware/asyncHandler');

const router = express.Router({ mergeParams: true });

const SUPPORTED_LANGS = ['ko', 'en', 'ja', 'zh'];

// 요청 언어로 리뷰 텍스트를 지연 번역 - 이미 그 언어로 캐싱돼 있으면 캐시만 반환,
// 처음 요청되는 언어일 때만 실제로 Translate를 호출하고 결과를 아이템에 저장해둠
async function withTranslatedText(review, lang) {
  if (!lang || review.sourceLang === lang) return review;
  const cached = review.translations?.[lang];
  if (cached) return { ...review, text: cached };

  try {
    const { translatedText, sourceLang } = await translate.translateText(review.text, lang);
    if (sourceLang === lang) {
      // 번역해보니 원문 언어가 요청 언어와 같았던 경우 - 재번역 불필요하니 sourceLang만 캐싱
      await reviews.updateReview({ ...review, sourceLang }).catch(() => {});
      return { ...review, sourceLang };
    }
    const updatedTranslations = { ...(review.translations || {}), [lang]: translatedText };
    await reviews
      .updateReview({ ...review, sourceLang, translations: updatedTranslations })
      .catch(() => {});
    return { ...review, text: translatedText, sourceLang, translations: updatedTranslations };
  } catch (err) {
    // 번역 실패해도 리뷰 자체는 보여줘야 하니 원문 그대로 반환 (fail-open)
    console.error('review translation failed', err);
    return review;
  }
}

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

router.get('/', optionalAuthenticate, asyncHandler(async (req, res) => {
  const items = await reviews.queryReviewsByProduct(req.params.productId);
  // isVisible이 없는 건(이 기능 이전에 만들어진 리뷰) 그대로 공개 - 검열 통과/대기 여부와 무관하게
  // isVisible=false로 명시된 것만 "검토중"으로 숨김
  const visible = items.filter((item) => item.isVisible !== false);
  const ownPending = req.user
    ? items.find((item) => item.userId === req.user.sub && item.isVisible === false)
    : undefined;
  const list = ownPending ? [ownPending, ...visible] : visible;

  const reviewCount = visible.length;
  const averageRating = reviewCount === 0
    ? 0
    : visible.reduce((sum, r) => sum + r.rating, 0) / reviewCount;

  const lang = SUPPORTED_LANGS.includes(req.query.lang) ? req.query.lang : null;
  const translated = await Promise.all(list.map((item) => withTranslatedText(item, lang)));

  res.status(200).json({ reviews: translated, averageRating, reviewCount });
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

  // 사진은 검열 전이라 비공개 quarantine 버킷에 먼저 올라감 - worker Lambda가 승인해야
  // review_photos(공개)로 옮겨짐
  let photoKey;
  if (req.file) {
    photoKey = await s3.uploadToQuarantine(req.file.buffer, req.file.mimetype);
  }

  // 검열 결과를 기다리지 않고 즉시 저장(PENDING/비공개) - 실제 검열은 review_pipeline이
  // 비동기로 수행하고 끝나면 moderationStatus/isVisible/photoUrl을 갱신함
  const review = {
    userId: req.user.sub,
    productId,
    rating,
    text,
    photoUrl: null,
    photoKey: photoKey ?? null,
    authorNickname,
    createdAt: new Date().toISOString(),
    moderationStatus: 'PENDING',
    isVisible: false,
  };

  try {
    await reviews.putReview(review);
  } catch (err) {
    if (photoKey) await s3.deleteQuarantinePhoto(photoKey).catch(() => {});
    if (err.name === 'ConditionalCheckFailedException') {
      return res.status(409).json({ error: 'already reviewed this product' });
    }
    return res.status(500).json({ error: 'failed to save review' });
  }

  await sqs
    .sendReviewModerationMessage({ userId: review.userId, productId, text, photoKey })
    .catch((err) => {
      // 큐 전송 실패해도 리뷰 저장 자체는 이미 성공했으니 요청은 성공으로 응답 -
      // PENDING 상태로 남아있는 리뷰는 로그로 남겨서 운영 중 확인 필요
      console.error('failed to enqueue review moderation', err);
    });

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

  // 새 사진은 quarantine에 올라감(재검열 대상) - 기존 사진을 그대로 두는 경우는 이미
  // review_photos(공개)에 있으므로 quarantine을 거치지 않음
  let newPhotoKey;
  if (req.file) {
    newPhotoKey = await s3.uploadToQuarantine(req.file.buffer, req.file.mimetype);
  }

  // 사진 제거만 요청(새 사진 없음)한 경우는 비동기 검열 대상이 아니라 여기서 바로 처리
  if (!newPhotoKey && removePhoto && existing.photoKey) {
    await s3.deleteReviewPhoto(existing.photoKey).catch(() => {});
  }

  // 수정도 등록과 동일하게 PENDING/비공개로 되돌리고 재검열 큐로 보냄. 새 사진이 없으면
  // photoKey를 안 보내서(worker가 이미지 재검열을 생략) 기존 photoUrl이 그대로 유지됨 -
  // 텍스트는 항상 재검열, 안 바뀐 기존 사진은 재검열 안 하는 기존 동기 방식의 동작을 그대로 유지
  const updated = {
    ...existing,
    rating,
    text,
    photoUrl: newPhotoKey ? null : removePhoto ? null : existing.photoUrl,
    photoKey: newPhotoKey ?? (removePhoto ? null : existing.photoKey),
    updatedAt: new Date().toISOString(),
    moderationStatus: 'PENDING',
    isVisible: false,
  };

  try {
    await reviews.updateReview(updated);
  } catch (err) {
    if (newPhotoKey) await s3.deleteQuarantinePhoto(newPhotoKey).catch(() => {});
    return res.status(500).json({ error: 'failed to update review' });
  }

  // 새 사진으로 교체된 경우 예전 공개 사진은 더 이상 필요 없으니 정리
  if (newPhotoKey && existing.photoKey && !removePhoto) {
    await s3.deleteReviewPhoto(existing.photoKey).catch(() => {});
  }

  await sqs
    .sendReviewModerationMessage({ userId: updated.userId, productId, text, photoKey: newPhotoKey })
    .catch((err) => {
      console.error('failed to enqueue review moderation', err);
    });

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
