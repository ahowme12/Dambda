const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');
const config = require('../config');

// Converse API는 임베딩을 지원 안 해서(텍스트 생성 전용) Titan Embed는 InvokeModel로 별도 호출함.
// bedrock.js의 client와 리전은 같지만 API 모양이 달라 클라이언트를 따로 둠
const client = new BedrockRuntimeClient({ region: config.awsRegion });

async function embedText(text) {
  const response = await client.send(
    new InvokeModelCommand({
      modelId: config.bedrockEmbeddingModelId,
      contentType: 'application/json',
      accept: 'application/json',
      body: JSON.stringify({ inputText: text }),
    })
  );
  const parsed = JSON.parse(new TextDecoder().decode(response.body));
  return parsed.embedding;
}

// 저장 시점(admin/seed)과 조회 시점(findRelevantProducts)이 반드시 같은 조립 방식을 써야
// 벡터가 같은 의미공간에 놓이므로, 이 함수 하나로만 상품 임베딩용 텍스트를 만듦
function buildProductEmbeddingText(product) {
  return [product.name, product.category, product.reason].filter(Boolean).join('\n');
}

function cosineSimilarity(a, b) {
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i += 1) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

// 카탈로그가 topK보다 작으면 지금 규모에선 필터링해봐야 의미가 없으니 Bedrock 호출 없이
// 그대로 반환함 - 카탈로그가 topK를 넘어설 때부터 실제로 "관련 있는 것만 추리기"가 시작됨
async function findRelevantProducts(catalog, query, topK = 15) {
  if (catalog.length <= topK) return catalog;

  let queryEmbedding;
  try {
    queryEmbedding = await embedText(query);
  } catch (err) {
    // 질의 임베딩이 실패해도 추천 자체가 죽으면 안 되니 필터링 없이 전체 카탈로그로 폴백
    // (임베딩 붙이기 전의 기존 동작과 동일)
    console.error('embeddings: query embedding failed, falling back to full catalog', err);
    return catalog;
  }

  const withEmbedding = catalog.filter((p) => Array.isArray(p.embedding));
  // embedding이 하나도 없으면(아직 임베딩 없이 시딩된 옛 데이터 등) 필터링할 근거 자체가
  // 없으니 빈 목록을 주는 것보다 기존 동작(전체 카탈로그)으로 폴백하는 게 안전함
  if (withEmbedding.length === 0) return catalog;

  return withEmbedding
    .map((p) => ({ product: p, score: cosineSimilarity(queryEmbedding, p.embedding) }))
    .sort((a, b) => b.score - a.score)
    .slice(0, topK)
    .map((entry) => entry.product);
}

module.exports = { embedText, buildProductEmbeddingText, cosineSimilarity, findRelevantProducts };
