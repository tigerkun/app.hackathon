/**
 * AI Assistant Controller
 * POST /api/v1/ai/chat — conversational safety guidance via the Groq-backed
 * aiService. Guest-friendly (optionalAuth) but strictly rate-limited because
 * every upstream call consumes provider tokens.
 */

const aiService = require('../services/aiService');

const MAX_MESSAGE_LENGTH = 1000;
const MAX_HISTORY_TURNS = 12;
const MAX_HISTORY_ITEM_LENGTH = 2000;

/**
 * Sanitizes a chat history array. Drops anything that is not a plain object
 * with a user/assistant role and string content; caps length so a hostile
 * payload cannot inflate upstream token usage.
 */
function sanitizeHistory(rawHistory) {
  if (!Array.isArray(rawHistory)) return [];
  const cleaned = [];
  for (const item of rawHistory.slice(-MAX_HISTORY_TURNS)) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) continue;
    // Strict allowlist: unknown roles (e.g. hostile 'system' injections) are dropped
    const role = item.role === 'assistant' ? 'assistant' : (item.role === 'user' ? 'user' : null);
    if (!role) continue;
    if (typeof item.content !== 'string') continue;
    const content = item.content.slice(0, MAX_HISTORY_ITEM_LENGTH).trim();
    if (!content) continue;
    cleaned.push({ role, content });
  }
  return cleaned;
}

async function chat(req, res, next) {
  try {
    const { text, message, history } = req.body || {};
    const prompt = typeof text === 'string' && text.trim() ? text : message;

    if (typeof prompt !== 'string' || !prompt.trim()) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'MISSING_MESSAGE',
          message: 'A non-empty "text" field is required.',
          details: []
        }
      });
    }

    if (prompt.length > MAX_MESSAGE_LENGTH) {
      return res.status(400).json({
        success: false,
        error: {
          code: 'MESSAGE_TOO_LONG',
          message: `Message exceeds the ${MAX_MESSAGE_LENGTH} character limit.`,
          details: [{ maxLength: MAX_MESSAGE_LENGTH }]
        }
      });
    }

    if (!aiService.isConfigured()) {
      // Honest failure (invariant #3): no fabricated replies when unconfigured.
      return res.status(503).json({
        success: false,
        error: {
          code: 'AI_NOT_CONFIGURED',
          message: 'AI assistant backend is not configured. Offline safety guides remain available in the app. For immediate danger dial 112.',
          details: []
        }
      });
    }

    const result = await aiService.chat({
      text: prompt.trim(),
      history: sanitizeHistory(history)
    });

    res.status(200).json({
      success: true,
      data: {
        reply: result.reply,
        model: result.model
      }
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  chat
};
