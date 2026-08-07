const http = require('http');
const client = require('prom-client');

const register = new client.Registry();
client.collectDefaultMetrics({ register, prefix: 'dambda_' });

const httpRequests = new client.Counter({
  name: 'dambda_http_requests_total',
  help: 'Total number of HTTP requests handled by the backend',
  labelNames: ['method', 'status_code'],
  registers: [register],
});

const httpDuration = new client.Histogram({
  name: 'dambda_http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'status_code'],
  buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
  registers: [register],
});

const requestsInFlight = new client.Gauge({
  name: 'dambda_http_requests_in_flight',
  help: 'Number of HTTP requests currently being handled',
  registers: [register],
});

function metricsMiddleware(req, res, next) {
  requestsInFlight.inc();
  const started = process.hrtime.bigint();
  res.on('finish', () => {
    const statusCode = String(res.statusCode);
    const elapsedSeconds = Number(process.hrtime.bigint() - started) / 1e9;
    httpRequests.inc({ method: req.method, status_code: statusCode });
    httpDuration.observe({ method: req.method, status_code: statusCode }, elapsedSeconds);
    requestsInFlight.dec();
  });
  next();
}

// dambda 인프라의 compute 모듈이 enable_prometheus=true일 때 같은 태스크 안 ADOT
// 사이드카가 이 포트를 긁어서 Amazon Managed Prometheus로 remote-write함(모듈 주석 참고).
// enable_prometheus=false(기본값)여도 이 서버 자체는 항상 뜸 - 아무도 스크레이프 안 하면
// 그냥 아무 비용도 안 드는 로컬 HTTP 서버일 뿐이라 무해함
function startMetricsServer(port = 9090) {
  const server = http.createServer(async (req, res) => {
    if (req.url !== '/metrics') {
      res.writeHead(404).end('not found');
      return;
    }
    try {
      res.writeHead(200, { 'Content-Type': register.contentType });
      res.end(await register.metrics());
    } catch (error) {
      res.writeHead(500).end('metrics collection failed');
    }
  });
  server.listen(port, '0.0.0.0', () => {
    console.log(`dambda metrics listening on port ${port}`);
  });
  return server;
}

module.exports = { metricsMiddleware, startMetricsServer };
