const express = require('express');
const products = require('../services/products');
const productLikes = require('../services/productLikes');
const authenticate = require('../middleware/authenticate');
const asyncHandler = require('../middleware/asyncHandler');

const router = express.Router();

router.get('/', asyncHandler(async (req, res) => {
  res.status(200).json({ products: await products.listProducts() });
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
