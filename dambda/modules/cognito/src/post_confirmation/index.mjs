import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";

const client = new DynamoDBClient({});

// Cognito PostConfirmation 트리거: 가입 시 선택한 locale을 Users 테이블에 기록
export const handler = async (event) => {
  const attrs = event.request.userAttributes;

  await client.send(
    new PutItemCommand({
      TableName: process.env.USERS_TABLE_NAME,
      Item: {
        user_id: { S: event.userName },
        sub: { S: attrs.sub },
        email: { S: attrs.email ?? "" },
        locale: { S: attrs["custom:locale"] ?? "en" },
        created_at: { N: String(Date.now()) },
      },
    })
  );

  return event;
};
