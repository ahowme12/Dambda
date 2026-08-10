const express = require('express');
const cognito = require('../services/cognito');
const dynamodb = require('../services/dynamodb');
const authenticate = require('../middleware/authenticate');
const asyncHandler = require('../middleware/asyncHandler');

const router = express.Router();

router.post('/signup', asyncHandler(async (req, res) => {
  const { email, password, nickname, country } = req.body || {};
  if (!email || !password || !nickname || !country) {
    return res.status(400).json({ error: 'email, password, nickname, country are all required' });
  }

  let sub;
  try {
    sub = await cognito.createUser(email);
  } catch (err) {
    if (err.name === 'UsernameExistsException') {
      return res.status(409).json({ error: 'email already registered' });
    }
    return res.status(400).json({ error: err.message });
  }

  try {
    await cognito.setPassword(email, password);
  } catch (err) {
    // 비밀번호 설정 실패 -> 방금 만든 계정을 그대로 두면 비번 없는 고아 계정이 됨. 최선을 다해 정리
    await cognito.deleteUser(email).catch(() => {});
    if (err.name === 'InvalidPasswordException') {
      return res.status(400).json({ error: 'password does not meet requirements (min 8 chars, upper/lower/number)' });
    }
    return res.status(400).json({ error: err.message });
  }

  const createdAt = new Date().toISOString();
  try {
    await dynamodb.putProfile({ userId: sub, email, nickname, country, createdAt });
  } catch (err) {
    await cognito.deleteUser(email).catch(() => {});
    return res.status(500).json({ error: 'failed to save profile' });
  }

  res.status(201).json({ userId: sub, email, nickname, country });
}));

router.post('/login', asyncHandler(async (req, res) => {
  const { email, password } = req.body || {};
  if (!email || !password) {
    return res.status(400).json({ error: 'email and password are required' });
  }

  try {
    const tokens = await cognito.login(email, password);
    res.status(200).json(tokens);
  } catch (err) {
    // 이메일이 없는지 비번이 틀렸는지 구분해서 알려주지 않음 (계정 존재 여부 노출 방지)
    res.status(401).json({ error: 'invalid email or password' });
  }
}));

router.post('/refresh', asyncHandler(async (req, res) => {
  const { refreshToken } = req.body || {};
  if (!refreshToken) {
    return res.status(400).json({ error: 'refreshToken is required' });
  }

  try {
    const tokens = await cognito.refresh(refreshToken);
    res.status(200).json(tokens);
  } catch (err) {
    // 리프레시 토큰 자체가 만료/폐기됨 - 재로그인이 필요하다는 뜻으로 401
    res.status(401).json({ error: 'refresh token invalid or expired' });
  }
}));

router.get('/me', authenticate, asyncHandler(async (req, res) => {
  const profile = await dynamodb.getProfile(req.user.sub);
  if (!profile) {
    return res.status(404).json({ error: 'profile not found' });
  }
  res.status(200).json(profile);
}));

module.exports = router;
