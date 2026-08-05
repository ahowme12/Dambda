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

module.exports = authenticate;
