const cognito = require('../services/cognito');

// Authorization: Bearer <accessToken> -> Cognito GetUser로 검증 -> req.user에 sub/email 부착
async function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'missing bearer token' });
  }

  try {
    req.user = await cognito.getUserByAccessToken(token);
    next();
  } catch (err) {
    res.status(401).json({ error: 'invalid or expired token' });
  }
}

// GET /reviews처럼 로그인 없이도 접근 가능해야 하지만, 로그인된 요청이면 req.user를 채워서
// "내 pending 리뷰"를 같이 보여줄 수 있게 하는 버전 - 토큰이 없거나 무효해도 401 없이 통과시킴
async function optionalAuthenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) {
    return next();
  }

  try {
    req.user = await cognito.getUserByAccessToken(token);
  } catch (err) {
    // 토큰이 만료/무효해도 공개 조회 자체는 막지 않음
  }
  next();
}

module.exports = authenticate;
module.exports.optionalAuthenticate = optionalAuthenticate;
