/**
 * SafeSphere Backend Module Root
 * Re-exports server, application, and datastore.
 */

const { server, wss, broadcastSosAlert } = require('./server');
const { app } = require('./app');
const { db } = require('./data/store');
const config = require('./config');

module.exports = {
  server,
  app,
  wss,
  db,
  config,
  broadcastSosAlert
};
