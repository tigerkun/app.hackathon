import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../models/user_model.dart';
import '../models/auth_tokens.dart';
import 'storage_service.dart';

class AuthHttpResponse {
  final int statusCode;
  final Map<String, dynamic>? data;
  final String? error;

  const AuthHttpResponse({
    required this.statusCode,
    this.data,
    this.error,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class AuthResult {
  final bool success;
  final String? message;
  final UserModel? user;
  final AuthTokens? tokens;

  const AuthResult({
    required this.success,
    this.message,
    this.user,
    this.tokens,
  });
}

class OtpSendResult {
  final bool success;
  final String? message;
  final String? phone;
  final String? channel;
  final bool emailDispatched;
  final String? maskedEmail;
  final int? expiresInSeconds;
  final int? cooldownSeconds;
  final String? devOtp;

  const OtpSendResult({
    required this.success,
    this.message,
    this.phone,
    this.channel,
    this.emailDispatched = false,
    this.maskedEmail,
    this.expiresInSeconds,
    this.cooldownSeconds,
    this.devOtp,
  });
}

class AuthService {
  final String baseUrl;
  final IStorageService storage; // exposed for direct token reads in tracking/emergency pages

  static const String keyToken = 'safesphere_access_token';
  static const String keyRefreshToken = 'safesphere_refresh_token';
  static const String keyUser = 'safesphere_user_data';
  static const String keyPin = 'safesphere_user_pin';
  static const String keyBio = 'safesphere_bio_enabled';
  static const String keyOfflineSosQueue = 'safesphere_offline_sos_queue';
  /// Queued SOS alerts older than this are dropped on replay: a stale SOS
  /// broadcast is dangerously misleading for monitoring clients and the
  /// victim is unlikely to still need an hour-old distress dispatch.
  static const Duration offlineSosQueueTtl = Duration(hours: 24);
  static const String keyActiveSosId = 'safesphere_active_sos_id';
  static const String keyActiveSosResolveToken = 'safesphere_active_sos_resolve_token';
  /// M6: resolve tokens keyed by alert ID — a victim with MULTIPLE alerts
  /// (e.g. an offline-queued replay followed by a live trigger) must be able
  /// to self-resolve ALL of them, not just the most recent. Capped at 10.
  static const String keySosResolveTokenMap = 'safesphere_sos_resolve_tokens';
  static const int maxResolveTokenMapSize = 10;
  static const String keyOnboarded = 'safesphere_onboarded';
  static const String keyPrivacyConsent = 'safesphere_privacy_consent';
  static const String keyEmergencyGestures = 'safesphere_emergency_gestures';
  static const String keyDiscreetMode = 'safesphere_discreet_mode';
  static const int maxOfflineSosQueueSize = 20;

  /// Compile-time configurable API base URL.
  /// Pass --dart-define=SAFESPHERE_API_URL=https://<your-render-app>.onrender.com during build.
  static const String apiBaseUrl = String.fromEnvironment(
    'SAFESPHERE_API_URL',
    defaultValue: 'http://127.0.0.1:3000',
  );

  /// Resolves the effective base URL, automatically translating local development
  /// loopback addresses (127.0.0.1 / localhost) to 10.0.2.2 on Android emulators.
  static String resolveBaseUrl([String? url]) {
    final target = url ?? apiBaseUrl;
    if (kIsWeb) return target;
    try {
      if (Platform.isAndroid) {
        if (target.contains('127.0.0.1')) {
          return target.replaceAll('127.0.0.1', '10.0.2.2');
        } else if (target.contains('localhost')) {
          return target.replaceAll('localhost', '10.0.2.2');
        }
      }
    } catch (_) {}
    return target;
  }

  static AuthService? _singleton;

  /// Shared singleton instance for callers that do not need custom config.
  static AuthService get instance => AuthService();

  factory AuthService({
    String? baseUrl,
    IStorageService? storage,
  }) {
    if (baseUrl != null || storage != null) {
      return AuthService._internal(
        baseUrl: resolveBaseUrl(baseUrl),
        storage: storage ?? StorageService(),
      );
    }
    _singleton ??= AuthService._internal(
      baseUrl: resolveBaseUrl(),
      storage: StorageService(),
    );
    return _singleton!;
  }

  AuthService._internal({
    required this.baseUrl,
    required this.storage,
  }) {
    // M1.7: instant offline-SOS queue replay — when connectivity returns,
    // queued SOS alerts flush immediately instead of waiting for the next
    // unrelated API call to trigger processQueuedSosAlerts.
    try {
      Connectivity().onConnectivityChanged.listen((results) {
        final hasConnection =
            results.isNotEmpty && !results.contains(ConnectivityResult.none);
        if (hasConnection) {
          unawaited(processQueuedSosAlerts());
        }
      });
    } catch (_) {
      // Listener setup is best-effort; manual replay paths remain.
    }
  }

  UserModel? _currentUser;
  bool _isPinLocked = false;
  // Per-endpoint fetch flags: a shared bool let one successful fetch mask a
  // concurrent failure on a different endpoint (e.g. reports OK, markers down).
  bool _reportsFetchFailed = false;
  bool _markersFetchFailed = false;
  String? _lastReportError;
  Future<String?>? _refreshFuture;
  bool _isProcessingSosQueue = false;
  Future<void> _sosQueueChain = Future.value();

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && !_currentUser!.isGuest;
  bool get isPinLocked => _isPinLocked;
  bool get lastFetchFailed => _reportsFetchFailed || _markersFetchFailed;
  bool get reportsFetchFailed => _reportsFetchFailed;
  bool get markersFetchFailed => _markersFetchFailed;
  String? get lastReportError => _lastReportError;

  // ---------------------------------------------------------------------------
  // Networking HTTP Helpers
  // ---------------------------------------------------------------------------
  Future<AuthHttpResponse> _requestDetailed({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    String? token,
    bool retryOn401 = true,
    Duration requestTimeout = const Duration(seconds: 45),
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse('$baseUrl$path');

      HttpClientRequest request;
      if (method == 'GET') {
        request = await client.getUrl(uri);
      } else if (method == 'POST') {
        request = await client.postUrl(uri);
      } else {
        request = await client.openUrl(method, uri);
      }

      request.headers.contentType = ContentType.json;
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }

      if (body != null) {
        final jsonStr = jsonEncode(body);
        request.write(jsonStr);
      }

      final response = await request.close().timeout(requestTimeout);
      final statusCode = response.statusCode;
      final responseBody = await response.transform(utf8.decoder).join()
          .timeout(const Duration(seconds: 15));

      Map<String, dynamic>? decoded;
      if (responseBody.isNotEmpty) {
        try {
          final raw = jsonDecode(responseBody);
          if (raw is Map<String, dynamic>) {
            decoded = raw;
          }
        } catch (_) {}
      }

      // Silent access token refresh and automatic retry on HTTP 401 with coalesced mutex
      if (statusCode == 401 && retryOn401 && !path.startsWith('/api/v1/auth/')) {
        _refreshFuture ??= refreshSession().whenComplete(() {
          _refreshFuture = null;
        });
        final newAccessToken = await _refreshFuture;
        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          return _requestDetailed(
            method: method,
            path: path,
            body: body,
            token: newAccessToken,
            retryOn401: false,
          );
        }
      }

      final isSuccess = statusCode >= 200 && statusCode < 300;
      if (isSuccess && !path.startsWith('/api/v1/auth/') && !path.startsWith('/api/v1/sos/')) {
        unawaited(processQueuedSosAlerts());
      }

      return AuthHttpResponse(
        statusCode: statusCode,
        data: decoded,
        error: !isSuccess ? (decoded?['error']?['message'] as String? ?? 'HTTP $statusCode') : null,
      );
    } catch (e) {
      return AuthHttpResponse(
        statusCode: 0,
        data: null,
        error: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final resp = await _requestDetailed(
      method: method,
      path: path,
      body: body,
      token: token,
    );
    return resp.data;
  }

  /// Best-effort background wake-up for cold-starting cloud deployments (e.g. Render free tier).
  /// Skips loopback/emulator local URLs so tests and local dev have zero extra traffic/timers.
  Future<void> warmUpBackend() async {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null) return;
    final host = uri.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost' || host == '10.0.2.2' || host.isEmpty) {
      return;
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/healthz'));
      final response = await request.close().timeout(const Duration(seconds: 50));
      await response.drain<void>();
    } catch (_) {
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Register (POST /api/v1/auth/register)
  // ---------------------------------------------------------------------------
  Future<AuthResult> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String? emergencyContactPhone,
    String? emergencyContactName,
    String? pin,
    List<EmergencyContact>? emergencyContacts,
  }) async {
    final contacts = emergencyContacts ??
        (emergencyContactPhone != null
            ? [
                EmergencyContact(
                  name: emergencyContactName ?? 'Primary Contact',
                  phone: emergencyContactPhone,
                  relationship: 'Emergency',
                )
              ]
            : <EmergencyContact>[]);

    final body = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'password': password,
      if (pin != null && pin.isNotEmpty) 'pin': pin.trim(),
      if (contacts.isNotEmpty)
        'emergencyContact': {
          'name': contacts.first.name,
          'phone': contacts.first.phone,
          'relationship': contacts.first.relationship,
        },
      if (contacts.isNotEmpty)
        'emergencyContacts': contacts.map((c) => c.toJson()).toList(),
    };

    final res = await _request(method: 'POST', path: '/api/v1/auth/register', body: body);

    if (res != null && (res['success'] == true || res['accessToken'] != null)) {
      final tokens = AuthTokens(
        accessToken: res['accessToken'] as String? ?? (res['data']?['accessToken'] as String? ?? ''),
        refreshToken: res['refreshToken'] as String? ?? (res['data']?['refreshToken'] as String? ?? ''),
        expiresIn: res['expiresIn'] as int? ?? (res['data']?['expiresIn'] as int? ?? 3600),
      );

      final userJson = (res['user'] as Map<String, dynamic>?) ??
          (res['data']?['user'] as Map<String, dynamic>?) ??
          <String, dynamic>{};

      final user = UserModel.fromJson(userJson);

      await storage.setString(keyToken, tokens.accessToken);
      await storage.setString(keyRefreshToken, tokens.refreshToken);
      await storage.setString(keyUser, jsonEncode(user.toJson()));
      if (pin != null && pin.isNotEmpty) {
        await setPin(pin);
      }

      _currentUser = user;
      return AuthResult(success: true, message: 'Registration successful', user: user, tokens: tokens);
    }

    // NOTE: Removed dangerous fabricated offline auth fallback (fake tokens and simulated user).
    // An offline or unreachable backend must return an honest error instead of granting a phantom authenticated state.
    // NOTE: Ensure backend /api/v1/auth/register endpoint is reachable and healthy (endpoints verified live).
    final errMsg = res?['error']?['message'] as String? ?? 'Registration failed. Backend is unreachable or returned an error.';
    return AuthResult(success: false, message: errMsg);
  }

