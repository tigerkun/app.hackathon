/**
 * AI Safety Assistant Service
 * Talks to Groq's OpenAI-compatible chat completions API to power the
 * conversational safety assistant. The API key is read exclusively from the
 * GROQ_API_KEY environment variable and is never logged or returned to clients.
 *
 * Honesty rules (AGENTS.md invariant #3): when the key is missing or the
 * upstream call fails, this service surfaces an error instead of fabricating
 * a reply. The frontend falls back to static offline safety guides.
 */

const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions';
const DEFAULT_MODEL = 'openai/gpt-oss-120b';
const REQUEST_TIMEOUT_MS = 15000;
const MAX_OUTPUT_TOKENS = 400;

const SYSTEM_PROMPT = [
  'You are SafeSphere\'s AI Safety Assistant for users in India.',
  'You give calm, concise, step-by-step personal-safety guidance.',
  'Rules:',
  '- Reply in under 150 words, short actionable sentences.',
  '- For immediate danger always tell the user to dial 112 (national emergency) first.',
  '- Use verified Indian helplines: 112 police/national, 181 women helpline, 108 ambulance, 101 fire, 1930 cyber fraud.',
  '- You are assistive only: never claim you have contacted police, sent alerts, or tracked anyone.',
  '- Never ask for passwords, OTPs, or PINs; never instruct the user to share them.',
  '- Do not provide medical diagnosis beyond first-aid triage while help arrives.',
].join('\n');

function getApiKey() {
  return process.env.GROQ_API_KEY || '';
}

function isConfigured() {
  return getApiKey().length > 0;
}

function getModel() {
  return process.env.GROQ_MODEL || DEFAULT_MODEL;
}

/**
 * Calls Groq chat completions. `history` must already be sanitized by the
 * controller (array of { role: 'user'|'assistant', content: string }).
 * Returns { reply, model } on success, throws { status, code, message } on failure.
 */
async function chat({ text, history = [] }) {
  const apiKey = getApiKey();
  if (!apiKey) {
    const err = new Error('AI assistant backend is not configured.');
    err.status = 503;
    err.code = 'AI_NOT_CONFIGURED';
    throw err;
  }

  const payload = {
    model: getModel(),
    max_tokens: MAX_OUTPUT_TOKENS,
    temperature: 0.4,
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      ...history,
      { role: 'user', content: text }
    ]
  };

  let response;
  try {
    response = await fetch(GROQ_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
    });
  } catch (e) {
    const err = new Error('AI safety service is unreachable right now.');
    err.status = 502;
    err.code = 'AI_UPSTREAM_UNREACHABLE';
    throw err;
  }

  if (!response.ok) {
    // Consume body but never propagate upstream error text verbatim: it can
    // echo request metadata. Map to a stable honest code instead.
    try { await response.text(); } catch (_) { /* ignore */ }
    const err = new Error(
      response.status === 429
        ? 'AI safety service is busy. Please try again in a moment.'
        : 'AI safety service rejected the request.'
    );
    err.status = response.status === 429 ? 429 : 502;
    err.code = response.status === 429 ? 'AI_RATE_LIMITED' : 'AI_UPSTREAM_ERROR';
    throw err;
  }

  let decoded;
  try {
    decoded = await response.json();
  } catch (_) {
    const err = new Error('AI safety service returned an invalid response.');
    err.status = 502;
    err.code = 'AI_UPSTREAM_ERROR';
    throw err;
  }

  const reply = decoded && decoded.choices && decoded.choices[0]
    && decoded.choices[0].message
    && typeof decoded.choices[0].message.content === 'string'
    ? decoded.choices[0].message.content.trim()
    : '';

  if (!reply) {
    const err = new Error('AI safety service returned an empty reply.');
    err.status = 502;
    err.code = 'AI_UPSTREAM_ERROR';
    throw err;
  }

  return { reply, model: getModel() };
}

module.exports = {
  isConfigured,
  chat
};
