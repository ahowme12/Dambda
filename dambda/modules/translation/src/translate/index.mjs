import { TranslateClient, TranslateTextCommand } from "@aws-sdk/client-translate";

const client = new TranslateClient({});

// ECS 백엔드가 lambda:InvokeFunction으로 동기 호출.
// 캐싱(Translations 테이블 조회/저장)은 호출측(ECS)이 담당하고, 이 함수는 순수 번역만 수행
export const handler = async (event) => {
  const { text, targetLocale, sourceLocale = "auto" } = event;

  const result = await client.send(
    new TranslateTextCommand({
      Text: text,
      SourceLanguageCode: sourceLocale,
      TargetLanguageCode: targetLocale,
    })
  );

  return { translatedText: result.TranslatedText };
};
