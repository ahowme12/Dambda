const config = require('../config');

// Tavily: LLM 도구 호출용으로 설계된 검색 API (https://tavily.com, 월 1000회 무료 티어)
// Node 20에 내장된 fetch를 그대로 씀 - 별도 HTTP 클라이언트 의존성 불필요
async function search(query) {
  if (!config.tavilyApiKey) {
    throw new Error('TAVILY_API_KEY not configured');
  }

  const response = await fetch('https://api.tavily.com/search', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      api_key: config.tavilyApiKey,
      query,
      max_results: 5,
    }),
  });

  if (!response.ok) {
    throw new Error(`tavily search failed: ${response.status}`);
  }

  const data = await response.json();
  return (data.results || []).map((r) => ({
    title: r.title,
    url: r.url,
    content: r.content,
  }));
}

module.exports = { search };
