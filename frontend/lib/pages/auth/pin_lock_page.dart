import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/auth_state.dart';
import '../../routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';

class PinLockPage extends StatefulWidget {
  const PinLockPage({super.key});

  @override
  State<PinLockPage> createState() => _PinLockPageState();
}

class _PinLockPageState extends State<PinLockPage> with SingleTickerProviderStateMixin {
  String _enteredPin = '';
  int _failedAttempts = 0;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;
  bool _isLockedOut = false;
  String? _errorMessage;

  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -12.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12.0, end: 12.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _startLockoutTimer() {
    setState(() {
      _isLockedOut = true;
      _lockoutSeconds = 60;
      _errorMessage = 'Too many failed attempts. Locked for 60 seconds.';
      _enteredPin = '';
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockoutSeconds <= 1) {
        timer.cancel();
        setState(() {
          _isLockedOut = false;
          _lockoutSeconds = 0;
          _failedAttempts = 0;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _lockoutSeconds--;
          _errorMessage = 'PIN locked. Try again in ${_lockoutSeconds}s';
        });
      }
    });
  }

  void _onKeyPress(String digit) {
    if (_isLockedOut) return;
    if (_enteredPin.length < 4) {
      setState(() {
        _enteredPin += digit;
        _errorMessage = null;
      });
      if (_enteredPin.length == 4) {
        _submitPin();
      }
    }
  }

  void _onBackspace() {
    if (_isLockedOut) return;
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = null;
      });
    }
  }

  /// M1.6b: Forgot-PIN recovery — OTP sent to the registered phone resets the
  /// PIN. On success the user returns here and logs in with the new PIN.
  Future<void> _openForgotPinFlow() async {
    final reset = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101A33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _ForgotPinSheet(),
    );
    if (reset == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'PIN reset successfully. Log in with your new PIN.'),
          backgroundColor: Colors.teal,
        ),
      );
      setState(() {
        _enteredPin = '';
        _errorMessage = null;
      });
    }
  }

  Future<void> _submitPin() async {
    final pin = _enteredPin;
    final authState = AuthState();
    final valid = await authState.unlockPin(pin);

    if (!mounted) return;

    if (valid) {
      if (authState.isAuthenticated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN verified. Access granted.'),
            backgroundColor: Colors.teal,
          ),
        );
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN verified. Please sign in to restore your session.'),
            backgroundColor: Colors.teal,
          ),
        );
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    } else {
      _shakeController.forward(from: 0.0);
      _failedAttempts++;

      if (_failedAttempts >= 5) {
        _startLockoutTimer();
      } else {
        final remaining = 5 - _failedAttempts;
        setState(() {
          _enteredPin = '';
          _errorMessage = 'Incorrect PIN. $remaining ${remaining == 1 ? 'attempt' : 'attempts'} remaining.';
        });
      }
    }
  }

  Widget _buildDot(int index) {
    final isFilled = index < _enteredPin.length;
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isFilled ? AppColors.teal : Colors.transparent,
        border: Border.all(
          color: _errorMessage != null ? AppColors.red : AppColors.teal,
          width: 2,
        ),
        boxShadow: isFilled
            ? [
                BoxShadow(
                  color: AppColors.teal.withValues(alpha: 0.6),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildKeypadButton(String label, {VoidCallback? onTap, IconData? icon}) {
    return Container(
      width: 72,
      height: 72,
      margin: const EdgeInsets.all(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(36),
          onTap: _isLockedOut ? null : onTap,
          splashColor: AppColors.teal.withValues(alpha: 0.3),
          highlightColor: Colors.white.withValues(alpha: 0.1),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 26)
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            // Pulsing Shield Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.teal.withValues(alpha: 0.1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.teal.withValues(alpha: 0.2),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 56,
                color: AppColors.teal,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Enter 4-Digit PIN',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AuthState().isDiscreetMode
                  ? 'System Security Verification'
                  : 'Quick security access for SafeSphere',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 24),

            // 4 Animated Indicator Dots
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) => _buildDot(i)),
              ),
            ),

            const SizedBox(height: 14),

            // Error / Lockout Message
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              const SizedBox(height: 18),

            const Spacer(),

            // Custom Numeric Keypad (0-9, Backspace, Biometric)
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildKeypadButton('1', onTap: () => _onKeyPress('1')),
                    _buildKeypadButton('2', onTap: () => _onKeyPress('2')),
                    _buildKeypadButton('3', onTap: () => _onKeyPress('3')),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildKeypadButton('4', onTap: () => _onKeyPress('4')),
                    _buildKeypadButton('5', onTap: () => _onKeyPress('5')),
                    _buildKeypadButton('6', onTap: () => _onKeyPress('6')),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildKeypadButton('7', onTap: () => _onKeyPress('7')),
                    _buildKeypadButton('8', onTap: () => _onKeyPress('8')),
                    _buildKeypadButton('9', onTap: () => _onKeyPress('9')),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildKeypadButton(
                      '',
                      icon: Icons.fingerprint,
                      onTap: () async {
                        final authState = AuthState();
                        final success = await authState.unlockBiometrics();
                        if (!mounted) return;
                        if (success) {
                          Navigator.pushReplacementNamed(
                            context,
                            authState.isAuthenticated ? AppRoutes.home : AppRoutes.login,
                          );
                        }
                      },
                    ),
                    _buildKeypadButton('0', onTap: () => _onKeyPress('0')),
                    _buildKeypadButton('', icon: Icons.backspace_outlined, onTap: _onBackspace),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Alternative Login ("Use Password Instead")
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.login),
              child: const Text(
                'Use Password Instead',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),

            // M1.6b: Forgot-PIN recovery — OTP to the registered phone
            TextButton(
              onPressed: _openForgotPinFlow,
              child: const Text(
                'Forgot PIN?',
                style: TextStyle(color: AppColors.teal, fontSize: 13),
              ),
            ),

            const SizedBox(height: 10),

            // 🚨 Unconditional Bottom Emergency SOS Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Unconditional emergency bypass
                    AuthState().enterEmergencyBypass();
                    Navigator.pushNamed(context, AppRoutes.emergency);
                  },
                  icon: const Icon(Icons.emergency, color: Colors.white, size: 24),
                  label: const Text(
                    'Emergency SOS / Dial 112',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 6,
                    shadowColor: AppColors.red.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// M1.6b: Forgot-PIN recovery sheet — OTP to the registered phone, then a new
/// PIN. Honest failures surface as inline errors; no fabricated success.
class _ForgotPinSheet extends StatefulWidget {
  const _ForgotPinSheet();

  @override
  State<_ForgotPinSheet> createState() => _ForgotPinSheetState();
}

class _ForgotPinSheetState extends State<_ForgotPinSheet> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  bool _otpSent = false;
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter your registered phone number.');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final res = await AuthService.instance.sendOtp(phone);
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      if (res.success) {
        _otpSent = true;
        _error = null;
      } else {
        _error = 'Could not send the OTP. Check the number and try again.';
      }
    });
  }

  Future<void> _resetPin() async {
    final otp = _otpController.text.trim();
    final newPin = _pinController.text.trim();
    if (otp.isEmpty || newPin.isEmpty) {
      setState(() => _error = 'Enter the OTP and your new PIN.');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final ok = await AuthService.instance.resetPin(
      phone: _phoneController.text.trim(),
      otp: otp,
      newPin: newPin,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (ok) {
      // Backend revoked all sessions during the reset — wipe the dead local
      // tokens and install the NEW PIN so the keypad verifies what the user
      // just chose (previously the old local PIN still unlocked).
      await AuthService.instance.applyPinReset(newPin);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error =
            'Reset failed. Check the OTP and PIN (4-6 digits), then retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reset your PIN',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'We will email a 6-digit verification code to the address on your account.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            enabled: !_otpSent,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Registered mobile number',
              prefixText: '+91 ',
              counterText: '',
              labelStyle: TextStyle(color: Colors.white60),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.teal),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isBusy ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.black,
              ),
              child: Text(_otpSent ? 'OTP sent ✓' : 'Send OTP'),
            ),
          ),
          if (_otpSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, letterSpacing: 4),
              decoration: const InputDecoration(
                labelText: '6-digit OTP',
                counterText: '',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.teal),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              style: const TextStyle(color: Colors.white, letterSpacing: 4),
              decoration: const InputDecoration(
                labelText: 'New PIN (4-6 digits)',
                counterText: '',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.teal),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isBusy ? null : _resetPin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.lock_reset),
                label: const Text('Reset PIN'),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
