const express = require('express');
const authenticate = require('../middleware/authenticate');
const asyncHandler = require('../middleware/asyncHandler');
const moderationEvents = require('../services/moderationEvents');

const router = express.Router();
router.use(authenticate);

router.get('/', asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'no-store');
  const notifications = await moderationEvents.listUnreadNotifications(req.user.sub);
  res.status(200).json({ notifications });
}));

router.patch('/:eventId/read', asyncHandler(async (req, res) => {
  await moderationEvents.markNotificationRead(req.params.eventId, req.user.sub);
  res.status(204).send();
}));

module.exports = router;
