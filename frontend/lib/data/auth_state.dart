import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

enum AuthStatus {
  initial,
  unauthenticated,
  guest,          // Emergency bypass active
  authenticated,  // Full verified session
  pinLocked,      // Fast PIN keypad barrier
  otpPending,     // Phone verification in flight
  loading,        // Network / storage in flight
}

class AuthState extends ChangeNotifier {
  final AuthService authService;

  static AuthState? _instance;
  factory AuthState({AuthService? authService}) {
    if (_instance == null || authService != null) {
      _instance = AuthState._internal(authService: authService ?? AuthService());
    }
    return _instance!;
  }

  AuthState._internal({required this.authService});

  AuthStatus _status = AuthStatus.initial;
  UserModel? _currentUser;
  String? _errorMessage;
  String? _pendingPhone;
  bool _isOnboarded = false;
  String? _consentVersion;
  String? _consentTimestamp;

  AuthStatus get status => _status;
  UserModel? get currentUser => _currentUser;
  String? get errorMessage => _errorMessage;
  String? get pendingPhone => _pendingPhone;
  bool get isOnboarded => _isOnboarded;
  String? get consentVersion => _consentVersion;
  String? get consentTimestamp => _consentTimestamp;

  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isGuest => _status == AuthStatus.guest;
  bool get isPinLocked => _status == AuthStatus.pinLocked;
  bool get isOtpPending => _status == AuthStatus.otpPending;
  bool get isLoading => _status == AuthStatus.loading;
  bool get hasActiveAccess => isAuthenticated || isGuest;
  bool get isPrivileged => _currentUser != null && _currentUser!.isPrivileged;

  void setErrorMessage(String? msg) {
    _errorMessage = msg;
    notifyListeners();
  }

  void setPendingPhone(String? phone) {
    _pendingPhone = phone;
    notifyListeners();
  }

  bool _didInitialize = false;

  Future<void> initialize() async {
    if (_didInitialize) return;
    _didInitialize = true;
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    unawaited(authService.processQueuedSosAlerts());

    try {
      final onboardedStr = await authService.storage.getString(AuthService.keyOnboarded);
      _isOnboarded = onboardedStr == 'true';
      final consentStr = await authService.storage.getString(AuthService.keyPrivacyConsent);
      if (consentStr != null && consentStr.isNotEmpty) {
        try {
          final decoded = jsonDecode(consentStr);
          if (decoded is Map<String, dynamic>) {
            _consentVersion = decoded['version'] as String?;
            _consentTimestamp = decoded['timestamp'] as String?;
          }
        } catch (_) {}
      }
      final hasPin = await authService.hasStoredPin();
      final user = await authService.getProfile();

      if (user != null) {
        _currentUser = user;
        if (hasPin) {
          _status = AuthStatus.pinLocked;
        } else {
          _status = AuthStatus.authenticated;
        }
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }

  void enterEmergencyBypass() {
    _currentUser = UserModel.guest();
    _status = AuthStatus.guest;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> login(String emailOrPhone, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await authService.login(emailOrPhone, password);
      if (result.success && result.user != null) {
        _currentUser = result.user;
        final hasPin = await authService.hasStoredPin();
        if (hasPin) {
          _status = AuthStatus.pinLocked;
        } else {
          _status = AuthStatus.authenticated;
        }
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.unauthenticated;
        _errorMessage = result.message ?? 'Invalid credentials. Please check your details.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String emergencyContactPhone,
    String? emergencyContactName,
    String? pin,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    _pendingPhone = phone;
    notifyListeners();

    try {
      final result = await authService.register(
        name: name,
        email: email,
        phone: phone,
        password: password,
        emergencyContactPhone: emergencyContactPhone,
        emergencyContactName: emergencyContactName,
        pin: pin,
      );

      if (result.success) {
        if (pin != null && pin.isNotEmpty) {
          await authService.setPin(pin);
        }
        _currentUser = result.user;
        _status = AuthStatus.otpPending;
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.unauthenticated;
        _errorMessage = result.message ?? 'Registration failed. Please try again.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> sendOtp(String phone) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    _pendingPhone = phone;
    notifyListeners();

    try {
      final result = await authService.sendOtp(phone);
      if (result.success) {
        _status = AuthStatus.otpPending;
        notifyListeners();
        return true;
      } else {
        _errorMessage = result.message ?? 'Failed to send OTP.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyOtp(String code) async {
    final phone = _pendingPhone;
    if (phone == null || phone.isEmpty) {
      _errorMessage = 'No phone number available for OTP verification.';
      notifyListeners();
      return false;
    }

    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await authService.verifyOtp(phone: phone, code: code);
      if (result.success && result.user != null) {
        _currentUser = result.user;
        _status = AuthStatus.authenticated;
        _pendingPhone = null;
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.otpPending;
        _errorMessage = result.message ?? 'Invalid or expired OTP code.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = AuthStatus.otpPending;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlockPin(String pin) async {
    _errorMessage = null;
    final valid = await authService.verifyPin(pin);
    if (valid) {
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } else {
      _errorMessage = 'Incorrect PIN code.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> unlockBiometrics() async {
    _errorMessage = null;
    final valid = await authService.verifyBiometrics();
    if (valid) {
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } else {
      _errorMessage = 'Biometric authentication failed.';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      await authService.logout();
    } catch (_) {}

    _currentUser = null;
    _pendingPhone = null;
    _errorMessage = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> completeOnboarding({String consentVersion = '1.0'}) async {
    final now = DateTime.now().toIso8601String();
    await authService.storage.setString(AuthService.keyOnboarded, 'true');
    await authService.storage.setString(
      AuthService.keyPrivacyConsent,
      '{"version":"$consentVersion","timestamp":"$now"}',
    );
    _isOnboarded = true;
    _consentVersion = consentVersion;
    _consentTimestamp = now;
    notifyListeners();
  }

  Future<bool> deleteAccount({String? pin}) async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      final success = await authService.deleteAccount(pin: pin);
      if (success) {
        _currentUser = null;
        _pendingPhone = null;
        _isOnboarded = false;
        _consentVersion = null;
        _consentTimestamp = null;
        await authService.storage.remove(AuthService.keyOnboarded);
        await authService.storage.remove(AuthService.keyPrivacyConsent);
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return true;
      }
    } catch (_) {}
    _status = AuthStatus.authenticated;
    notifyListeners();
    return false;
  }

  Future<void> clearLocalData() async {
    _status = AuthStatus.loading;
    notifyListeners();
    try {
      await authService.logout();
      await authService.clearActiveSos();
      await authService.clearQueuedSosAlerts();
      await authService.storage.remove(AuthService.keyOnboarded);
      await authService.storage.remove(AuthService.keyPrivacyConsent);
    } catch (_) {}
    _currentUser = null;
    _pendingPhone = null;
    _isOnboarded = false;
    _consentVersion = null;
    _consentTimestamp = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
