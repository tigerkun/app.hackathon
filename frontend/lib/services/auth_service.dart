import 'dart:async';
import '../models/user_model.dart';

/// Manages authentication state, secure session storage, PIN lock, and biometrics
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    _initDemoUser();
  }

  UserModel? _currentUser;
  String? _sessionToken;
  String? _storedPin = "1234";
  bool _isPinLocked = false;
  bool _biometricsRegistered = true;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isPinLocked => _isPinLocked;
  bool get biometricsEnabled => _currentUser?.biometricsEnabled ?? false;
  bool get hasPin => _storedPin != null && _storedPin!.isNotEmpty;

  void _initDemoUser() {
    _currentUser = const UserModel(
      id: "usr_demo_001",
      email: "demo@safesphere.org",
      name: "Jane SafeSphere",
      phone: "+91 9876543210",
      hasPin: true,
      biometricsEnabled: true,
      emergencyContacts: [
        EmergencyContact(name: "National Emergency", phone: "112", relationship: "Emergency"),
        EmergencyContact(name: "Mom", phone: "+91 9876500001", relationship: "Mother"),
      ],
    );
    _sessionToken = "jwt_demo_token_safesphere_2026";
  }

  /// Authenticate with email or phone and password
  Future<bool> login(String emailOrPhone, String password) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (emailOrPhone.trim().isEmpty || password.trim().isEmpty) {
      return false;
    }
    // Demo authentication check
    _currentUser = UserModel(
      id: "usr_${DateTime.now().millisecondsSinceEpoch}",
      email: emailOrPhone.contains('@') ? emailOrPhone : '$emailOrPhone@safesphere.org',
      name: emailOrPhone.split('@').first,
      phone: emailOrPhone.contains('@') ? "+91 9876543210" : emailOrPhone,
      hasPin: _storedPin != null,
      biometricsEnabled: _biometricsRegistered,
      emergencyContacts: const [
        EmergencyContact(name: "National Emergency", phone: "112", relationship: "Emergency"),
      ],
    );
    _sessionToken = "jwt_token_${DateTime.now().millisecondsSinceEpoch}";
    _isPinLocked = false;
    return true;
  }

  /// Quick login or unlock with 4-digit PIN
  Future<bool> loginWithPin(String pin) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (_storedPin == null || _storedPin == pin) {
      _isPinLocked = false;
      return true;
    }
    return false;
  }

  /// Biometric authentication (FaceID / Fingerprint)
  Future<bool> loginWithBiometrics() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (_biometricsRegistered) {
      _isPinLocked = false;
      return true;
    }
    return false;
  }

  /// Register a new citizen account
  Future<bool> signup({
    required String name,
    required String email,
    required String phone,
    required String password,
    String? pin,
    List<EmergencyContact>? emergencyContacts,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (name.trim().isEmpty || email.trim().isEmpty || password.trim().isEmpty) {
      return false;
    }
    if (pin != null && pin.isNotEmpty) {
      _storedPin = pin;
    }
    _currentUser = UserModel(
      id: "usr_${DateTime.now().millisecondsSinceEpoch}",
      email: email.trim(),
      name: name.trim(),
      phone: phone.trim(),
      hasPin: pin != null && pin.isNotEmpty,
      biometricsEnabled: false,
      emergencyContacts: emergencyContacts ?? const [
        EmergencyContact(name: "National Emergency", phone: "112", relationship: "Emergency"),
      ],
    );
    _sessionToken = "jwt_token_${DateTime.now().millisecondsSinceEpoch}";
    _isPinLocked = false;
    return true;
  }

  /// Set or update the Safety PIN
  void setPin(String newPin) {
    _storedPin = newPin;
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(hasPin: true);
    }
  }

  /// Lock current session
  void lockSession() {
    _isPinLocked = true;
  }

  /// Toggle Biometrics
  void setBiometricsEnabled(bool enabled) {
    _biometricsRegistered = enabled;
    if (_currentUser != null) {
      _currentUser = _currentUser!.copyWith(biometricsEnabled: enabled);
    }
  }

  /// Log out and reset session
  Future<void> logout() async {
    _currentUser = null;
    _sessionToken = null;
    _isPinLocked = false;
  }
}
