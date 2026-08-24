const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const authenticate = require('../middleware/authenticate');
const admin = require('../middleware/admin');
const asyncHandler = require('../middleware/asyncHandler');
const reviews = require('../services/reviews');
const products = require('../services/products');
const s3 = require('../services/s3');
const moderationEvents = require('../services/moderationEvents');
const translate = require('../services/bedrockTranslate');
const embeddings = require('../services/embeddings');

const router = express.Router();
router.use(authenticate, admin);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (req, file, cb) => cb(null, ['image/jpeg', 'image/png', 'image/webp'].includes(file.mimetype)),
});

function productFields(body) {
  const name = String(body.name || '').trim();
  const category = String(body.category || '').trim().toUpperCase();
  const store = String(body.store || '').trim();
  const reason = String(body.reason || '').trim();
  const price = Number(body.price);
  if (
    !name || !store || !reason || !Number.isInteger(price) || price < 0 ||
    !['SNACK', 'COSMETIC', 'LIVING'].includes(category)
  ) {
    return null;
  }
  return {
    name, category, store, reason, price,
    ...(String(body.discountInfo || '').trim() ? { discountInfo: String(body.discountInfo).trim() } : {}),
  };
}

// 관리자가 올린 상품 이미지(products/ 접두어)만 교체/삭제 시 정리 대상으로 취급 - 시딩
// 스크립트가 만든 카탈로그 이미지(snack/, cosmetic/, living/ 접두어)는 여러 상품이 공유하는
// 게 아니라도 실수로 건드리지 않게 안전장치를 둠
function storedProductImageKey(product) {
  if (product.imageKey) return product.imageKey;
  try {
    const path = new URL(product.imageUrl).pathname.replace(/^\//, '');
    return path.startsWith('products/') ? path : null;
  } catch (_) {
    return null;
  }
}

async function translatedProductFields(fields) {
  try {
    return await translate.translateProduct(fields);
  } catch (err) {
    // 번역 서비스 장애가 관리자 상품 등록/수정 자체를 막지는 않게 함 - translations가
    // 없으면 Flutter가 한국어 원문을 그대로 표시함
    console.error('product translation failed', err);
    return null;
  }
}

// "AI로 찾기"가 이 상품을 관련 상품으로 찾아낼 수 있으려면 임베딩이 있어야 하는데,
// 계산 실패가 상품 등록/수정 자체를 막으면 안 되므로 번역과 동일하게 논-fatal로 처리 -
// 실패하면 embedding 없이 저장되고, embeddings.findRelevantProducts가 그런 상품은
// 알아서 건너뜀(전체 폴백 대상이 될 뿐 등록/수정 자체는 항상 성공함)
async function productEmbedding(fields) {
  try {
    return await embeddings.embedText(embeddings.buildProductEmbeddingText(fields));
  } catch (err) {
    console.error('product embedding failed', err);
    return null;
  }
}

router.get('/me', (req, res) => res.status(200).json({ admin: true }));

router.get('/reviews', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  res.status(200).json({ reviews: await reviews.listAllReviews() });
}));

router.delete('/reviews/:userId/:productId', asyncHandler(async (req, res) => {
  const existing = await reviews.getReview(req.params.userId, req.params.productId);
  if (!existing) return res.status(404).json({ error: 'review not found' });
  await reviews.deleteReview(req.params.userId, req.params.productId);
  if (existing.photoKey) await s3.deleteReviewPhoto(existing.photoKey).catch(() => {});
  // 검열 큐를 거치지 않은 일반 리뷰 삭제라 기존 moderation_events 행이 없음 - 알림용으로 새로 만듦
  await moderationEvents.createDeletionNotification(existing);
  res.status(204).send();
}));

router.get('/moderation-events', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  res.status(200).json({ events: await moderationEvents.listEvents() });
}));

router.get('/moderation-events/:eventId/image', asyncHandler(async (req, res) => {
  const event = await moderationEvents.getEvent(req.params.eventId);
  if (!event?.quarantinePhotoKey) return res.status(404).json({ error: 'image not found' });
  const object = await s3.getQuarantinePhoto(event.quarantinePhotoKey);
  res.set('Cache-Control', 'private, no-store');
  res.type(object.ContentType || 'image/jpeg');
  object.Body.pipe(res);
}));

