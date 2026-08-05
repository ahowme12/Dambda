const {
  CognitoIdentityProviderClient,
  AdminCreateUserCommand,
  AdminSetUserPasswordCommand,
  AdminDeleteUserCommand,
  AdminInitiateAuthCommand,
  GetUserCommand,
} = require('@aws-sdk/client-cognito-identity-provider');
const config = require('../config');

const client = new CognitoIdentityProviderClient({ region: config.awsRegion });

function attr(attributes, name) {
  const found = (attributes || []).find((a) => a.Name === name);
  return found ? found.Value : undefined;
}

// 이메일 인증 절차 없이 바로 CONFIRMED 상태로 유저 생성. 반환값에서 sub를 뽑아 DynamoDB 프로필 키로 씀
async function createUser(email) {
  const result = await client.send(
    new AdminCreateUserCommand({
      UserPoolId: config.userPoolId,
      Username: email,
      UserAttributes: [
        { Name: 'email', Value: email },
        { Name: 'email_verified', Value: 'true' },
      ],
      MessageAction: 'SUPPRESS',
    })
  );
  return attr(result.User.Attributes, 'sub');
}

async function setPassword(email, password) {
  await client.send(
    new AdminSetUserPasswordCommand({
      UserPoolId: config.userPoolId,
      Username: email,
      Password: password,
      Permanent: true,
    })
  );
}

// 회원가입 중간 단계 실패 시 고아 계정(비밀번호 없는 유저) 방지용 보상 삭제
async function deleteUser(email) {
  await client.send(
    new AdminDeleteUserCommand({
      UserPoolId: config.userPoolId,
      Username: email,
    })
  );
}

async function login(email, password) {
  const result = await client.send(
    new AdminInitiateAuthCommand({
      UserPoolId: config.userPoolId,
      ClientId: config.userPoolClientId,
      AuthFlow: 'ADMIN_USER_PASSWORD_AUTH',
      AuthParameters: { USERNAME: email, PASSWORD: password },
    })
  );
  const authResult = result.AuthenticationResult;
  return {
    accessToken: authResult.AccessToken,
    idToken: authResult.IdToken,
    refreshToken: authResult.RefreshToken,
    expiresIn: authResult.ExpiresIn,
  };
}

// 액세스 토큰으로 신원 확인. 별도 JWT/JWKS 검증 없이 Cognito가 직접 유효성을 판단하게 함
async function getUserByAccessToken(accessToken) {
  const result = await client.send(new GetUserCommand({ AccessToken: accessToken }));
  return {
    sub: attr(result.UserAttributes, 'sub'),
    email: attr(result.UserAttributes, 'email'),
  };
}

module.exports = { createUser, setPassword, deleteUser, login, getUserByAccessToken };
