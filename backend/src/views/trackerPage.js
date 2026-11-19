/**
 * SafeSphere Inline Guardian Tracker HTML
 * Zero-dependency, lightweight (~100 lines) browser viewer for live guardian tracking sessions.
 * Dark theme matching AppColors (bg #0B0F1A, teal #2FE0C9, red #FF4C4C).
 * Automatically reads session and token from query params, polls backend every 10s,
 * renders status, coordinates, breadcrumbs, and Google Maps link, and stops when inactive.
 * All dynamic values are strictly inserted via textContent (XSS-safe, no innerHTML).
 */

const trackerHtml = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SafeSphere — Live Guardian Tracking</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: #0B0F1A;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 24px 16px;
    }
    .container {
      width: 100%;
      max-width: 480px;
      background: #111827;
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 16px;
      padding: 24px;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
    }
    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
      padding-bottom: 16px;
      margin-bottom: 20px;
    }
    .logo { font-size: 20px; font-weight: bold; color: #2FE0C9; }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 12px;
      font-weight: 700;
      padding: 4px 10px;
      border-radius: 999px;
      background: rgba(47, 224, 201, 0.15);
      color: #2FE0C9;
    }
    .badge.ended, .badge.expired, .badge.error {
      background: rgba(255, 76, 76, 0.15);
      color: #FF4C4C;
    }
    .badge-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: currentColor;
    }
    .field-group { margin-bottom: 16px; }
    .label { font-size: 12px; color: #94A3B8; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px; }
    .value { font-size: 16px; font-weight: 500; color: #FFFFFF; word-break: break-all; }
    .btn-maps {
      display: block;
      width: 100%;
      text-align: center;
      background: #2FE0C9;
      color: #0B0F1A;
      font-weight: 600;
      padding: 12px;
      border-radius: 8px;
      text-decoration: none;
      margin-top: 20px;
      transition: opacity 0.2s;
    }
    .btn-maps:hover { opacity: 0.9; }
    .btn-maps.disabled {
      background: #374151;
      color: #9CA3AF;
      pointer-events: none;
    }
    .footer {
      margin-top: 24px;
      text-align: center;
      font-size: 12px;
      color: #94A3B8;
    }
    .alert-banner {
      background: rgba(255, 76, 76, 0.15);
      border: 1px solid #FF4C4C;
      color: #FF4C4C;
      border-radius: 8px;
      padding: 12px;
      font-size: 14px;
      margin-bottom: 16px;
      display: none;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">SafeSphere</div>
      <div id="statusBadge" class="badge">
        <span class="badge-dot"></span>
        <span id="statusText">CONNECTING</span>
      </div>
    </div>

    <div id="alertBanner" class="alert-banner"></div>

    <div class="field-group">
      <div class="label">Broadcaster</div>
      <div id="userName" class="value">—</div>
    </div>

    <div class="field-group">
      <div class="label">Last Location</div>
      <div id="lastLocation" class="value">Awaiting first fix…</div>
    </div>

    <div class="field-group">
      <div class="label">Accuracy</div>
      <div id="accuracy" class="value">—</div>
    </div>

    <div class="field-group">
      <div class="label">Breadcrumbs Recorded</div>
      <div id="breadcrumbCount" class="value">0</div>
    </div>

    <div class="field-group">
      <div class="label">Session Expires</div>
      <div id="expiresAt" class="value">—</div>
    </div>

    <a id="mapsLink" href="#" target="_blank" rel="noopener noreferrer" class="btn-maps disabled">Open in Google Maps</a>
  </div>

  <div class="footer">
    SafeSphere Live Guardian Stream • Auto-refreshes every 10s
  </div>

  <script>
    (function() {
      var params = new URLSearchParams(window.location.search);
      var sessionId = params.get('session') || params.get('sessionId') || '';
      var token = params.get('token') || '';

      var statusBadge = document.getElementById('statusBadge');
      var statusText = document.getElementById('statusText');
      var alertBanner = document.getElementById('alertBanner');
      var userNameEl = document.getElementById('userName');
      var lastLocationEl = document.getElementById('lastLocation');
      var accuracyEl = document.getElementById('accuracy');
      var breadcrumbCountEl = document.getElementById('breadcrumbCount');
      var expiresAtEl = document.getElementById('expiresAt');
      var mapsLink = document.getElementById('mapsLink');

      var pollTimer = null;

      function showAlert(msg) {
        alertBanner.textContent = msg;
        alertBanner.style.display = 'block';
      }

      if (!sessionId || !token) {
        statusBadge.className = 'badge ended';
        statusText.textContent = 'AWAITING SESSION';
        showAlert('Provide session ID and token in URL parameters (?session=...&token=...) to view live trip.');
        return;
      }

      function updateStatus(status) {
        var s = (status || 'unknown').toLowerCase();
        statusBadge.className = 'badge ' + s;
        statusText.textContent = s.toUpperCase();
      }

      function poll() {
        var url = '/api/v1/location/track/' + encodeURIComponent(sessionId) + '?token=' + encodeURIComponent(token);
        fetch(url)
          .then(function(res) {
            if (!res.ok) {
              return res.json().catch(function() { return {}; }).then(function(errData) {
                var code = (errData && errData.error && errData.error.code) || res.status;
                var msg = (errData && errData.error && errData.error.message) || 'Failed to load tracking data';
                var err = new Error(code + ': ' + msg);
                err.status = res.status;
                throw err;
              });
            }
            return res.json();
          })
          .then(function(payload) {
            alertBanner.style.display = 'none';
            var session = (payload && payload.data && (payload.data.session || payload.data)) || {};
            var status = session.status || 'unknown';
            updateStatus(status);

            userNameEl.textContent = session.userName || 'SafeSphere Citizen';

            var loc = session.currentLocation;
            if (loc && typeof loc.latitude === 'number' && typeof loc.longitude === 'number') {
              var lat = loc.latitude.toFixed(5);
              var lng = loc.longitude.toFixed(5);
              lastLocationEl.textContent = lat + ', ' + lng;
              mapsLink.href = 'https://www.google.com/maps?q=' + encodeURIComponent(loc.latitude) + ',' + encodeURIComponent(loc.longitude);
              mapsLink.classList.remove('disabled');
            } else {
              lastLocationEl.textContent = 'Awaiting location fix';
            }

            if (loc && typeof loc.accuracy === 'number') {
              accuracyEl.textContent = '±' + Math.round(loc.accuracy) + ' m';
            } else {
              accuracyEl.textContent = '—';
            }

            var crumbs = session.breadcrumbs;
            var count = Array.isArray(crumbs) ? crumbs.length : (session.pointCount || 0);
            breadcrumbCountEl.textContent = String(count);

            if (session.expiresAt) {
              try {
                expiresAtEl.textContent = new Date(session.expiresAt).toLocaleTimeString();
              } catch (_) {
                expiresAtEl.textContent = session.expiresAt;
              }
            } else {
              expiresAtEl.textContent = '—';
            }

            if (status !== 'active') {
              if (pollTimer) {
                clearInterval(pollTimer);
                pollTimer = null;
              }
            }
          })
          .catch(function(err) {
            var httpStatus = err && err.status;
            if (httpStatus === 401 || httpStatus === 403 || httpStatus === 404) {
              updateStatus('ended');
              showAlert(err.message || 'Session expired or invalid credential');
              if (pollTimer) {
                clearInterval(pollTimer);
                pollTimer = null;
              }
            } else {
              // Transient network or server hiccup: show warning banner but keep polling
              showAlert('Connection lost (' + (err.message || 'network error') + '). Reconnecting...');
            }
          });
      }

      poll();
      pollTimer = setInterval(poll, 10000);
    })();
  </script>
</body>
</html>`;

module.exports = {
  trackerHtml
};