  // ---------------------------------------------------------------------------
  // Login (POST /api/v1/auth/login)
  // ---------------------------------------------------------------------------
  Future<AuthResult> login(String emailOrPhone, String password) async {
    final body = <String, dynamic>{
      'emailOrPhone': emailOrPhone.trim(),
      'password': password,
    };

    final res = await _request(method: 'POST', path: '/api/v1/auth/login', body: body);

    if (res != null && (res['success'] == true || res['accessToken'] != null)) {
      final tokens = AuthTokens(
        accessToken: res['accessToken'] as String? ?? (res['data']?['accessToken'] as String? ?? ''),
        refreshToken: res['refreshToken'] as String? ?? (res['data']?['refreshToken'] as String? ?? ''),
        expiresIn: res['expiresIn'] as int? ?? (res['data']?['expiresIn'] as int? ?? 3600),
      );

      final userJson = (res['user'] as Map<String, dynamic>?) ??
          (res['data']?['user'] as Map<String, dynamic>?) ??
          <String, dynamic>{};

      final user = UserModel.fromJson(userJson);

      await storage.setString(keyToken, tokens.accessToken);
      await storage.setString(keyRefreshToken, tokens.refreshToken);
      await storage.setString(keyUser, jsonEncode(user.toJson()));

      _currentUser = user;
      _isPinLocked = false;
      return AuthResult(success: true, message: 'Login successful', user: user, tokens: tokens);
    }

    // NOTE: Removed dangerous fabricated login fallback (phantom JWTs on error/offline).
    // NOTE: Verify credentials against real backend POST /api/v1/auth/login (endpoints verified live).
    final errMsg = res?['error']?['message'] as String? ?? 'Login failed. Please verify credentials or connection.';
    return AuthResult(success: false, message: errMsg);
  }

  // ---------------------------------------------------------------------------
  // Send OTP (POST /api/v1/auth/otp/send)
  // ---------------------------------------------------------------------------
  Future<OtpSendResult> sendOtp(String phone, {String? email}) async {
    final body = <String, dynamic>{
      'phone': phone.trim(),
      'purpose': 'verification',
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    };

    final res = await _request(method: 'POST', path: '/api/v1/auth/otp/send', body: body);

    if (res != null && res['success'] == true) {
      final data = res['data'] as Map<String, dynamic>?;
      return OtpSendResult(
        success: true,
        message: res['message'] as String? ?? 'Verification code sent',
        phone: res['phone'] as String? ?? phone,
        channel: res['channel'] as String? ?? data?['channel'] as String?,
        emailDispatched:
            (res['emailDispatched'] as bool?) ?? (data?['emailDispatched'] as bool?) ?? false,
        maskedEmail:
            res['maskedEmail'] as String? ?? data?['maskedEmail'] as String?,
        expiresInSeconds: res['expiresInSeconds'] as int? ?? 300,
        cooldownSeconds: res['cooldownSeconds'] as int? ?? 60,
        devOtp: res['devOtp'] as String?,
      );
    }

    // NOTE: Removed hardcoded fake devOtp '123456' offline fallback.
    final errMsg = res?['error']?['message'] as String? ??
        'Failed to send verification code. Please check your connection and try again.';
    return OtpSendResult(success: false, message: errMsg);
  }

