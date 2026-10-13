import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/auth_state.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_container.dart';

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

  Future<void> _submitPin() async {
    final pin = _enteredPin;
    final authState = AuthState();
    final valid = await authState.unlockPin(pin);

    if (!mounted) return;

    if (valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN verified. Access granted.'),
          backgroundColor: Colors.teal,
        ),
      );
      Navigator.pushReplacementNamed(context, AppRoutes.home);
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
            const Text(
              'Quick security access for SafeSphere',
              style: TextStyle(color: Colors.white60, fontSize: 13),
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
                          Navigator.pushReplacementNamed(context, AppRoutes.home);
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