router.patch('/moderation-events/:eventId', asyncHandler(async (req, res) => {
  const status = String(req.body.status || '').toUpperCase();
  if (!['REVIEWED', 'DISMISSED'].includes(status)) {
    return res.status(400).json({ error: 'invalid moderation status' });
  }
  const existing = await moderationEvents.getEvent(req.params.eventId);
  if (!existing) return res.status(404).json({ error: 'moderation event not found' });
  res.status(200).json(await moderationEvents.updateStatus(req.params.eventId, status));
}));

router.delete('/moderation-events/:eventId', asyncHandler(async (req, res) => {
  const existing = await moderationEvents.getEvent(req.params.eventId);
  if (!existing) return res.status(404).json({ error: 'moderation event not found' });
  if (existing.quarantinePhotoKey) {
    await s3.deleteQuarantinePhoto(existing.quarantinePhotoKey).catch(() => {});
  }
  // 완전 삭제 대신 DELETED로 소프트 삭제 - 작성자 알림함(GET /notifications)에 뜨게 함
  await moderationEvents.markDeleted(req.params.eventId);
  res.status(204).send();
}));

router.post('/products', upload.single('image'), asyncHandler(async (req, res) => {
  const fields = productFields(req.body);
  if (!fields || !req.file) {
    return res.status(400).json({ error: 'name, category, price, store, reason and image are required' });
  }
  const image = await s3.uploadProductImage(req.file.buffer, req.file.mimetype);
  const translations = await translatedProductFields(fields);
  const embedding = await productEmbedding(fields);
  const product = {
    itemId: `admin_${crypto.randomUUID()}`,
    ...fields,
    ...(translations ? { translations } : {}),
    ...(embedding ? { embedding } : {}),
    imageUrl: image.url,
    imageKey: image.key,
    createdAt: new Date().toISOString(),
  };
  await products.putProduct(product);
  res.status(201).json(product);
}));

router.put('/products/:itemId', upload.single('image'), asyncHandler(async (req, res) => {
  const existing = await products.getProduct(req.params.itemId);
  if (!existing) return res.status(404).json({ error: 'product not found' });
  const fields = productFields(req.body);
  if (!fields) return res.status(400).json({ error: 'invalid product fields' });

  let image = null;
  if (req.file) image = await s3.uploadProductImage(req.file.buffer, req.file.mimetype);
  const translations = await translatedProductFields(fields);
  const embedding = await productEmbedding(fields);
  const updated = {
    ...existing,
    ...fields,
    ...(translations ? { translations } : {}),
    ...(embedding ? { embedding } : {}),
    ...(image ? { imageUrl: image.url, imageKey: image.key } : {}),
    updatedAt: new Date().toISOString(),
  };
  // 번역에 실패했다면 변경 전 문구의 오래된 번역을 노출하지 않고 원문으로 폴백함
  if (!translations) delete updated.translations;
  // name/reason이 바뀌었을 수 있으니 임베딩은 항상 재계산 대상 - 실패 시 ...existing으로
  // 스프레드된 예전 임베딩이 새 문구랑 안 맞는 채로 남는 걸 막음(없는 게 나음, 그래야
  // findRelevantProducts가 이 상품을 "임베딩 없음"으로 취급해서 걸러냄)
  if (!embedding) delete updated.embedding;
  await products.updateProduct(updated);
  if (image) {
    const oldKey = storedProductImageKey(existing);
    if (oldKey) await s3.deleteProductImage(oldKey).catch(() => {});
  }
  res.status(200).json(updated);
}));

router.delete('/products/:itemId', asyncHandler(async (req, res) => {
  const existing = await products.getProduct(req.params.itemId);
  if (!existing) return res.status(404).json({ error: 'product not found' });
  await products.deleteProduct(req.params.itemId);
  const key = storedProductImageKey(existing);
  if (key) await s3.deleteProductImage(key).catch(() => {});
  res.status(204).send();
}));

module.exports = router;
