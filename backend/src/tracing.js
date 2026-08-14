// server.js가 express/AWS SDK를 require하기 전에 먼저 실행돼야 자동계측이 걸리므로,
// Dockerfile CMD에서 `node --require ./src/tracing.js src/server.js`로 진입점보다
// 먼저 로드함. 이미지는 하나로 유지하고 ENABLE_TRACING 환경변수로만 켜고 끔 - 꺼져있으면
// 아무 것도 안 하고 바로 리턴(오버헤드 없음)
if (process.env.ENABLE_TRACING === 'true') {
  const { NodeSDK } = require('@opentelemetry/sdk-node');
  const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
  const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');

  // 같은 ECS 태스크 안의 ADOT 사이드카(otlp receiver, 4318 포트)로 보냄 - 같은 태스크
  // 내부 통신이라 인증 불필요(ADOT -> X-Ray 구간에서만 태스크 롤로 SigV4 인증함)
  const sdk = new NodeSDK({
    serviceName: 'dambda-backend',
    traceExporter: new OTLPTraceExporter({ url: 'http://127.0.0.1:4318/v1/traces' }),
    instrumentations: [getNodeAutoInstrumentations()],
  });

  sdk.start();

  process.on('SIGTERM', () => {
    sdk.shutdown().finally(() => process.exit(0));
  });
}
