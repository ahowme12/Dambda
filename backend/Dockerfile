FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
# ci는 lockfile 그대로 설치만 하고 의존성 버전 재해석을 안 해서 install보다 빠름 -
# lockfile이 package.json이랑 안 맞으면 바로 에러내는 것도 오히려 안전함 
RUN npm ci --omit=dev --no-audit --no-fund
COPY src ./src
EXPOSE 80
ENV PORT=80
# --require로 server.js보다 먼저 계측을 걸어야 http/express/AWS SDK 자동계측이 붙음.
# ENABLE_TRACING=false(기본)면 tracing.js 자체가 즉시 리턴해서 오버헤드 없음
CMD ["node", "--require", "./src/tracing.js", "src/server.js"]
