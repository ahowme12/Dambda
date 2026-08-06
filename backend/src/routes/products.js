const express = require('express');
const products = require('../services/products');
const productLikes = require('../services/productLikes');
const bedrock = require('../services/bedrock');
const authenticate = require('../middleware/authenticate');
const asyncHandler = require('../middleware/asyncHandler');

const router = express.Router();

router.get('/', asyncHandler(async (req, res) => {
  res.status(200).json({ products: await products.listProducts() });
}));

router.post('/:productId/ask', asyncHandler(async (req, res) => {
  const question = (req.body.question || '').trim();
  if (!question) {
    return res.status(400).json({ error: 'question is required' });
  }

  const product = await products.getProduct(req.params.productId);
  if (!product) {
    return res.status(404).json({ error: 'product not found' });
  }

  const answer = await bedrock.askAboutProduct(product, question);
  res.status(200).json({ answer });
}));

router.post('/recommend', asyncHandler(async (req, res) => {
  const query = (req.body.query || '').trim();
  if (!query) {
    return res.status(400).json({ error: 'query is required' });
  }
  // 서버는 대화를 저장 안 함(무상태) - 클라이언트(ChatState)가 들고 있다가 매번 통째로 보냄
  const history = Array.isArray(req.body.history) ? req.body.history : [];

  const catalog = await products.listProducts();
  const result = await bedrock.findProducts(catalog, query, history);
  res.status(200).json(result);
}));

router.get('/likes/mine', authenticate, asyncHandler(async (req, res) => {
  const productIds = await productLikes.likedProductIdsForUser(req.user.sub);
  res.status(200).json({ productIds });
}));

router.put('/:productId/like', authenticate, asyncHandler(async (req, res) => {
  await productLikes.like(req.user.sub, req.params.productId);
  res.status(204).send();
}));

router.delete('/:productId/like', authenticate, asyncHandler(async (req, res) => {
  await productLikes.unlike(req.user.sub, req.params.productId);
  res.status(204).send();
}));

module.exports = router;
