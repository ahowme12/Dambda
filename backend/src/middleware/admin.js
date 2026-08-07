const cognito = require('../services/cognito');

// authenticate 미들웨어 다음에 붙여씀 - req.user.username(Cognito username)이 "admin"
// 그룹 소속인지 확인. 일반 유저는 403으로 막힘
async function admin(req, res, next) {
  try {
    if (!(await cognito.isAdmin(req.user.username))) {
      return res.status(403).json({ error: 'admin access required' });
    }
    next();
  } catch (err) {
    next(err);
  }
}

module.exports = admin;
