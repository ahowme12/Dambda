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

router.post('/password/forgot', asyncHandler(async (req, res) => {
  const email = String(req.body?.email || '').trim().toLowerCase();
  if (!email) return res.status(400).json({ error: 'email is required' });

  try {
    await cognito.forgotPassword(email);
  } catch (err) {
    // 가입 여부를 외부에 노출하지 않는다 - 존재하는 계정이면 Cognito가 이메일을 발송한다
    if (!['UserNotFoundException', 'InvalidParameterException'].includes(err.name)) {
      throw err;
    }
  }
  res.status(204).send();
}));

router.post('/password/confirm', asyncHandler(async (req, res) => {
  const email = String(req.body?.email || '').trim().toLowerCase();
  const code = String(req.body?.code || '').trim();
  const newPassword = String(req.body?.newPassword || '');
  if (!email || !code || !newPassword) {
    return res.status(400).json({ error: 'email, code and newPassword are required' });
  }

  try {
    await cognito.confirmForgotPassword(email, code, newPassword);
    res.status(204).send();
  } catch (err) {
    if (err.name === 'CodeMismatchException') {
      return res.status(400).json({ error: 'invalid verification code' });
    }
    if (err.name === 'ExpiredCodeException') {
      return res.status(400).json({ error: 'verification code expired' });
    }
    if (err.name === 'InvalidPasswordException') {
      return res.status(400).json({ error: 'password does not meet requirements' });
    }
    return res.status(400).json({ error: 'could not reset password' });
  }
}));

// 소셜 로그인 사용자는 Cognito엔 자동 생성되지만 앱 전용 프로필은 DynamoDB에 없으므로
// 첫 로그인 때 한 번만 기본 프로필을 만든다
router.post('/social/session', authenticate, asyncHandler(async (req, res) => {
  let profile = await dynamodb.getProfile(req.user.sub);
  if (!profile) {
    const email = req.user.email;
    const nickname = req.user.name || email?.split('@')[0] || 'DAMBDA traveler';
    profile = {
      userId: req.user.sub,
      email,
      nickname,
      country: 'OTHER',
      authProvider: 'social',
      createdAt: new Date().toISOString(),
    };
    await dynamodb.putProfile(profile);
  }
  res.status(200).json(profile);
}));

module.exports = router;
