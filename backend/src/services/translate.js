const { TranslateClient, TranslateTextCommand } = require('@aws-sdk/client-translate');
const config = require('../config');

const client = new TranslateClient({ region: config.awsRegion });

// SourceLanguageCode: 'auto'로 원문 언어를 별도 감지 호출 없이 한 번에 처리.
// 리뷰처럼 짧거나 애매한 텍스트는 언어 자동판별 신뢰도가 낮아 DetectedLanguageLowConfidenceException이
// 남 - 예외에 실려오는 감지 언어로 한 번 더 시도함(review_moderation Lambda와 동일 이슈/해법)
async function translateText(text, targetLang) {
  try {
    const result = await client.send(
      new TranslateTextCommand({
        Text: text,
        SourceLanguageCode: 'auto',
        TargetLanguageCode: targetLang,
      })
    );
    return { translatedText: result.TranslatedText, sourceLang: result.SourceLanguageCode };
  } catch (err) {
    if (err.name === 'DetectedLanguageLowConfidenceException' && err.DetectedLanguageCode) {
      if (err.DetectedLanguageCode === targetLang) {
        return { translatedText: text, sourceLang: targetLang };
      }
      const retry = await client.send(
        new TranslateTextCommand({
          Text: text,
          SourceLanguageCode: err.DetectedLanguageCode,
          TargetLanguageCode: targetLang,
        })
      );
      return { translatedText: retry.TranslatedText, sourceLang: err.DetectedLanguageCode };
    }
    throw err;
  }
}

const PRODUCT_LANGUAGES = ['en', 'ja', 'zh'];
const PRODUCT_FIELDS = ['name', 'reason', 'store', 'discountInfo'];

// 관리자가 등록/수정하는 상품은 항상 한국어 원문이라(seed-products.js와 동일 전제) source를
// 'auto'로 감지할 필요가 없음 - DetectedLanguageLowConfidenceException 자체가 안 생기는
// 더 단순하고 확실한 경로. name/reason/store/discountInfo를 en/ja/zh로 배치 번역해서
// { en: {name, reason, store, discountInfo?}, ja: {...}, zh: {...} } 형태로 돌려줌
async function translateProduct(fields) {
  const languageEntries = await Promise.all(
    PRODUCT_LANGUAGES.map(async (lang) => {
      const fieldEntries = await Promise.all(
        PRODUCT_FIELDS.map(async (field) => {
          const value = fields[field];
          if (!value || !String(value).trim()) return null;
          const result = await client.send(
            new TranslateTextCommand({
              Text: String(value),
              SourceLanguageCode: 'ko',
              TargetLanguageCode: lang,
            })
          );
          return [field, result.TranslatedText];
        })
      );
      return [lang, Object.fromEntries(fieldEntries.filter(Boolean))];
    })
  );
  return Object.fromEntries(languageEntries);
}

module.exports = { translateText, translateProduct };
