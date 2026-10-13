/**
 * Test Server Harness
 * Boots Express on ephemeral port (0) for zero-port-collision isolated integration testing.
 */

const http = require('http');
const { app } = require('../../src/app');
const { db } = require('../../src/data/store');

async function startTestServer() {
  // Ensure clean test environment state
  process.env.NODE_ENV = 'test';
  db.reset();

  const server = http.createServer(app);

  await new Promise((resolve, reject) => {
    server.listen(0, '127.0.0.1', (err) => {
      if (err) reject(err);
      else resolve();
    });
  });

  const address = server.address();
  const port = address.port;
  const baseUrl = `http://127.0.0.1:${port}`;

  return {
    baseUrl,
    request: async (path, options = {}) => {
      const url = `${baseUrl}${path}`;
      const headers = {
        'Content-Type': 'application/json',
        ...(options.headers || {})
      };

      const response = await fetch(url, {
        method: options.method || 'GET',
        headers,
        body: options.body !== undefined ? JSON.stringify(options.body) : undefined
      });

      let jsonBody = null;
      try {
        jsonBody = await response.json();
      } catch (e) {
        jsonBody = null;
      }

      return {
        status: response.status,
        headers: response.headers,
        body: jsonBody
      };
    },
    close: () =>
      new Promise((resolve) => {
        server.close(resolve);
      })
  };
}

module.exports = {
  startTestServer
};