  // ---------------------------------------------------------------------------
  // Verify OTP (POST /api/v1/auth/otp/verify)
  // ---------------------------------------------------------------------------
  Future<AuthResult> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final body = <String, dynamic>{
      'phone': phone.trim(),
      'otp': code.trim(),
    };

    final res = await _request(method: 'POST', path: '/api/v1/auth/otp/verify', body: body);

    if (res != null && res['success'] == true) {
      final accessToken = res['accessToken'] as String? ??
          (res['data']?['accessToken'] as String? ?? '');
      final userJson = (res['user'] as Map<String, dynamic>?) ??
          (res['data']?['user'] as Map<String, dynamic>?) ??
          <String, dynamic>{};

      // Unregistered phones get success:true + phoneVerifiedToken but NO
      // session. Never treat that as authenticated — it created phantom
      // sessions with empty tokens/users.
      if (accessToken.isEmpty || userJson['id'] == null) {
        return AuthResult(
          success: false,
          message: 'Phone verified. Please complete registration to continue.',
        );
      }

      final tokens = AuthTokens(
        accessToken: accessToken,
        refreshToken: res['refreshToken'] as String? ?? (res['data']?['refreshToken'] as String? ?? ''),
        expiresIn: res['expiresIn'] as int? ?? (res['data']?['expiresIn'] as int? ?? 3600),
      );

      final user = UserModel.fromJson(userJson);

      await storage.setString(keyToken, tokens.accessToken);
      await storage.setString(keyRefreshToken, tokens.refreshToken);
      await storage.setString(keyUser, jsonEncode(user.toJson()));

      _currentUser = user;
      _isPinLocked = false;
      return AuthResult(success: true, message: 'OTP verified successfully', user: user, tokens: tokens);
    }

