import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class AuthPinPage extends StatefulWidget {
  const AuthPinPage({super.key});

  @override
  State<AuthPinPage> createState() => _AuthPinPageState();
}

class _AuthPinPageState extends State<AuthPinPage> {
  String _enteredPin = "";
  bool _isError = false;

  void _onDigitPress(String digit) {
    if (_enteredPin.length < 4) {
      setState(() {
        _isError = false;
        _enteredPin += digit;
      });

      if (_enteredPin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _isError = false;
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _verifyPin() async {
    final success = await AuthService().loginWithPin(_enteredPin);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("PIN verified successfully"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      setState(() {
        _isError = true;
        _enteredPin = "";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Incorrect PIN. Please re-enter or sign in with credentials."),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<void> _callEmergency() async {
    final uri = Uri.parse("tel:112");
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const Spacer(),

            // Lock Icon
            Icon(
              _isError ? Icons.lock_clock : Icons.lock_outline,
              size: 48,
              color: _isError ? AppColors.red : AppColors.teal,
            ),
            const SizedBox(height: 16),
            const Text(
              "Enter Safety PIN",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isError ? "Incorrect PIN entered. Try again." : "Enter your 4-digit security PIN to unlock",
              style: TextStyle(
                fontSize: 14,
                color: _isError ? AppColors.red : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),

            // PIN Dots Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final isFilled = index < _enteredPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled
                        ? (_isError ? AppColors.red : AppColors.teal)
                        : Colors.transparent,
                    border: Border.all(
                      color: _isError
                          ? AppColors.red
                          : (isFilled ? AppColors.teal : AppColors.textSecondary),
                      width: 2,
                    ),
                  ),
                );
              }),
            ),
            const Spacer(),

            // Numeric Keypad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  _buildKeypadRow(["1", "2", "3"]),
                  const SizedBox(height: 16),
                  _buildKeypadRow(["4", "5", "6"]),
                  const SizedBox(height: 16),
                  _buildKeypadRow(["7", "8", "9"]),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Emergency 112 button
                      InkWell(
                        onTap: _callEmergency,
                        borderRadius: BorderRadius.circular(36),
                        child: Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.red.withValues(alpha: 0.15),
                            border: Border.all(color: AppColors.red.withValues(alpha: 0.5)),
                          ),
                          child: const Text(
                            "112",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.red),
                          ),
                        ),
                      ),
                      _buildKeypadButton("0"),
                      // Backspace button
                      InkWell(
                        onTap: _onBackspace,
                        borderRadius: BorderRadius.circular(36),
                        child: Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          child: const Icon(Icons.backspace_outlined, color: AppColors.textSecondary, size: 24),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: digits.map((d) => _buildKeypadButton(d)).toList(),
    );
  }

  Widget _buildKeypadButton(String digit) {
    return InkWell(
      onTap: () => _onDigitPress(digit),
      borderRadius: BorderRadius.circular(36),
      child: Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          digit,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
