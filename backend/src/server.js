const express = require('express');
const cors = require('cors');
const config = require('./config');
const authRoutes = require('./routes/auth');
const productsRoutes = require('./routes/products');
const reviewsRoutes = require('./routes/reviews');
const adminRoutes = require('./routes/admin');
const notificationsRoutes = require('./routes/notifications');
const { metricsMiddleware, startMetricsServer } = require('./metrics');

const app = express();
app.use(cors());
app.use(express.json());
app.use(metricsMiddleware);

// ALB 타겟그룹 헬스체크가 무인증으로 이 경로를 침
app.get('/', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.use('/auth', authRoutes);
app.use('/products', productsRoutes);
app.use('/products/:productId/reviews', reviewsRoutes);
app.use('/admin', adminRoutes);
app.use('/notifications', notificationsRoutes);

// 라우트에서 처리 안 한 예외의 최종 방어선 (asyncHandler가 여기로 넘겨줌) -
// 이게 없으면 하나의 요청에서 난 에러가 서버 프로세스 전체를 죽임
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: 'internal server error' });
});

app.listen(config.port, () => {
  console.log(`dambda-backend listening on port ${config.port}`);
});

// ADOT 사이드카(enable_prometheus=true일 때만 실제로 존재)가 긁어갈 포트 - 사이드카가 없어도
// 이 서버 자체는 항상 떠서 로컬 curl로도 확인 가능함
startMetricsServer(Number(process.env.METRICS_PORT || 9090));
