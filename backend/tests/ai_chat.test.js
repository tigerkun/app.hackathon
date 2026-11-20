/**
 * AI Safety Assistant Test Suite (TODO(REAL_BACKEND) — Groq integration)
 *
 * Verifies POST /api/v1/ai/chat:
 * 1. Honest unconfigured state: 503 AI_NOT_CONFIGURED when GROQ_API_KEY is absent
 * 2. Input validation: missing/blank text → 400 MISSING_MESSAGE
 * 3. Input validation: oversized text → 400 MESSAGE_TOO_LONG (1000 char cap)
 * 4. Success path (Groq upstream mocked): 200 envelope with reply + model,
 *    upstream payload carries system prompt, capped max_tokens, Bearer auth
 * 5. Guest access: optionalAuth — no Authorization header required
 * 6. History sanitization: hostile/malformed history dropped, capped at 12 turns
 * 7. Upstream 401 → 502 AI_UPSTREAM_ERROR, API key never leaked in the response
 * 8. Upstream 429 → 429 AI_RATE_LIMITED
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestServer } = require('./helpers/testApp');

describe('AI Safety Assistant /api/v1/ai/chat (Groq)', () => {
  let t;
  const REAL_FETCH = global.fetch;
  const ORIGINAL_KEY = process.env.GROQ_API_KEY;

  // Groq upstream mock state
  let groqCalls = [];
  let groqResponder = () => new Response(JSON.stringify({
    choices: [{ message: { content: ' Move to a crowded, well-lit area and dial 112 now. Women Helpline: 181.' } }]
  }), { status: 200, headers: { 'content-type': 'application/json' } });

  before(async () => {
    process.env.NODE_ENV = 'test';
    delete process.env.GROQ_API_KEY;
    t = await startTestServer();

    // Intercept only api.groq.com traffic; delegate everything else to real fetch
    global.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : (input && input.url) || '';
      if (url.includes('api.groq.com')) {
        groqCalls.push({ url, init, headers: (init && init.headers) || {} });
        return groqResponder();
      }
      return REAL_FETCH(input, init);
    };
  });

  after(() => {
    global.fetch = REAL_FETCH;
    if (ORIGINAL_KEY !== undefined) process.env.GROQ_API_KEY = ORIGINAL_KEY;
    else delete process.env.GROQ_API_KEY;
    return t.close();
  });

  it('returns honest 503 AI_NOT_CONFIGURED when GROQ_API_KEY is absent', async () => {
    const res = await t.request('/api/v1/ai/chat', {
      method: 'POST',
      body: { text: 'I feel unsafe walking home' }
    });
    assert.equal(res.status, 503);
    assert.equal(res.body.success, false);
    assert.equal(res.body.error.code, 'AI_NOT_CONFIGURED');
    assert.match(res.body.error.message, /not configured/i);
    // Honest copy must still point at the real emergency number
    assert.match(res.body.error.message, /112/);
  });

  it('rejects missing or blank text with 400 MISSING_MESSAGE', async () => {
    process.env.GROQ_API_KEY = 'test-groq-key-not-real';
    for (const body of [{}, { text: '' }, { text: '   ' }, { text: null }]) {
      const res = await t.request('/api/v1/ai/chat', { method: 'POST', body });
      assert.equal(res.status, 400, `expected 400 for body=${JSON.stringify(body)}`);
      assert.equal(res.body.error.code, 'MISSING_MESSAGE');
    }
  });

  it('rejects oversized text with 400 MESSAGE_TOO_LONG', async () => {
    const res = await t.request('/api/v1/ai/chat', {
      method: 'POST',
      body: { text: 'a'.repeat(1001) }
    });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'MESSAGE_TOO_LONG');
    assert.deepEqual(res.body.error.details, [{ maxLength: 1000 }]);
  });

  it('returns a live reply on success and calls Groq with the safety system prompt', async () => {
    process.env.GROQ_API_KEY = 'test-groq-key-not-real';
    const res = await t.request('/api/v1/ai/chat', {
      method: 'POST',
      body: { text: 'Someone is following me' }
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.success, true);
    assert.match(res.body.data.reply, /112/);
    assert.ok(res.body.data.model, 'model must be reported back');

    assert.equal(groqCalls.length, 1);
    const call = groqCalls[0];
    assert.equal(call.url, 'https://api.groq.com/openai/v1/chat/completions');
    assert.equal(call.headers.Authorization, 'Bearer test-groq-key-not-real');
    const payload = JSON.parse(call.init.body);
    assert.ok(payload.model, 'upstream model must be set');
    assert.equal(payload.max_tokens, 400);
    assert.ok(payload.messages[0].role === 'system');
    assert.match(payload.messages[0].content, /112/);
    assert.equal(payload.messages[payload.messages.length - 1].role, 'user');
    assert.equal(payload.messages[payload.messages.length - 1].content, 'Someone is following me');
  });

  it('sanitizes hostile history payloads before upstream dispatch', async () => {
    process.env.GROQ_API_KEY = 'test-groq-key-not-real';
    groqCalls = [];
    const res = await t.request('/api/v1/ai/chat', {
      method: 'POST',
      body: {
        text: 'current question',
        history: [
          { role: 'user', content: 'previous question 1' },
          'hostile-string-entry',
          null,
          { role: 'evil_role', content: 'injected' },
          { role: 'assistant', content: 42 },
          { role: 'user', content: '   ' },
          { role: 'user', content: 'previous question 2' }
        ]
      }
    });
    assert.equal(res.status, 200);
    const payload = JSON.parse(groqCalls[groqCalls.length - 1].init.body);
    const historyRoles = payload.messages.slice(1, -1).map(m => `${m.role}:${m.content}`);
    assert.deepEqual(historyRoles, [
      'user:previous question 1',
      'user:previous question 2'
    ]);
  });

  it('caps history at the last 12 turns', async () => {
    process.env.GROQ_API_KEY = 'test-groq-key-not-real';
    groqCalls = [];
    const history = [];
    for (let i = 0; i < 30; i++) history.push({ role: 'user', content: `turn ${i}` });
    const res = await t.request('/api/v1/ai/chat', {
      method: 'POST',
      body: { text: 'now', history }
    });
    assert.equal(res.status, 200);
    const payload = JSON.parse(groqCalls[groqCalls.length - 1].init.body);
    const historyMessages = payload.messages.slice(1, -1);
    assert.equal(historyMessages.length, 12);
    assert.equal(historyMessages[0].content, 'turn 18');
    assert.equal(historyMessages[11].content, 'turn 29');
  });

  it('maps upstream 401 to honest 502 without leaking the API key', async () => {
    process.env.GROQ_API_KEY = 'test-groq-key-not-real-SECRETVALUE';
    groqResponder = () => new Response(JSON.stringify({ error: { message: 'invalid api key' } }),
      { status: 401, headers: { 'content-type': 'application/json' } });
    const res = await t.request('/api/v1/ai/chat', {
      method: 'POST',
      body: { text: 'help me' }
    });
    assert.equal(res.status, 502);
    assert.equal(res.body.success, false);
    assert.equal(res.body.error.code, 'AI_UPSTREAM_ERROR');
    const serialized = JSON.stringify(res.body);
    assert.ok(!serialized.includes('SECRETVALUE'), 'API key must never leak into responses');
  });

  it('maps upstream 429 to AI_RATE_LIMITED with honest busy copy', async () => {
    process.env.GROQ_API_KEY = 'test-groq-key-not-real';
    groqResponder = () => new Response(JSON.stringify({ error: { message: 'rate limit exceeded' } }),
      { status: 429, headers: { 'content-type': 'application/json' } });
    const res = await t.request('/api/v1/ai/chat', {
      method: 'POST',
      body: { text: 'help me' }
    });
    assert.equal(res.status, 429);
    assert.equal(res.body.error.code, 'AI_RATE_LIMITED');
    assert.match(res.body.error.message, /busy/i);
  });
});
