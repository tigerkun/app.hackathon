import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/user_model.dart';
import '../models/auth_tokens.dart';
import 'storage_service.dart';

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

  static AuthService? _singleton;

  /// Shared singleton instance for callers that do not need custom config.
  static AuthService get instance => AuthService();

  factory AuthService({
    String? baseUrl,
    IStorageService? storage,
  }) {
    if (baseUrl != null || storage != null) {
      return AuthService._internal(
        baseUrl: baseUrl ?? 'http://127.0.0.1:3000',
        storage: storage ?? StorageService(),
      );
    }
    _singleton ??= AuthService._internal(
      baseUrl: 'http://127.0.0.1:3000',
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

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && !_currentUser!.isGuest;
  bool get isPinLocked => _isPinLocked;

  // ---------------------------------------------------------------------------
  // Networking HTTP Helper
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    String? token,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);

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
      final responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (responseBody.isNotEmpty) {
        final decoded = jsonDecode(responseBody);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      return null;
    } catch (_) {
      // In offline / isolated network mode, graceful fallback handled by caller
      return null;
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
        await storage.setString(keyPin, pin);
      }

      _currentUser = user;
      return AuthResult(success: true, message: 'Registration successful', user: user, tokens: tokens);
    }

    // NOTE: Removed dangerous fabricated offline auth fallback (fake tokens and simulated user).
    // An offline or unreachable backend must return an honest error instead of granting a phantom authenticated state.
    // TODO(REAL_BACKEND): Ensure backend /api/v1/auth/register endpoint is reachable and healthy.
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
    // TODO(REAL_BACKEND): Verify credentials against real backend POST /api/v1/auth/login.
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
    // TODO(REAL_BACKEND): Wire to active SMS gateway endpoint.
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
    // TODO(REAL_BACKEND): Verify OTP code against backend POST /api/v1/auth/otp/verify.
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

  // ---------------------------------------------------------------------------
  // Local PIN & Biometrics Management
  // ---------------------------------------------------------------------------
  Future<bool> setPin(String pin) async {
    if (pin.trim().length >= 4) {
      await storage.setString(keyPin, pin.trim());
      return true;
    }
    return false;
  }

  Future<bool> verifyPin(String pin) async {
    final storedPin = await storage.getString(keyPin);
    if (storedPin == null || storedPin.isEmpty) {
      // NOTE: Removed hardcoded '1234' testing PIN bypass. If no PIN is configured, verify returns false.
      // TODO(REAL_BACKEND): Verify PIN against POST /api/v1/auth/login-pin when connected.
      return false;
    }
    if (storedPin == pin.trim()) {
      _isPinLocked = false;
      return true;
    }
    return false;
  }

  Future<bool> hasStoredPin() async {
    final stored = await storage.getString(keyPin);
    return stored != null && stored.isNotEmpty;
  }

  Future<bool> verifyBiometrics() async {
    // NOTE: Removed fake mock validation (Future.delayed 300ms returning true unconditionally).
    // TODO(REAL_HARDWARE): Integrate real hardware biometric scanning via local_auth package.
    // For now, return false so unauthorized biometric bypass is blocked.
    _isPinLocked = true;
    return false;
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

    final res = await _request(
      method: 'POST',
      path: '/api/v1/sos/trigger',
      body: body,
      token: token,
    );

    if (res != null && res['success'] == true) {
      final alertId = res['data']?['id'] as String? ?? res['id'] as String?;
      if (alertId != null) {
        await storage.setString('safesphere_active_sos_id', alertId);
      }
      return res;
    }
    return null;
  }

  Future<bool> resolveSos({String? alertId, String? notes}) async {
    final token = await storage.getString(keyToken);
    final targetId = alertId ?? await storage.getString('safesphere_active_sos_id');
    if (targetId == null || targetId.isEmpty) return false;

    final body = <String, dynamic>{
      'id': targetId,
      'notes': notes ?? 'Citizen marked safe',
    };

    final res = await _request(
      method: 'POST',
      path: '/api/v1/sos/$targetId/resolve',
      body: body,
      token: token,
    );

    if (res != null && res['success'] == true) {
      await storage.remove('safesphere_active_sos_id');
      return true;
    }
    return false;
  }

  Future<String?> getActiveSosId() async {
    return await storage.getString('safesphere_active_sos_id');
  }

  // ---------------------------------------------------------------------------
  // Reports API (/api/v1/reports)
  // ---------------------------------------------------------------------------

  /// Fetches live community incident reports from the backend.
  /// Optional filters: type (e.g. "Theft"), status (e.g. "pending"), limit.
  Future<List<Map<String, dynamic>>> fetchReports({
    String? type,
    String? status,
    int? limit,
  }) async {
    final token = await storage.getString(keyToken);
    final queryParams = <String, String>{};
    if (type != null) queryParams['type'] = type;
    if (status != null) queryParams['status'] = status;
    if (limit != null) queryParams['limit'] = '$limit';

    final queryString = queryParams.isNotEmpty
        ? '?' + queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')
        : '';

    final res = await _request(
      method: 'GET',
      path: '/api/v1/reports$queryString',
      token: token,
    );

    if (res != null && res['success'] == true) {
      final data = res['data'];
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
    }
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

    final res = await _request(
      method: 'POST',
      path: '/api/v1/reports',
      body: body,
      token: token,
    );

    if (res != null && res['success'] == true) {
      return res['data'] as Map<String, dynamic>?;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Markers API (/api/v1/markers)
  // ---------------------------------------------------------------------------

  /// Fetches safety markers (police stations, hospitals, safe zones) sorted by proximity.
  Future<List<Map<String, dynamic>>> fetchNearbyMarkers({
    required double latitude,
    required double longitude,
    double? radiusKm,
    String? type,
    int? limit,
  }) async {
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

    final res = await _request(
      method: 'GET',
      path: '/api/v1/markers/nearby$queryString',
      token: token,
    );

    if (res != null && res['success'] == true) {
      final data = res['data'];
      if (data is List) {
        return data.cast<Map<String, dynamic>>();
      }
    }
    return [];
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
