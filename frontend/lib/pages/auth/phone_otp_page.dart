import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/auth_state.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_container.dart';

class PhoneOtpPage extends StatefulWidget {
  final String? phone;

  const PhoneOtpPage({
    super.key,
    this.phone,
  });

  @override
  State<PhoneOtpPage> createState() => _PhoneOtpPageState();
}

class _PhoneOtpPageState extends State<PhoneOtpPage> {
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  Timer? _countdownTimer;
  int _secondsRemaining = 60;
  bool _canResend = false;
  bool _isLoading = false;
  String? _errorBanner;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final fn in _focusNodes) {
      fn.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() {
      _secondsRemaining = 60;
      _canResend = false;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
          _canResend = true;
        });
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  String _formatTimer() {
    final mins = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final secs = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  String _maskPhone(String raw) {
    if (raw.length <= 4) return raw;
    final last4 = raw.substring(raw.length - 4);
    final prefix = raw.length > 7 ? raw.substring(0, 3) : '';
    return '$prefix******$last4';
  }

  String get _otpCode {
    return _controllers.map((c) => c.text).join();
  }

  Future<void> _handleVerify() async {
    final code = _otpCode.trim();
    if (code.length != 6) {
      setState(() => _errorBanner = 'Please enter all 6 digits of the verification code.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorBanner = null;
    });

    final authState = AuthState();
    final success = await authState.verifyOtp(code);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number successfully verified! Citizen security active.'),
          backgroundColor: Colors.teal,
        ),
      );
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (route) => false);
    } else {
      setState(() {
        _errorBanner = authState.errorMessage ?? 'Invalid OTP code. Please check and try again.';
      });
    }
  }

  Future<void> _handleResend() async {
    if (!_canResend) return;

    final phone = widget.phone ?? AuthState().pendingPhone ?? '';
    if (phone.isEmpty) {
      setState(() => _errorBanner = 'No mobile phone registered for OTP resend.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorBanner = null;
    });

    final authState = AuthState();
    final success = await authState.sendOtp(phone);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('New verification code sent to ${_maskPhone(phone)}.'),
          backgroundColor: Colors.teal,
        ),
      );
      // Clear inputs
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();
      _startCountdown();
    } else {
      setState(() {
        _errorBanner = authState.errorMessage ?? 'Failed to resend code. Please try again.';
      });
    }
  }

  Widget _buildOtpCell(int index) {
    return SizedBox(
      width: 44,
      height: 54,
      child: GlassContainer(
        blur: 12,
        borderColor: _controllers[index].text.isNotEmpty ? AppColors.teal : AppColors.glassBorder,
        child: Center(
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (value) {
              if (value.isNotEmpty) {
                if (index < 5) {
                  _focusNodes[index + 1].requestFocus();
                } else {
                  _focusNodes[index].unfocus();
                  _handleVerify();
                }
              } else {
                if (index > 0) {
                  _focusNodes[index - 1].requestFocus();
                }
              }
              setState(() {});
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePhone = widget.phone ?? AuthState().pendingPhone ?? '+91 9876543210';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Phone Verification', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Icon(
                  Icons.mark_email_read_outlined,
                  size: 64,
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Verify Your Number',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Code sent via SMS to ${_maskPhone(activePhone)}',
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ),
              const SizedBox(height: 24),

              // Error Banner (if present)
              if (_errorBanner != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.red.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorBanner!,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // 6 Discrete Glassmorphic OTP Cells
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _buildOtpCell(i)),
              ),
              const SizedBox(height: 28),

              // Verify & Continue Action Button
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleVerify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                        )
                      : const Text(
                          'Verify & Continue',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
              const SizedBox(height: 24),

              // Dynamic Countdown Resend Timer
              Center(
                child: _canResend
                    ? TextButton.icon(
                        onPressed: _isLoading ? null : _handleResend,
                        icon: const Icon(Icons.refresh, color: AppColors.teal, size: 18),
                        label: const Text(
                          'Resend SMS Code',
                          style: TextStyle(
                            color: AppColors.teal,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : Text(
                        'Resend code in ${_formatTimer()}',
                        style: const TextStyle(color: Colors.white54, fontSize: 13),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
