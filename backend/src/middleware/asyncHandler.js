// Express 4는 async 핸들러 안에서 던진 예외를 자동으로 안 잡아줘서, 처리 안 된 예외가
// unhandled rejection이 되어 프로세스 전체가 죽음. 모든 async 라우트 핸들러를 이걸로 감싸서
// 에러를 항상 next(err)로 넘기고, server.js의 전역 에러 핸들러가 500으로 응답하게 함
function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

module.exports = asyncHandler;
