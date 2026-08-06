const { BedrockRuntimeClient, ConverseCommand } = require('@aws-sdk/client-bedrock-runtime');
const config = require('../config');
const websearch = require('./websearch');

const client = new BedrockRuntimeClient({ region: config.awsRegion });

const WEB_SEARCH_TOOL = {
  toolSpec: {
    name: 'web_search',
    description:
      '실시간 웹 검색. 카탈로그 정보로 답할 수 없는 질문(현재 가격, 실시간 재고, 최신 뉴스 등)에만 사용',
    inputSchema: {
      json: {
        type: 'object',
        properties: { query: { type: 'string', description: '검색어' } },
        required: ['query'],
      },
    },
  },
};

// TAVILY_API_KEY가 없으면(로컬 개발 등) 도구 자체를 안 줘서 Nova가 호출을 시도하지 않게 함 -
// 시도했는데 도구가 없으면 에러가 나므로, 아예 선택지에서 빼는 게 안전함
function toolConfig() {
  return config.tavilyApiKey ? { tools: [WEB_SEARCH_TOOL] } : undefined;
}

async function runTool(name, input) {
  if (name === 'web_search') {
    const results = await websearch.search(input.query);
    return JSON.stringify(results);
  }
  throw new Error(`unknown tool: ${name}`);
}

// system 프롬프트 + 첫 사용자 메시지로 시작해서, 모델이 도구 호출을 요청하면 실행하고
// 결과를 대화에 이어붙여 다시 물어보는 걸 반복함 (Bedrock Converse API의 표준 tool-use 루프)
async function converse(systemText, userText) {
  const messages = [{ role: 'user', content: [{ text: userText }] }];

  for (let round = 0; round < 3; round += 1) {
    const result = await client.send(
      new ConverseCommand({
        modelId: config.bedrockModelId,
        system: [{ text: systemText }],
        messages,
        inferenceConfig: { maxTokens: 500, temperature: 0.3 },
        toolConfig: toolConfig(),
      })
    );

    const message = result.output.message;
    if (result.stopReason !== 'tool_use') {
      return message.content.map((c) => c.text || '').join('');
    }

    messages.push(message);
    const toolResults = await Promise.all(
      message.content
        .filter((c) => c.toolUse)
        .map(async (c) => {
          try {
            const output = await runTool(c.toolUse.name, c.toolUse.input);
            return {
              toolResult: {
                toolUseId: c.toolUse.toolUseId,
                content: [{ text: output }],
              },
            };
          } catch (err) {
            return {
              toolResult: {
                toolUseId: c.toolUse.toolUseId,
                content: [{ text: `tool failed: ${err.message}` }],
                status: 'error',
              },
            };
          }
        })
    );
    messages.push({ role: 'user', content: toolResults });
  }

  return '답변을 만드는 데 실패했어요. 다시 시도해주세요.';
}

async function askAboutProduct(product, question) {
  const productContext = JSON.stringify({
    name: product.name,
    category: product.category,
    reason: product.reason,
    store: product.store,
    price: product.price,
    discountInfo: product.discountInfo,
  });

  const systemText = `당신은 여행 상품 앱 "담다"의 상품 안내 도우미입니다.
아래 상품 정보에 근거해서 답하세요. 실시간 가격/판매처처럼 이 정보에 없는 내용은
web_search 도구로 실제로 검색해서 답하고, 검색해도 못 찾으면 모른다고 솔직히 답하세요.
지어내지 마세요. 답변은 2~3문장으로 간결하게 하세요.

상품 정보:
${productContext}`;

  return converse(systemText, question);
}

// 홈 화면 "AI로 찾기" - 카탈로그 전체를 컨텍스트로 주고 사용자 요청에 맞는 상품을 추천.
// 매칭된 상품을 화면에서 하이라이트할 수 있게 itemId 배열을 JSON으로 받아옴
async function findProducts(catalog, query) {
  const catalogContext = JSON.stringify(
    catalog.map((p) => ({
      itemId: p.itemId,
      name: p.name,
      category: p.category,
      reason: p.reason,
      price: p.price,
    }))
  );

  const systemText = `당신은 여행 상품 앱 "담다"의 상품 추천 도우미입니다.
아래 상품 목록 중에서 사용자 요청에 가장 잘 맞는 상품을 최대 5개 골라 추천하세요.
목록에 없는 내용(실시간 가격 비교 등)이 필요하면 web_search 도구를 쓰세요.
반드시 아래 JSON 형식으로만 답하세요(다른 텍스트 없이):
{"answer": "추천 이유 2~3문장", "productIds": ["itemId1", "itemId2"]}

상품 목록:
${catalogContext}`;

  const raw = await converse(systemText, query);
  try {
    const jsonText = raw.slice(raw.indexOf('{'), raw.lastIndexOf('}') + 1);
    const parsed = JSON.parse(jsonText);
    return {
      answer: typeof parsed.answer === 'string' ? parsed.answer : raw,
      productIds: Array.isArray(parsed.productIds) ? parsed.productIds : [],
    };
  } catch (_) {
    // 모델이 JSON 형식을 안 지켰을 때 - 답변 텍스트는 그대로 보여주고 매칭 하이라이트만 포기
    return { answer: raw, productIds: [] };
  }
}

module.exports = { askAboutProduct, findProducts };
