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

module.exports = { translateText };
