const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { isAllowedCorsOrigin } = require('../src/app');

describe('CORS origin policy', () => {
  it('allows configured production origins and rejects wildcard/unlisted origins', () => {
    const origins = ['https://app.example', 'https://admin.example'];

    assert.equal(isAllowedCorsOrigin('https://app.example', origins, true), true);
    assert.equal(isAllowedCorsOrigin('https://evil.example', origins, true), false);
    assert.equal(isAllowedCorsOrigin('https://evil.example', ['*'], true), false);
  });

  it('retains the development wildcard and permits clients without an Origin header', () => {
    assert.equal(isAllowedCorsOrigin('https://localhost:8080', ['*'], false), true);
    assert.equal(isAllowedCorsOrigin(undefined, [], true), true);
  });
});
