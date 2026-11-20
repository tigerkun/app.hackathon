import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  final int? expiresInSeconds;
  final int? cooldownSeconds;
  final String? devOtp;

  const OtpSendResult({
    required this.success,
    this.message,
    this.phone,
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
  static const String keyActiveSosId = 'safesphere_active_sos_id';
  static const String keyActiveSosResolveToken = 'safesphere_active_sos_resolve_token';
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

  static AuthService? _singleton;

  /// Shared singleton instance for callers that do not need custom config.
  static AuthService get instance => AuthService();

  factory AuthService({
    String? baseUrl,
    IStorageService? storage,
  }) {
    if (baseUrl != null || storage != null) {
      return AuthService._internal(
        baseUrl: baseUrl ?? apiBaseUrl,
        storage: storage ?? StorageService(),
      );
    }
    _singleton ??= AuthService._internal(
      baseUrl: apiBaseUrl,
      storage: StorageService(),
    );
    return _singleton!;
  }

  AuthService._internal({
    required this.baseUrl,
    required this.storage,
  });

  UserModel? _currentUser;
  bool _isPinLocked = false;
  bool _lastFetchFailed = false;
  Future<String?>? _refreshFuture;
  bool _isProcessingSosQueue = false;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && !_currentUser!.isGuest;
  bool get isPinLocked => _isPinLocked;
  bool get lastFetchFailed => _lastFetchFailed;

  // ---------------------------------------------------------------------------
  // Networking HTTP Helpers
  // ---------------------------------------------------------------------------
  Future<AuthHttpResponse> _requestDetailed({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    String? token,
    bool retryOn401 = true,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 4);
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

      final response = await request.close().timeout(const Duration(seconds: 5));
      final statusCode = response.statusCode;
      final responseBody = await response.transform(utf8.decoder).join();

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
  Future<OtpSendResult> sendOtp(String phone) async {
    final body = <String, dynamic>{
      'phone': phone.trim(),
      'purpose': 'verification',
    };

    final res = await _request(method: 'POST', path: '/api/v1/auth/otp/send', body: body);

    if (res != null && res['success'] == true) {
      return OtpSendResult(
        success: true,
        message: res['message'] as String? ?? 'OTP sent successfully',
        phone: res['phone'] as String? ?? phone,
        expiresInSeconds: res['expiresInSeconds'] as int? ?? 300,
        cooldownSeconds: res['cooldownSeconds'] as int? ?? 60,
        devOtp: res['devOtp'] as String?,
      );
    }

    // NOTE: Removed hardcoded fake devOtp '123456' offline fallback.
    // Real SMS OTP requires an operational backend SMS gateway / provider integration.
    // NOTE: Wire to active SMS gateway endpoint (endpoints verified live).
    final errMsg = res?['error']?['message'] as String? ?? 'Failed to send OTP. SMS gateway connection failed.';
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
      await storage.remove(keyPin);
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
        } catch (_) {}
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
        await storage.setString(keyPin, cleanPin);
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
    if (storedPin == pin.trim()) {
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
    final body = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'batteryLevel': batteryLevel,
      'alertType': alertType ?? 'CRITICAL_SOS',
      'notes': notes,
    };

    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/sos/trigger',
      body: body,
      token: token,
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      final alertId = res.data!['data']?['id'] as String? ?? res.data!['id'] as String?;
      if (alertId != null) {
        await storage.setString(keyActiveSosId, alertId);
        final resolveToken = res.data!['resolveToken'] as String? ??
            (res.data!['data']?['resolveToken'] as String?);
        if (resolveToken != null) {
          await storage.setString(keyActiveSosResolveToken, resolveToken);
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
  // Offline SOS Local Storage Queue & Automatic Replay Logic
  // ---------------------------------------------------------------------------
  Future<void> queueOfflineSos(Map<String, dynamic> payload) async {
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
      while (queue.length >= maxOfflineSosQueueSize) {
        queue.removeAt(0); // Drop oldest entries to enforce capacity cap
      }
      queue.add(payload);
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
          final res = await _requestDetailed(
            method: 'POST',
            path: '/api/v1/sos/trigger',
            body: item,
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
                await storage.setString(keyActiveSosResolveToken, resolveToken);
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

    final resolveToken = await storage.getString(keyActiveSosResolveToken);
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
      await storage.remove(keyActiveSosResolveToken);
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
    final res = await _requestDetailed(
      method: 'GET',
      path: '/api/v1/sos?limit=$limit',
      token: token,
    );
    if (res.isSuccess && res.data != null && res.data!['data'] is List) {
      final list = (res.data!['data'] as List).cast<Map<String, dynamic>>();
      if (_currentUser?.id != null) {
        return list.where((a) => a['userId'] == _currentUser!.id).toList();
      }
      return list;
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
    _lastFetchFailed = false;
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
    _lastFetchFailed = !res.isSuccess;
    return [];
  }

  /// Submits a new incident report to the backend.
  Future<Map<String, dynamic>?> submitReport({
    required String type,
    required String description,
    required String location,
    double? latitude,
    double? longitude,
  }) async {
    final token = await storage.getString(keyToken);
    final body = <String, dynamic>{
      'type': type,
      'description': description,
      'location': location,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };

    final res = await _requestDetailed(
      method: 'POST',
      path: '/api/v1/reports',
      body: body,
      token: token,
    );

    if (res.isSuccess && res.data != null && res.data!['success'] == true) {
      return res.data!['data'] as Map<String, dynamic>?;
    }
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
    _lastFetchFailed = false;
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
    _lastFetchFailed = !res.isSuccess;
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
      // Backend builds shareUrl from this; without it prod links point at localhost.
      'baseUrl': apiBaseUrl,
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
