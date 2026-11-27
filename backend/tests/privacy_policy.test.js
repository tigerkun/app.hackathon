/**
 * Privacy Policy Route Tests (Play Console & DPDP Act 2023)
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestServer } = require('./helpers/testApp');

describe('Public Privacy Policy HTML Routes (/privacy, /privacy-policy)', () => {
  let t;

  before(async () => {
    t = await startTestServer();
  });

  after(() => t.close());

  for (const path of ['/privacy', '/privacy-policy']) {
    it(`serves 200 text/html privacy policy on GET ${path}`, async () => {
      const res = await fetch(`${t.baseUrl}${path}`);
      const html = await res.text();
      assert.equal(res.status, 200);
      assert.match(res.headers.get('content-type') || '', /text\/html/);
      assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
      assert.match(html, /SafeSphere Privacy Policy/);
      assert.match(html, /DPDP Act 2023/);
      assert.match(html, /DELETE \/api\/v1\/auth\/me/);
      assert.match(html, /tejasgaur94@gmail\.com/);
    });
  }
});