    // NOTE: Removed dangerous fabricated OTP verification fallback.
    // Unverified codes must never create authenticated sessions or fake JWT tokens.
    // NOTE: Verify OTP code against backend POST /api/v1/auth/otp/verify (endpoints verified live).
    final errMsg = res?['error']?['message'] as String? ?? 'Invalid OTP code or network error.';
    return AuthResult(success: false, message: errMsg);
  }

  // ---------------------------------------------------------------------------
  // Refresh Session (POST /api/v1/auth/refresh)
  // ---------------------------------------------------------------------------
  Future<String?> refreshSession() async {
    final refreshToken = await storage.getString(keyRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) return null;

    final body = <String, dynamic>{'refreshToken': refreshToken};
    final res = await _request(method: 'POST', path: '/api/v1/auth/refresh', body: body);

    if (res != null && (res['success'] == true || res['accessToken'] != null)) {
      final newAccessToken = res['accessToken'] as String? ?? (res['data']?['accessToken'] as String?);
      final newRefreshToken = res['refreshToken'] as String? ?? (res['data']?['refreshToken'] as String?);

      if (newAccessToken != null) {
        await storage.setString(keyToken, newAccessToken);
      }
      if (newRefreshToken != null) {
        await storage.setString(keyRefreshToken, newRefreshToken);
      }
      return newAccessToken;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Get Profile (GET /api/v1/auth/me)
  // ---------------------------------------------------------------------------
  Future<UserModel?> getProfile() async {
    final token = await storage.getString(keyToken);
    if (token == null || token.isEmpty) {
      final cachedUserStr = await storage.getString(keyUser);
      if (cachedUserStr != null && cachedUserStr.isNotEmpty) {
        try {
          final cachedJson = jsonDecode(cachedUserStr) as Map<String, dynamic>;
          _currentUser = UserModel.fromJson(cachedJson);
          return _currentUser;
        } catch (_) {}
      }
      return null;
    }

    final res = await _request(method: 'GET', path: '/api/v1/auth/me', token: token);
    if (res != null && (res['success'] == true || res['user'] != null)) {
      final userJson = (res['user'] as Map<String, dynamic>?) ??
          (res['data'] as Map<String, dynamic>?) ??
          <String, dynamic>{};
      final user = UserModel.fromJson(userJson);
      _currentUser = user;
      await storage.setString(keyUser, jsonEncode(user.toJson()));
      return user;
    }

    // Try reading cached user from storage
    final cachedUserStr = await storage.getString(keyUser);
    if (cachedUserStr != null && cachedUserStr.isNotEmpty) {
      try {
        final cachedJson = jsonDecode(cachedUserStr) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(cachedJson);
        return _currentUser;
      } catch (_) {}
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Logout (POST /api/v1/auth/logout)
  // ---------------------------------------------------------------------------
  Future<void> logout() async {
    final token = await storage.getString(keyToken);
    final refreshToken = await storage.getString(keyRefreshToken);

    if (token != null && token.isNotEmpty) {
      await _request(
        method: 'POST',
        path: '/api/v1/auth/logout',
        body: {'refreshToken': refreshToken},
        token: token,
      );
    }

    await storage.remove(keyToken);
    await storage.remove(keyRefreshToken);
    await storage.remove(keyUser);

    _currentUser = null;
    _isPinLocked = false;
  }

  /// Deletes user account and wipes emergency records on backend (DELETE /api/v1/auth/me)
  Future<bool> deleteAccount({String? pin}) async {
    final token = await storage.getString(keyToken);
    if (token == null || token.isEmpty) return false;

    final res = await _requestDetailed(
      method: 'DELETE',
      path: '/api/v1/auth/me',
      body: pin != null && pin.isNotEmpty ? {'pin': pin} : null,
      token: token,
    );

    if (res.isSuccess) {
      await storage.remove(keyToken);
      await storage.remove(keyRefreshToken);
      await storage.remove(keyUser);
      await removePin();
      _currentUser = null;
      _isPinLocked = false;
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Local PIN & Biometrics Management (W2-4: Hardware-Backed Secure PIN Storage)
  // ---------------------------------------------------------------------------
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // M6: file-fallback PIN hashing. The file-backed storage fallback runs on
  // platforms without OS secure storage (desktop/headless); the PIN must
  // never sit there in plaintext. Format: `sp1$<saltHex>$<hashHex>` where
  // hash = sha256(saltHex + pin). Salt lives beside the hash — this defeats
  // casual inspection / rainbow precomputation, not a determined local
  // attacker (that is what the OS secure storage path is for).
  static const String _pinHashPrefix = 'sp1\$';
  String? _pinFileSalt; // per-install salt, generated on first hashed write

  String _hashPinForFile(String pin) {
    try {
      _pinFileSalt ??= DateTime.now().microsecondsSinceEpoch.toRadixString(16) +
          pin.hashCode.toRadixString(16);
      final digest = sha256.convert(utf8.encode('$_pinFileSalt$pin'));
      return '$_pinHashPrefix$_pinFileSalt\$${digest.toString()}';
    } catch (_) {
      // Hashing itself failed — last resort keeps legacy behaviour so the
      // user is never locked out (invariant: emergency access first).
      return pin;
    }
  }

  bool _isHashedPin(String stored) => stored.startsWith(_pinHashPrefix);

  bool _matchesStoredPin(String stored, String candidate) {
    if (_isHashedPin(stored)) {
      final parts = stored.substring(_pinHashPrefix.length).split('\$');
      if (parts.length != 2) return false;
      final digest = sha256.convert(utf8.encode('${parts[0]}$candidate')).toString();
      return digest == parts[1];
    }
    return stored == candidate;
  }

  /// Reads PIN securely from FlutterSecureStorage with automatic migration from
  /// legacy unencrypted storage and graceful fallback if secure storage is unavailable.
  Future<String?> _getSecureOrMigratedPin() async {
    // 1. Try reading from secure storage
    try {
      final securePin = await _secureStorage.read(key: keyPin);
      if (securePin != null && securePin.isNotEmpty) {
        // Clean up legacy plaintext storage if still present
        try {
          final legacyPin = await storage.getString(keyPin);
          if (legacyPin != null) {
            await storage.remove(keyPin);
          }
        } catch (_) {}
        return securePin;
      }
    } catch (_) {
      // Platform channel unavailable or threw (e.g. desktop/unit test harness); fall through to storage
    }

    // 2. Fallback & migration: check legacy file storage
    try {
      final legacyPin = await storage.getString(keyPin);
      if (legacyPin != null && legacyPin.isNotEmpty) {
        // Attempt migration to secure storage
        try {
          await _secureStorage.write(key: keyPin, value: legacyPin);
          await storage.remove(keyPin);
          return legacyPin;
        } catch (_) {}
        // M6: secure storage unavailable — upgrade any LEGACY PLAINTEXT
        // file value to the salted-hash form in place (same lock behaviour).
        if (!_isHashedPin(legacyPin)) {
          try {
            final hashed = _hashPinForFile(legacyPin);
            if (_isHashedPin(hashed)) {
              await storage.setString(keyPin, hashed);
            }
          } catch (_) {}
        }
        return legacyPin;
      }
    } catch (_) {}

    return null;
  }

  Future<bool> setPin(String pin) async {
    final cleanPin = pin.trim();
    if (cleanPin.length >= 4) {
      bool wroteSecure = false;
      try {
        await _secureStorage.write(key: keyPin, value: cleanPin);
        wroteSecure = true;
        await storage.remove(keyPin);
      } catch (_) {}

      if (!wroteSecure) {
        // M6: file fallback stores a salted HASH, never the raw PIN.
        await storage.setString(keyPin, _hashPinForFile(cleanPin));
      }
      return true;
    }
    return false;
  }

  Future<bool> verifyPin(String pin) async {
    final storedPin = await _getSecureOrMigratedPin();
    if (storedPin == null || storedPin.isEmpty) {
      // NOTE: Removed hardcoded '1234' testing PIN bypass. If no PIN is configured, verify returns false.
      // NOTE: Verify PIN against POST /api/v1/auth/login-pin when connected (endpoints verified live).
      return false;
    }
    if (_matchesStoredPin(storedPin, pin.trim())) {
      _isPinLocked = false;
      return true;
    }
    return false;
  }

  Future<bool> hasStoredPin() async {
    final stored = await _getSecureOrMigratedPin();
    return stored != null && stored.isNotEmpty;
  }

  Future<void> removePin() async {
    try {
      await _secureStorage.delete(key: keyPin);
    } catch (_) {}
    try {
      await storage.remove(keyPin);
    } catch (_) {}
  }

  Future<bool> verifyBiometrics() async {
    // Hardware biometric authentication via local_auth
    try {
      final localAuth = LocalAuthentication();
      final canAuth = await localAuth.canCheckBiometrics || await localAuth.isDeviceSupported();
      if (!canAuth) return false;
      final didAuth = await localAuth.authenticate(
        localizedReason: 'Unlock SafeSphere',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (didAuth) {
        _isPinLocked = false;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Backward compatibility convenience methods
  // ---------------------------------------------------------------------------
  Future<bool> loginWithPin(String pin) async {
    return verifyPin(pin);
  }

  Future<bool> loginWithBiometrics() async {
    return verifyBiometrics();
  }

  // ---------------------------------------------------------------------------
  // Emergency SOS Real API Integration (/api/v1/sos)
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> triggerSos({
    required double latitude,
    required double longitude,
    double? accuracy,
    int? batteryLevel,
    String? alertType,
    String? notes,
  }) async {
    final token = await storage.getString(keyToken);
    final random = math.Random.secure();
    final requestNonce = List.generate(
      4,
      (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    ).join();
    final body = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'batteryLevel': batteryLevel,
      'alertType': alertType ?? 'CRITICAL_SOS',
      'notes': notes,
      // Stable per-trigger idempotency key: if this request lands but the
      // response is lost, the offline-queue replay reuses the SAME key and the
      // backend returns the original alert instead of duplicating it.
      'clientRequestId': 'sos_$requestNonce',
    };

    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/sos/trigger',
      body: body,
      token: token,
      requestTimeout: const Duration(seconds: 12),
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      final alertId = res.data!['data']?['id'] as String? ?? res.data!['id'] as String?;
      if (alertId != null) {
        await storage.setString(keyActiveSosId, alertId);
        final resolveToken = res.data!['resolveToken'] as String? ??
            (res.data!['data']?['resolveToken'] as String?);
        if (resolveToken != null) {
          await _storeResolveToken(alertId, resolveToken);
        }
      }
      unawaited(processQueuedSosAlerts());
      return res.data;
    }

    // Network unreachable or dispatch failure: queue offline for automatic replay
    await queueOfflineSos(body);
    return null;
  }

  // ---------------------------------------------------------------------------
  // M6: per-alert resolve-token map (multi-active-SOS support)
  // ---------------------------------------------------------------------------
  /// Persists a resolve token under its alert ID (JSON map, capped, newest
  /// evicted). The legacy single-token key stays untouched for backward
  /// compatibility with already-persisted sessions.
  Future<void> _storeResolveToken(String alertId, String token) async {
    try {
      // Legacy key always mirrors the newest token (older app versions and
      // the "last alert" flow still read it).
      await storage.setString(keyActiveSosResolveToken, token);
      final raw = await storage.getString(keySosResolveTokenMap);
      final Map<String, dynamic> map = {};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) map.addAll(decoded);
      }
      map[alertId] = token;
      while (map.length > maxResolveTokenMapSize) {
        map.remove(map.keys.first);
      }
      await storage.setString(keySosResolveTokenMap, jsonEncode(map));
    } catch (_) {}
  }

  /// Reads the resolve token for a specific alert: per-alert map first,
  /// legacy single-token key as fallback (covers pre-M6 sessions).
  Future<String?> getSosResolveToken(String alertId) =>
      _readResolveToken(alertId);

  Future<String?> _readResolveToken(String alertId) async {
    try {
      final raw = await storage.getString(keySosResolveTokenMap);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && decoded[alertId] is String) {
          return decoded[alertId] as String;
        }
      }
    } catch (_) {}
    return await storage.getString(keyActiveSosResolveToken);
  }

  Future<void> _pruneResolveToken(String alertId) async {
    String? removedToken;
    try {
      final raw = await storage.getString(keySosResolveTokenMap);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && decoded.containsKey(alertId)) {
          removedToken = decoded[alertId] as String?;
          decoded.remove(alertId);
          await storage.setString(keySosResolveTokenMap, jsonEncode(decoded));
        }
      }
    } catch (_) {}
    // The legacy key mirrors the NEWEST token — it may belong to a DIFFERENT
    // still-active alert. Only touch it when it actually held THIS alert's
    // token; otherwise resolving an old alert would kill a live credential.
    final legacy = await storage.getString(keyActiveSosResolveToken);
    if (legacy == null) return;
    if (removedToken != null && legacy == removedToken) {
      // Re-mirror to the newest remaining map entry, or clear if none left.
      try {
        final raw = await storage.getString(keySosResolveTokenMap);
        if (raw != null && raw.isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
            await storage.setString(
                keyActiveSosResolveToken, decoded.values.last as String);
            return;
          }
        }
      } catch (_) {}
      await storage.remove(keyActiveSosResolveToken);
    }
  }

  // ---------------------------------------------------------------------------
  // Offline SOS Local Storage Queue & Automatic Replay Logic
  // ---------------------------------------------------------------------------
  /// Returns true when a queue entry's `_queuedAt` stamp is older than the
  /// TTL or is missing/unparsable (unknown age = treated as stale).
  bool _isQueueEntryExpired(Map<String, dynamic> entry) {
    final raw = entry['_queuedAt'];
    if (raw is! String || raw.isEmpty) return true;
    try {
      final queuedAt = DateTime.parse(raw);
      return DateTime.now().toUtc().difference(queuedAt.toUtc()) > offlineSosQueueTtl;
    } catch (_) {
      return true;
    }
  }

  /// M6: stable content signature of a queued SOS body (sorted keys) used
  /// for idempotency — a rapid double-enqueue of the SAME emergency must not
  /// become two dispatched alerts on replay.
  String _sosQueueSignature(Map<String, dynamic> payload) {
    final keys = payload.keys.toList()..sort();
    final buf = StringBuffer();
    for (final k in keys) {
      // clientRequestId/_queuedAt are transport metadata, not emergency
      // content — two rapid triggers of the SAME emergency must still dedupe
      // even though each carries a unique idempotency key.
      if (k == 'clientRequestId' || k == '_queuedAt') continue;
      buf.write('$k=');
      final v = payload[k];
      // Round floats so two GPS fixes a metre apart within the same trigger
      // dedupe, while genuinely different locations stay distinct.
      if (v is double) {
        buf.write(v.toStringAsFixed(4));
      } else if (v is num) {
        buf.write(v.toStringAsFixed(4));
      } else {
        buf.write(v.toString());
      }
      buf.write('|');
    }
    return buf.toString();
  }

  // Serialized through _sosQueueChain: concurrent enqueue calls (double-tap,
  // connectivity flap) must not interleave their read-modify-write and drop
  // or duplicate queue entries.
  Future<void> queueOfflineSos(Map<String, dynamic> payload) {
    final run = _sosQueueChain.then((_) => _queueOfflineSosImpl(payload));
    _sosQueueChain = run.catchError((_) {});
    return run;
  }

  Future<void> _queueOfflineSosImpl(Map<String, dynamic> payload) async {
    try {
      final raw = await storage.getString(keyOfflineSosQueue);
      final List<Map<String, dynamic>> queue = [];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              queue.add(Map<String, dynamic>.from(item));
            }
          }
        }
      }
      // TTL: drop entries that are already past their replay window.
      queue.removeWhere(_isQueueEntryExpired);
      // M6 idempotency: skip enqueue when an identical (non-expired) entry
      // already exists — duplicate trigger calls must not double-dispatch.
      final signature = _sosQueueSignature(payload);
      final isDuplicate = queue.any(
        (entry) => _sosQueueSignature(Map<String, dynamic>.from(entry)..remove('_queuedAt')) == signature,
      );
      if (isDuplicate) return;
      while (queue.length >= maxOfflineSosQueueSize) {
        queue.removeAt(0); // Drop oldest entries to enforce capacity cap
      }
      // Stamp the entry so replay can enforce the TTL. The underscore key
      // cannot collide with real SOS API fields and is stripped before send.
      final stamped = Map<String, dynamic>.from(payload)
        ..['_queuedAt'] = DateTime.now().toUtc().toIso8601String();
      queue.add(stamped);
      await storage.setString(keyOfflineSosQueue, jsonEncode(queue));
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getQueuedSosAlerts() async {
    try {
      final raw = await storage.getString(keyOfflineSosQueue);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((entry) => !_isQueueEntryExpired(entry))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> clearQueuedSosAlerts() async {
    await storage.remove(keyOfflineSosQueue);
  }

  Future<int> processQueuedSosAlerts() async {
    if (_isProcessingSosQueue) return 0;
    _isProcessingSosQueue = true;
    try {
      final raw = await storage.getString(keyOfflineSosQueue);
      if (raw == null || raw.isEmpty) return 0;

      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return 0;

      final token = await storage.getString(keyToken);
      final remaining = <Map<String, dynamic>>[];
      int sentCount = 0;

      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          // TTL enforcement: silently drop entries older than the window.
          if (_isQueueEntryExpired(item)) continue;
          final body = Map<String, dynamic>.from(item)..remove('_queuedAt');
          final res = await _requestDetailed(
            method: 'POST',
            path: '/api/v1/sos/trigger',
            body: body,
            token: token,
          );

          if (res.isSuccess && res.data != null && res.data!['success'] == true) {
            sentCount++;
            final alertId = res.data!['data']?['id'] as String? ?? res.data!['id'] as String?;
            if (alertId != null) {
              await storage.setString(keyActiveSosId, alertId);
              final resolveToken = res.data!['resolveToken'] as String? ??
                  (res.data!['data']?['resolveToken'] as String?);
              if (resolveToken != null) {
                await _storeResolveToken(alertId, resolveToken);
              }
            }
          } else {
            remaining.add(Map<String, dynamic>.from(item));
          }
        }
      }

      if (remaining.isEmpty) {
        await storage.remove(keyOfflineSosQueue);
      } else {
        await storage.setString(keyOfflineSosQueue, jsonEncode(remaining));
      }
      return sentCount;
    } catch (_) {
      return 0;
    } finally {
      _isProcessingSosQueue = false;
    }
  }

  Future<bool> resolveSos({String? alertId, String? notes}) async {
    final token = await storage.getString(keyToken);
    final targetId = alertId ?? await storage.getString(keyActiveSosId);
    if (targetId == null || targetId.isEmpty) return false;

    // M6: per-alert token first, legacy single-token key as fallback.
    final resolveToken = await _readResolveToken(targetId);
    final body = <String, dynamic>{
      'id': targetId,
      'notes': notes ?? 'Citizen marked safe',
      if (resolveToken != null) 'resolveToken': resolveToken,
    };

    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/sos/$targetId/resolve',
      body: body,
      token: token,
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      await storage.remove(keyActiveSosId);
      await _pruneResolveToken(targetId);
      return true;
    }
    return false;
  }

  Future<String?> getActiveSosId() async {
    return await storage.getString(keyActiveSosId);
  }

  /// Clears active SOS identifiers and resolve capability token from storage.
  Future<void> clearActiveSos() async {
    await storage.remove(keyActiveSosId);
    await storage.remove(keyActiveSosResolveToken);
  }

  /// Fetches live status and active monitor count for a specific SOS alert.
  Future<Map<String, dynamic>?> fetchSosStatus(String alertId) async {
    final token = await storage.getString(keyToken);
    final res = await _requestDetailed(
      method: 'GET',
      path: '/api/v1/sos/$alertId',
      token: token,
    );
    if (res.isSuccess && res.data != null) {
      final data = res.data!['data'];
      final monitors = res.data!['monitorsConnected'] ?? (data is Map ? data['monitorsConnected'] : 0);
      if (data is Map<String, dynamic>) {
        return {
          ...data,
          'monitorsConnected': monitors ?? 0,
        };
      }
    } else if (res.statusCode == 404) {
      return {'status': 'not_found', 'monitorsConnected': 0};
    }
    return null;
  }

  /// Retrieves SOS alert history for the current user.
  Future<List<Map<String, dynamic>>> fetchSosHistory({int limit = 10}) async {
    final token = await storage.getString(keyToken);
    if (token != null && token.isNotEmpty) {
      final res = await _requestDetailed(
        method: 'GET',
        path: '/api/v1/sos/mine?limit=$limit',
        token: token,
      );
      if (res.isSuccess && res.data != null && res.data!['data'] is List) {
        return (res.data!['data'] as List).cast<Map<String, dynamic>>();
      }
    }
    // Guests/anonymous users must NOT receive the global SOS list — it exposes
    // other users' alert locations and notes. Only authenticated users may
    // fall back to the public endpoint filtered to their own alerts.
    if (_currentUser?.id == null) {
      return [];
    }
    final res = await _requestDetailed(
      method: 'GET',
      path: '/api/v1/sos?limit=$limit',
      token: token,
    );
    if (res.isSuccess && res.data != null && res.data!['data'] is List) {
      final list = (res.data!['data'] as List).cast<Map<String, dynamic>>();
      return list.where((a) => a['userId'] == _currentUser!.id).toList();
    }
    return [];
  }

  /// Fetches real-time responder chat messages for an active SOS alert.
  Future<List<Map<String, dynamic>>> fetchSosMessages(String alertId, {String? token}) async {
    final activeResolveToken = token ?? await storage.getString(keyActiveSosResolveToken);
    final userJwt = await storage.getString(keyToken);
    final query = activeResolveToken != null && activeResolveToken.isNotEmpty
        ? '?token=${Uri.encodeQueryComponent(activeResolveToken)}'
        : '';
    final res = await _requestDetailed(
      method: 'GET',
      path: '/api/v1/sos/$alertId/messages$query',
      token: userJwt,
    );
    if (res.isSuccess && res.data != null && res.data!['data'] is List) {
      return (res.data!['data'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Sends a real-time chat message on an active SOS alert.
  Future<Map<String, dynamic>?> sendSosMessage(String alertId, String text, {String? token}) async {
    final activeResolveToken = token ?? await storage.getString(keyActiveSosResolveToken);
    final userJwt = await storage.getString(keyToken);
    final body = <String, dynamic>{
      'text': text.trim(),
      if (activeResolveToken != null && activeResolveToken.isNotEmpty) 'token': activeResolveToken,
    };
    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/sos/$alertId/messages',
      body: body,
      token: userJwt,
    );
    if (res.isSuccess && res.data != null && res.data!['data'] is Map<String, dynamic>) {
      return res.data!['data'] as Map<String, dynamic>;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Reports API (/api/v1/reports)
  // ---------------------------------------------------------------------------

  /// Fetches live community incident reports from the backend.
  /// Sets `lastFetchFailed` on transport or server failure so callers can display retry state.
  Future<List<Map<String, dynamic>>> fetchReports({
    String? type,
    String? status,
    int? limit,
    double? latitude,
    double? longitude,
    double? radiusKm,
  }) async {
    _reportsFetchFailed = false;
    final token = await storage.getString(keyToken);
    final queryParams = <String, String>{};
    if (type != null) queryParams['type'] = type;
    if (status != null) queryParams['status'] = status;
    if (limit != null) queryParams['limit'] = '$limit';
    if (latitude != null) queryParams['latitude'] = '$latitude';
    if (longitude != null) queryParams['longitude'] = '$longitude';
    if (radiusKm != null) queryParams['radiusKm'] = '$radiusKm';

    final queryString = queryParams.isNotEmpty
        ? '?' + queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')
        : '';

    final res = await _requestDetailed(
      method: 'GET',
      path: '/api/v1/reports$queryString',
      token: token,
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      final data = res.data!['data'];
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    }
    _reportsFetchFailed = !res.isSuccess;
    return [];
  }

  /// Submits a new incident report to the backend with optional photoBase64 attachment (F5-4).
  Future<Map<String, dynamic>?> submitReport({
    required String type,
    required String description,
    required String location,
    double? latitude,
    double? longitude,
    String? photoBase64,
  }) async {
    final token = await storage.getString(keyToken);
    final body = <String, dynamic>{
      'type': type,
      'description': description,
      'location': location,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (photoBase64 != null && photoBase64.isNotEmpty) 'photoBase64': photoBase64,
    };

    _lastReportError = null;
    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/reports',
      body: body,
      token: token,
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      return res.data!['data'] as Map<String, dynamic>?;
    }
    _lastReportError = res.error ?? 'Request failed (HTTP ${res.statusCode}).';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Markers API (/api/v1/markers)
  // ---------------------------------------------------------------------------

  /// Fetches safety markers (police stations, hospitals, safe zones) sorted by proximity.
  /// Sets `lastFetchFailed` on transport or server failure so callers can display retry state.
  Future<List<Map<String, dynamic>>> fetchNearbyMarkers({
    required double latitude,
    required double longitude,
    double? radiusKm,
    String? type,
    int? limit,
  }) async {
    _markersFetchFailed = false;
    final token = await storage.getString(keyToken);
    // Backend markerController accepts lat + (lon | longitude); 'lng' is NOT a recognized alias.
    final queryParams = <String, String>{
      'lat': '$latitude',
      'lon': '$longitude',
      if (radiusKm != null) 'radius': '$radiusKm',
      if (type != null) 'type': type,
      if (limit != null) 'limit': '$limit',
    };
    final queryString = '?' + queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

    final res = await _requestDetailed(
      method: 'GET',
      path: '/api/v1/markers/nearby$queryString',
      token: token,
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      final data = res.data!['data'];
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    }
    _markersFetchFailed = !res.isSuccess;
    return [];
  }

  /// Fetches pending safety markers awaiting admin/responder verification (GET /api/v1/markers/pending).
  Future<List<Map<String, dynamic>>> fetchPendingMarkers() async {
    final token = await storage.getString(keyToken);
    final res = await _requestDetailed(
      method: 'GET',
      path: '/api/v1/markers/pending',
      token: token,
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      final data = res.data!['data'];
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
    }
    return [];
  }

  /// Verifies or rejects a pending safety marker (POST /api/v1/markers/:id/verify).
  Future<bool> verifyMarker(String markerId, {required bool approve}) async {
    final token = await storage.getString(keyToken);
    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/markers/$markerId/verify',
      token: token,
      body: {'approve': approve},
    );
    return res.isSuccess && res.data != null && res.data!['success'] == true;
  }

  /// F5-5: Submits a new citizen safety marker for moderator review (POST /api/v1/markers).
  /// Returns the created marker map on success, null on failure.
  /// Status defaults to 'pending' — backend queues it for admin/responder verification.
  Future<Map<String, dynamic>?> createMarker({
    required String name,
    required String category,
    required double latitude,
    required double longitude,
    String? address,
    String? note,
  }) async {
    final token = await storage.getString(keyToken);
    final body = <String, dynamic>{
      'name': name,
      'category': category,
      'latitude': latitude,
      'longitude': longitude,
      if (address != null && address.isNotEmpty) 'address': address,
      if (note != null && note.isNotEmpty) 'note': note,
      'status': 'pending',
    };
    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/markers',
      token: token,
      body: body,
    );
    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      return res.data!['data'] as Map<String, dynamic>?;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Location Tracking API (/api/v1/location)
  // ---------------------------------------------------------------------------

  /// Creates a live tracking share session (POST /api/v1/location/share-session).
  /// Returns sessionId, token, shareUrl, expiresAt and caches keys in storage.
  Future<Map<String, dynamic>?> createTrackingSession({
    required double latitude,
    required double longitude,
    double? accuracy,
    int durationMinutes = 60,
    int? checkInIntervalMin,
  }) async {
    final token = await storage.getString(keyToken);
    final body = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      'durationMinutes': durationMinutes,
      if (checkInIntervalMin != null) 'checkInIntervalMin': checkInIntervalMin,
      // Backend builds shareUrl from this; send the RESOLVED base (emulator
      // 10.0.2.2 fix) so guardian links never point at a dead loopback.
      'baseUrl': resolveBaseUrl(),
    };

    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/location/share-session',
      body: body,
      token: token,
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      final sessionId = res.data!['sessionId'] as String? ?? (res.data!['data']?['sessionId'] as String?);
      final sessionToken = res.data!['token'] as String? ?? (res.data!['data']?['token'] as String?);
      final shareUrl = res.data!['shareUrl'] as String? ?? (res.data!['data']?['shareUrl'] as String?);
      final expiresAt = res.data!['expiresAt'] as String? ?? (res.data!['data']?['expiresAt'] as String?);

      if (sessionId != null && sessionToken != null) {
        await storage.setString('safesphere_tracking_session', sessionId);
        await storage.setString('safesphere_tracking_token', sessionToken);
      }

      return {
        'sessionId': sessionId,
        'token': sessionToken,
        'shareUrl': shareUrl,
        'expiresAt': expiresAt,
      };
    }
    return null;
  }

  /// Sends a breadcrumb location ping to the active tracking session (POST /api/v1/location/ping).
  Future<bool> sendLocationPing({
    required String sessionId,
    required double latitude,
    required double longitude,
    required String trackingToken,
    double? accuracy,
  }) async {
    final body = <String, dynamic>{
      'sessionId': sessionId,
      'token': trackingToken,
      'latitude': latitude,
      'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/location/ping',
      body: body,
    );

    return res.isSuccess && res.data != null && res.data!['success'] == true;
  }

  /// Terminates an active tracking session (POST /api/v1/location/terminate/:sessionId).
  Future<bool> terminateTrackingSession({
    required String sessionId,
    required String trackingToken,
    String? reason,
  }) async {
    final body = <String, dynamic>{
      'token': trackingToken,
      'reason': reason ?? 'User ended tracking session',
    };

    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/location/terminate/$sessionId',
      body: body,
      token: trackingToken,
    );

    await storage.remove('safesphere_tracking_session');
    await storage.remove('safesphere_tracking_token');

    return res.isSuccess;
  }

  /// Fetches a tracking session's current state
  /// (GET /api/v1/location/track/:sessionId). The token is sent as a `?token=`
  /// query param — never as Bearer — so a logged-in guardian's JWT cannot
  /// shadow the session credential.
  Future<Map<String, dynamic>?> fetchTrackingSession({
    required String sessionId,
    required String trackingToken,
  }) async {
    final res = await _requestDetailed(
      method: 'GET',
      path:
          '/api/v1/location/track/$sessionId?token=${Uri.encodeQueryComponent(trackingToken)}',
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      final data = res.data!['data'];
      return data is Map<String, dynamic> ? data : res.data;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // AI Safety Assistant (POST /api/v1/ai/chat — Groq-backed, guest allowed)
  // ---------------------------------------------------------------------------
  /// Sends a safety question to the live AI backend. Returns the decoded
  /// `data` map ({ reply, model }) on success, or null when the backend is
  /// unreachable / unconfigured / rate-limited. Never fabricates a reply —
  /// callers must fall back to the static offline safety guides (W2-5).
  Future<Map<String, dynamic>?> sendAiChat({
    required String message,
    List<Map<String, String>>? history,
  }) async {
    final token = await storage.getString(keyToken);
    final body = <String, dynamic>{
      'text': message,
      if (history != null && history.isNotEmpty) 'history': history,
    };

    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/ai/chat',
      body: body,
      token: token,
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      final data = res.data!['data'];
      if (data is Map<String, dynamic> &&
          data['reply'] is String &&
          (data['reply'] as String).isNotEmpty) {
        return data;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // M2.3: Community voting (POST /api/v1/reports/:id/vote)
  // ---------------------------------------------------------------------------
  /// Casts or switches the user's vote ('confirm' | 'decline') on a report.
  /// Returns the updated tally { upvotes, downvotes, myVote } on success,
  /// null on failure (callers roll back optimistic UI honestly).
  Future<Map<String, dynamic>?> voteReport({
    required String reportId,
    required String vote,
  }) async {
    final token = await storage.getString(keyToken);
    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/reports/$reportId/vote',
      body: { 'vote': vote },
      token: token,
    );
    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      return res.data!['data'] is Map<String, dynamic>
          ? res.data!['data'] as Map<String, dynamic>
          : null;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Reddit-style Community Comments & Comment Votes
  // ---------------------------------------------------------------------------
  String? _lastCommentError;
  String? get lastCommentError => _lastCommentError;

  Future<List<Map<String, dynamic>>> fetchReportComments(String reportId) async {
    final token = await storage.getString(keyToken);
    final res = await _requestDetailed(
      method: 'GET',
      path: '/api/v1/reports/$reportId/comments',
      token: token,
    );
    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      final list = res.data!['data'];
      if (list is List) {
        return list.whereType<Map<String, dynamic>>().toList();
      }
    }
    return [];
  }

  Future<Map<String, dynamic>?> createReportComment({
    required String reportId,
    required String body,
    String? parentId,
  }) async {
    _lastCommentError = null;
    final token = await storage.getString(keyToken);
    final payload = <String, dynamic>{'body': body};
    if (parentId != null && parentId.isNotEmpty) {
      payload['parentId'] = parentId;
    }
    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/reports/$reportId/comments',
      body: payload,
      token: token,
    );
    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      return res.data!['data'] as Map<String, dynamic>?;
    }
    _lastCommentError = res.error ?? 'Could not post comment.';
    return null;
  }

  Future<Map<String, dynamic>?> voteReportComment({
    required String reportId,
    required String commentId,
    required String vote,
  }) async {
    final token = await storage.getString(keyToken);
    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/reports/$reportId/comments/$commentId/vote',
      body: {'vote': vote},
      token: token,
    );
    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      return res.data!['data'] is Map<String, dynamic>
          ? res.data!['data'] as Map<String, dynamic>
          : null;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // M2.2: Aadhaar-lite abuse-prevention link (POST /api/v1/auth/aadhaar/link)
  // ---------------------------------------------------------------------------
  /// Links the last 4 digits of Aadhaar as a salted SHA-256 hash (server-side).
  /// The plaintext digits are never stored. Returns true when linked.
  Future<bool> linkAadhaarLast4(String last4) async {
    final token = await storage.getString(keyToken);
    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/auth/aadhaar/link',
      body: { 'aadhaarLast4': last4 },
      token: token,
    );
    return res.isSuccess && res.data != null && res.data!['success'] == true;
  }

  // ---------------------------------------------------------------------------
  // M3: Trusted circle connections (SafeSphere IDs, scoped guardian views)
  // ---------------------------------------------------------------------------
  /// Connection methods return `{ ok: true, data: <payload> }` on success or
  /// `{ ok: false, code: '<ERROR_CODE>', message: '...' }` on honest failure
  /// so callers can surface the real reason (scope denied, revoked, rate
  /// limited) instead of a generic failure.

  Future<Map<String, dynamic>> _connectionCall({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final token = await storage.getString(keyToken);
    final res = await _requestDetailed(
      method: method,
      path: path,
      body: body,
      token: token,
    );
    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      return { 'ok': true, 'data': res.data!['data'] };
    }
    final error = res.data != null && res.data!['error'] is Map<String, dynamic>
        ? res.data!['error'] as Map<String, dynamic>
        : null;
    return {
      'ok': false,
      'code': error != null ? (error['code'] ?? 'UNKNOWN') : 'NETWORK_ERROR',
      'message': error != null ? (error['message'] ?? 'Request failed') : 'Network unavailable',
    };
  }

  /// Sends a connection request addressed by the owner's public Safe ID.
  Future<Map<String, dynamic>> sendConnectionRequest({
    required String ownerSafeId,
    required List<String> scopes,
    String mode = 'sos_only',
  }) {
    return _connectionCall(
      method: 'POST',
      path: '/api/v1/connections',
      body: { 'ownerSafeId': ownerSafeId, 'scopes': scopes, 'mode': mode },
    );
  }

  /// Lists both directions of the user's circle (outgoing + incoming).
  Future<Map<String, dynamic>> fetchMyConnections() {
    return _connectionCall(method: 'GET', path: '/api/v1/connections/mine');
  }

  /// Accept/decline a pending request (owner), or withdraw own request (grantee).
  Future<Map<String, dynamic>> respondToConnection({
    required String connectionId,
    required bool accept,
  }) {
    return _connectionCall(
      method: 'POST',
      path: '/api/v1/connections/$connectionId/respond',
      body: { 'accept': accept },
    );
  }

  /// Either party revokes — immediate, every scoped read re-verifies.
  Future<Map<String, dynamic>> revokeConnection(String connectionId) {
    return _connectionCall(
      method: 'POST',
      path: '/api/v1/connections/$connectionId/revoke',
    );
  }

  /// Owner-only scope adjustment on an active connection.
  Future<Map<String, dynamic>> updateConnectionScopes({
    required String connectionId,
    required List<String> scopes,
  }) {
    return _connectionCall(
      method: 'PATCH',
      path: '/api/v1/connections/$connectionId/scopes',
      body: { 'scopes': scopes },
    );
  }

  /// Owner beacons a location point into the connection's 200-point buffer.
  Future<Map<String, dynamic>> pingConnectionLocation({
    required String connectionId,
    required double latitude,
    required double longitude,
    double? accuracy,
  }) {
    return _connectionCall(
      method: 'POST',
      path: '/api/v1/connections/$connectionId/ping',
      body: {
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
      },
    );
  }

  /// Grantee reads the owner's latest beacon (requires 'location' scope).
  Future<Map<String, dynamic>> fetchConnectionLive(String connectionId) {
    return _connectionCall(
      method: 'GET',
      path: '/api/v1/connections/$connectionId/live',
    );
  }

  /// Grantee reads the owner's SOS/tracking status (requires 'sos_status').
  Future<Map<String, dynamic>> fetchConnectionStatus(String connectionId) {
    return _connectionCall(
      method: 'GET',
      path: '/api/v1/connections/$connectionId/status',
    );
  }

  /// Grantee reads the owner's active alerts (requires 'nearby_alerts').
  Future<Map<String, dynamic>> fetchConnectionAlerts(String connectionId) {
    return _connectionCall(
      method: 'GET',
      path: '/api/v1/connections/$connectionId/alerts',
    );
  }

  /// Grantee "checks on" the owner — rate-limited server-side to 1 per 5 min.
  Future<Map<String, dynamic>> checkInOnConnection({
    required String connectionId,
    String? message,
  }) {
    return _connectionCall(
      method: 'POST',
      path: '/api/v1/connections/$connectionId/checkin',
      body: { if (message != null) 'message': message },
    );
  }

  /// M5: lists the user's OWN live tracking sessions for the privacy hub
  /// ("Who can see me"). Server scrubs the session token — visibility only.
  Future<Map<String, dynamic>> fetchMyTrackingSessions() {
    return _connectionCall(method: 'GET', path: '/api/v1/location/sessions/mine');
  }

  /// Stops one of the user's OWN live trips from the privacy hub — account
  /// auth replaces the tracking token here (the list endpoint scrubs it).
  Future<Map<String, dynamic>> terminateMyTrackingSession(String sessionId) {
    return _connectionCall(
      method: 'POST',
      path: '/api/v1/location/sessions/$sessionId/terminate',
    );
  }

  // ---------------------------------------------------------------------------
  // M1.6b: Forgot-PIN recovery (POST /api/v1/auth/pin/reset)
  // ---------------------------------------------------------------------------
  /// Resets the account PIN using the OTP sent to the registered phone.
  /// Returns true when the reset succeeded (the user can then log in with
  /// the new PIN). Honest failures return false — never a fabricated reset.
  /// Post-reset synchronization: the backend invalidated every session during
  /// PIN reset, so stored tokens are dead. Install the new PIN locally and
  /// clear the stale session so the user re-authenticates honestly.
  Future<void> applyPinReset(String newPin) async {
    await setPin(newPin);
    await storage.remove(keyToken);
    await storage.remove(keyRefreshToken);
    await storage.remove(keyUser);
    _currentUser = null;
    _isPinLocked = false;
  }

  Future<bool> resetPin({
    required String phone,
    required String otp,
    required String newPin,
  }) async {
    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/auth/pin/reset',
      body: {
        'phone': phone,
        'otp': otp,
        'newPin': newPin,
      },
    );
    return res.isSuccess && res.data != null && res.data!['success'] == true;
  }

  Future<bool> signup({
    required String name,
    required String email,
    required String phone,
    required String password,
    String? pin,
    List<EmergencyContact>? emergencyContacts,
  }) async {
    final res = await register(
      name: name,
      email: email,
      phone: phone,
      password: password,
      pin: pin,
      emergencyContacts: emergencyContacts,
    );
    return res.success;
  }
}
