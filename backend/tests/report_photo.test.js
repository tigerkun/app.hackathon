/**
 * SafeSphere Report Photo Attachments Test Suite (F5-4)
 * Tests photoBase64 attachment validation (<=500KB cap, mime verification),
 * data URL normalization, persistence, and safe serialization.
 */

const { describe, it, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { startTestServer } = require('./helpers/testApp');
const { db } = require('../src/data/store');

describe('F5-4: Incident Report Photo Attachments', () => {
  let serverHarness;

  before(async () => {
    serverHarness = await startTestServer();
  });

  after(async () => {
    if (serverHarness) {
      await serverHarness.close();
    }
  });

  beforeEach(() => {
    db.reset();
  });

  // Minimal 1x1 valid JPEG image buffer
  const sampleJpegBase64 = Buffer.from([
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
    0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
    0x00, 0xff, 0xd9
  ]).toString('base64');

  // Minimal valid PNG image buffer
  const samplePngBase64 = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
    0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82
  ]).toString('base64');

  it('successfully creates report with JPEG data URL photo attachment', async () => {
    const res = await serverHarness.request('/api/v1/reports', {
      method: 'POST',
      body: {
        type: 'Harassment',
        description: 'Streetlight outage near metro gate 2',
        location: 'Metro Gate 2, Rajiv Chowk',
        photoBase64: `data:image/jpeg;base64,${sampleJpegBase64}`
      }
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.success, true);
    assert.ok(res.body.data.photoUrl);
    assert.ok(res.body.data.photoUrl.startsWith('data:image/jpeg;base64,'));

    // Verify GET /api/v1/reports/:id includes photoUrl
    const getRes = await serverHarness.request(`/api/v1/reports/${res.body.data.id}`);
    assert.equal(getRes.status, 200);
    assert.equal(getRes.body.data.photoUrl, res.body.data.photoUrl);
  });

  it('successfully creates report with PNG data URL photo attachment', async () => {
    const res = await serverHarness.request('/api/v1/reports', {
      method: 'POST',
      body: {
        type: 'Accident',
        description: 'Pothole obstruction',
        location: 'Ring Road exit 4',
        photoBase64: `data:image/png;base64,${samplePngBase64}`
      }
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.success, true);
    assert.ok(res.body.data.photoUrl);
    assert.ok(res.body.data.photoUrl.startsWith('data:image/png;base64,'));
  });

  it('normalizes raw base64 without data: prefix into valid data URL', async () => {
    const res = await serverHarness.request('/api/v1/reports', {
      method: 'POST',
      body: {
        type: 'Theft',
        description: 'Bicycle stolen near library',
        location: 'Central Library gate',
        photoBase64: sampleJpegBase64
      }
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.success, true);
    assert.ok(res.body.data.photoUrl.startsWith('data:image/jpeg;base64,'));
  });

  it('rejects photo attachment exceeding 500KB cap with 400 Bad Request', async () => {
    // Generate buffer > 500KB (e.g. 520,000 bytes) with fake JPEG header
    const largeBuf = Buffer.alloc(520 * 1024, 0xaa);
    largeBuf[0] = 0xff;
    largeBuf[1] = 0xd8;
    largeBuf[2] = 0xff;
    const oversizedBase64 = largeBuf.toString('base64');

    const res = await serverHarness.request('/api/v1/reports', {
      method: 'POST',
      body: {
        type: 'Theft',
        description: 'Test oversize photo',
        location: 'Connaught Place',
        photoBase64: `data:image/jpeg;base64,${oversizedBase64}`
      }
    });

    assert.equal(res.status, 400);
    assert.equal(res.body.success, false);
    assert.ok(
      JSON.stringify(res.body.error).includes('500KB'),
      `Expected 500KB error message, got: ${JSON.stringify(res.body.error)}`
    );
  });

  it('rejects non-image payload (e.g. text/plain or invalid magic bytes) with 400', async () => {
    const textBase64 = Buffer.from('This is not an image file. Plain text.').toString('base64');
    const res = await serverHarness.request('/api/v1/reports', {
      method: 'POST',
      body: {
        type: 'Suspicious',
        description: 'Test invalid mime',
        location: 'Connaught Place',
        photoBase64: `data:image/jpeg;base64,${textBase64}`
      }
    });

    assert.equal(res.status, 400);
    assert.equal(res.body.success, false);
    assert.ok(
      JSON.stringify(res.body.error).includes('image format') || JSON.stringify(res.body.error).includes('JPEG'),
      `Expected format error, got: ${JSON.stringify(res.body.error)}`
    );
  });

  it('accepts report without photoBase64, setting photoUrl to null', async () => {
    const res = await serverHarness.request('/api/v1/reports', {
      method: 'POST',
      body: {
        type: 'Other',
        description: 'Report without any photo',
        location: 'Connaught Place'
      }
    });

    assert.equal(res.status, 201);
    assert.equal(res.body.success, true);
    assert.equal(res.body.data.photoUrl, null);
  });
});
