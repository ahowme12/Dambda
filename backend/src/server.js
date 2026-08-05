const express = require('express');
const cors = require('cors');
const config = require('./config');
const authRoutes = require('./routes/auth');
const productsRoutes = require('./routes/products');
const reviewsRoutes = require('./routes/reviews');

const app = express();
app.use(cors());
app.use(express.json());

// ALB 타겟그룹 헬스체크가 무인증으로 이 경로를 침
app.get('/', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.use('/auth', authRoutes);
app.use('/products', productsRoutes);
app.use('/products/:productId/reviews', reviewsRoutes);

// 라우트에서 처리 안 한 예외의 최종 방어선 (asyncHandler가 여기로 넘겨줌) -
// 이게 없으면 하나의 요청에서 난 에러가 서버 프로세스 전체를 죽임
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'internal server error' });
});

app.listen(config.port, () => {
  console.log(`dambda-backend listening on port ${config.port}`);
});
