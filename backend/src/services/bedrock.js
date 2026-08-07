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

// Nova가 가끔 최종 답변 앞에 <thinking>...내부 추론...</thinking>을 텍스트로 그대로
// 끼워넣을 때가 있음(구조화된 별도 필드가 아니라 답변 본문에 섞여서 옴) - 사용자에게
// 노출하면 안 되는 내용이라 최종 반환 직전에 걷어냄
function stripThinking(text) {
  return text.replace(/<thinking>[\s\S]*?<\/thinking>/gi, '').trim();
}

// history: 이전 대화 턴 [{role: 'user'|'assistant', text}, ...] - 클라이언트(ChatState)가
// 들고 있다가 매 요청마다 통째로 다시 보내줌(서버는 세션을 저장 안 하는 무상태 구조).
// role이 아닌 값은 걸러내고, 너무 길어지는 걸 막기 위해 최근 10턴(20개)만 사용
function toBedrockMessages(history, userText) {
  const recent = (history || [])
    .filter((h) => h.role === 'user' || h.role === 'assistant')
    .slice(-20);
  return [
    ...recent.map((h) => ({ role: h.role, content: [{ text: h.text }] })),
    { role: 'user', content: [{ text: userText }] },
  ];
}

// system 프롬프트 + 대화 히스토리로 시작해서, 모델이 도구 호출을 요청하면 실행하고
// 결과를 대화에 이어붙여 다시 물어보는 걸 반복함 (Bedrock Converse API의 표준 tool-use 루프)
async function converse(systemText, userText, history) {
  const messages = toBedrockMessages(history, userText);

  for (let round = 0; round < 3; round += 1) {
    const result = await client.send(
      new ConverseCommand({
        modelId: config.bedrockModelId,
        system: [{ text: systemText }],
        messages,
        // findProducts는 상품 여러 개 설명 + productIds 배열까지 JSON 하나에 담아야 해서
        // 500으로는 한국어 답변이 종종 중간에 잘림(잘리면 JSON.parse가 깨져서 raw JSON이
        // 그대로 노출되는 문제로 이어짐) - maxTokens는 상한일 뿐 실제 생성량만큼만 과금되니
        // 여유 있게 올려도 짧은 답변(askAboutProduct)엔 비용 영향 없음
        inferenceConfig: { maxTokens: 1000, temperature: 0.3 },
        toolConfig: toolConfig(),
      })
    );

    const message = result.output.message;
    if (result.stopReason !== 'tool_use') {
      return stripThinking(message.content.map((c) => c.text || '').join(''));
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
지어내지 마세요. 내부적으로 생각하는 과정을 답변에 쓰지 말고, 최종 답변만 출력하세요.
답변은 2~3문장으로 간결하게 하세요.

상품 정보:
${productContext}`;

  return converse(systemText, question);
}

// 홈 화면 채팅형 "AI로 찾기" - 카탈로그 전체를 컨텍스트로 주고 사용자 요청에 맞는 상품을 추천.
// 매칭된 상품을 화면에서 하이라이트할 수 있게 itemId 배열을 JSON으로 받아옴.
// history를 넘기면 이전 대화를 이어받아 답함(예: "저거 말고 더 싼 거")
async function findProducts(catalog, query, history) {
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
가능하면 되묻지 말고 최선의 추천을 먼저 제시하세요 - 요청이 모호해도(예: "제일 맛있는거")
설명(reason)이나 카테고리를 근거로 가장 그럴듯한 후보를 고르세요. 정말 필요할 때만
추천과 함께 짧게 되물어도 됩니다. 상품이 하나도 안 맞으면 그때만 productIds를 빈 배열로 두세요.
이전 대화가 있으면 그 맥락을 이어서 답하세요(예: "그거 말고 더 싼거"). 목록에 없는 내용
(실시간 가격 비교 등)이 필요하면 web_search 도구를 쓰세요.
내부적으로 생각하는 과정은 출력하지 말고, 반드시 아래 JSON 형식으로만 답하세요
(설명이나 생각 과정 없이 JSON 하나만):
{"answer": "추천 이유 2~3문장", "productIds": ["itemId1", "itemId2"]}

상품 목록:
${catalogContext}`;

  const raw = await converse(systemText, query, history);
  try {
    const jsonText = raw.slice(raw.indexOf('{'), raw.lastIndexOf('}') + 1);
    const parsed = JSON.parse(jsonText);
    return {
      answer: typeof parsed.answer === 'string' ? parsed.answer : raw,
      productIds: Array.isArray(parsed.productIds) ? parsed.productIds : [],
    };
  } catch (_) {
    // JSON 파싱 실패(주로 응답이 중간에 잘린 경우) - raw를 그대로 보여주면 "{"answer":..."
    // 같은 JSON 문법이 그대로 노출되니, "answer" 필드 값만이라도 정규식으로 건져서 보여줌.
    // 그마저 안 되면(answer 문자열 자체가 잘려 닫는 따옴표가 없음) 일반 안내 문구로 대체
    const match = raw.match(/"answer"\s*:\s*"((?:[^"\\]|\\.)*)"/);
    if (match) {
      try {
        return { answer: JSON.parse(`"${match[1]}"`), productIds: [] };
      } catch (_) {
        return { answer: match[1], productIds: [] };
      }
    }
    return { answer: '답변을 만드는 데 실패했어요. 다시 시도해주세요.', productIds: [] };
  }
}

module.exports = { askAboutProduct, findProducts };
