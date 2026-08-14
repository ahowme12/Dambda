const { BedrockRuntimeClient, ConverseCommand } = require('@aws-sdk/client-bedrock-runtime');
const config = require('../config');

// bedrock.js와 별개 클라이언트 - 순수 번역용이라 tool-use 루프(converse())가 필요 없음.
// Bedrock InvokeModel은 계정 기본 TPS가 낮아서(특히 seed-products.js처럼 짧은 시간에 여러
// 상품을 처리할 때) ThrottlingException이 나기 쉬움 - maxAttempts를 올려서 SDK가 지수
// 백오프로 알아서 재시도하게 함(기본값 3회로는 부족해서 겪은 실제 실패)
const client = new BedrockRuntimeClient({ region: config.awsRegion, maxAttempts: 8 });

function stripWrappingQuotes(text) {
  const trimmed = text.trim();
  if (trimmed.length >= 2 && trimmed[0] === '"' && trimmed[trimmed.length - 1] === '"') {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

// Translate API의 SourceLanguageCode:'auto' + DetectedLanguageLowConfidenceException 재시도
// 로직이 통째로 필요 없어짐 - LLM은 원문 언어를 미리 알려주지 않아도 번역 과정에서 알아서
// 이해하므로 별도 언어 감지 호출 자체가 불필요함. 이 프로젝트의 사용자 입력(리뷰/상품)은
// 전부 한국어 원문이라는 기존 전제는 그대로 유지(sourceLang 반환값은 호출부 호환용)
async function translateText(text, targetLang) {
  const result = await client.send(
    new ConverseCommand({
      modelId: config.bedrockModelId,
      system: [
        {
          text: '주어진 텍스트를 지정된 언어코드로 번역하는 번역기입니다. 설명, 따옴표, 부가 설명 없이 번역 결과만 출력하세요.',
        },
      ],
      messages: [{ role: 'user', content: [{ text: `언어코드 "${targetLang}"로 번역:\n${text}` }] }],
      inferenceConfig: { maxTokens: 500, temperature: 0 },
    })
  );
  const raw = result.output.message.content.map((c) => c.text || '').join('');
  return { translatedText: stripWrappingQuotes(raw), sourceLang: 'ko' };
}

const PRODUCT_LANGUAGES = ['en', 'ja', 'zh'];
const PRODUCT_FIELDS = ['name', 'reason', 'store', 'discountInfo'];

// 예전엔 필드 × 언어 조합마다 Translate를 따로 호출했음(최대 4개 필드 × 3개 언어 = 12번).
// Bedrock으로 옮기면서 한 번의 프롬프트에 다 묶어서 보내고 JSON 하나로 받음 - 호출 횟수를
// 줄이는 게 이 전환의 실질적인 이득(지연시간/비용 모두 12번 -> 1번)
async function translateProduct(fields) {
  const sourceEntries = PRODUCT_FIELDS.map((field) => [field, fields[field]]).filter(
    ([, value]) => value && String(value).trim()
  );
  if (sourceEntries.length === 0) return {};
  const source = Object.fromEntries(sourceEntries);

  const systemText = `아래 한국어 상품 필드들을 영어(en), 일본어(ja), 중국어(zh)로 번역하세요.
설명 없이 반드시 이 JSON 형식으로만 답하세요 (원문에 없는 필드는 결과에서도 빼세요):
{"en": {"필드명": "번역"}, "ja": {"필드명": "번역"}, "zh": {"필드명": "번역"}}`;

  const result = await client.send(
    new ConverseCommand({
      modelId: config.bedrockModelId,
      system: [{ text: systemText }],
      messages: [{ role: 'user', content: [{ text: JSON.stringify(source) }] }],
      inferenceConfig: { maxTokens: 1500, temperature: 0 },
    })
  );

  const raw = result.output.message.content.map((c) => c.text || '').join('');
  const jsonText = raw.slice(raw.indexOf('{'), raw.lastIndexOf('}') + 1);
  const parsed = JSON.parse(jsonText);

  return Object.fromEntries(
    PRODUCT_LANGUAGES.map((lang) => [
      lang,
      Object.fromEntries(Object.entries(parsed[lang] || {}).filter(([, v]) => v)),
    ])
  );
}

module.exports = { translateText, translateProduct };
