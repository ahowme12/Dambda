FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
# ci는 lockfile 그대로 설치만 하고 의존성 버전 재해석을 안 해서 install보다 빠름 -
# lockfile이 package.json이랑 안 맞으면 바로 에러내는 것도 오히려 안전함
RUN npm ci --omit=dev --no-audit --no-fund
COPY src ./src
EXPOSE 80
ENV PORT=80
CMD ["node", "src/server.js"]
