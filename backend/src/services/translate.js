const { TranslateClient, TranslateTextCommand } = require('@aws-sdk/client-translate');
const config = require('../config');

const client = new TranslateClient({ region: config.awsRegion });

// SourceLanguageCode: 'auto'로 원문 언어를 별도 감지 호출 없이 한 번에 처리
async function translateText(text, targetLang) {
  const result = await client.send(
    new TranslateTextCommand({
      Text: text,
      SourceLanguageCode: 'auto',
      TargetLanguageCode: targetLang,
    })
  );
  return { translatedText: result.TranslatedText, sourceLang: result.SourceLanguageCode };
}

module.exports = { translateText };
