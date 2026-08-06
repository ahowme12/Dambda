const { BedrockRuntimeClient, ConverseCommand } = require('@aws-sdk/client-bedrock-runtime');
const config = require('../config');

const client = new BedrockRuntimeClient({ region: config.awsRegion });

const SYSTEM_PROMPT = `당신은 여행 상품 앱 "담다"의 상품 안내 도우미입니다.
아래 제공된 상품 정보에 근거해서만 답하세요.
실시간 가격, 재고, 판매처 비교처럼 이 정보에 없는 내용을 물어보면
지어내지 말고 "실시간 가격/판매처 정보는 제공하지 않아요"라고 솔직히 답하세요.
답변은 2~3문장으로 간결하게 하세요.`;

async function askAboutProduct(product, question) {
  const productContext = JSON.stringify({
    name: product.name,
    category: product.category,
    reason: product.reason,
    store: product.store,
    price: product.price,
    discountInfo: product.discountInfo,
  });

  const result = await client.send(
    new ConverseCommand({
      modelId: config.bedrockModelId,
      system: [{ text: `${SYSTEM_PROMPT}\n\n상품 정보:\n${productContext}` }],
      messages: [{ role: 'user', content: [{ text: question }] }],
      inferenceConfig: { maxTokens: 300, temperature: 0.3 },
    })
  );

  return result.output.message.content[0].text;
}

module.exports = { askAboutProduct };
