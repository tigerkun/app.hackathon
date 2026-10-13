import 'package:flutter/material.dart';
import '../../data/auth_state.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_container.dart';

class LoginPage extends StatefulWidget {
  final String? redirectRoute;

  const LoginPage({
    super.key,
    this.redirectRoute,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final authState = AuthState();
    final success = await authState.login(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Welcome back to SafeSphere!'),
          backgroundColor: Colors.teal,
        ),
      );
      final dest = widget.redirectRoute ?? AppRoutes.home;
      Navigator.pushReplacementNamed(context, dest);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authState.errorMessage ?? 'Invalid login credentials.'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<void> _handleBiometricAuth() async {
    setState(() => _isLoading = true);
    final authState = AuthState();
    final success = await authState.unlockBiometrics();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric authentication verified.'),
          backgroundColor: Colors.teal,
        ),
      );
      final dest = widget.redirectRoute ?? AppRoutes.home;
      Navigator.pushReplacementNamed(context, dest);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric verification failed.'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  void _handleEmergencyBypass() {
    final authState = AuthState();
    authState.enterEmergencyBypass();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency Bypass Active. Immediate Citizen Safety Enabled.'),
        backgroundColor: AppColors.amber,
      ),
    );
    Navigator.pushNamed(context, AppRoutes.emergency);
  }

  void _showSmsOtpDialog() {
    final phoneCtrl = TextEditingController(text: _emailController.text.contains('@') ? '' : _emailController.text);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.bgDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.sms_outlined, color: AppColors.teal),
            SizedBox(width: 8),
            Text('Login with SMS OTP', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your 10-digit registered phone number to receive a one-time verification code.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '+91 9876543210',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.phone, color: AppColors.teal, size: 20),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal, foregroundColor: Colors.black87),
            onPressed: () async {
              final phone = phoneCtrl.text.trim();
              if (phone.length < 8) return;
              Navigator.pop(dialogCtx);
              final authState = AuthState();
              await authState.sendOtp(phone);
              if (!mounted) return;
              Navigator.pushNamed(context, AppRoutes.otp, arguments: phone);
            },
            child: const Text('Send OTP'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Brand Logo & Header
                  const Center(
                    child: Icon(
                      Icons.shield_outlined,
                      size: 64,
                      color: AppColors.teal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'SafeSphere',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: Text(
                      'Citizen Safety & Incident Intelligence',
                      style: TextStyle(fontSize: 13, color: Colors.white60),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 🚨 High-Visibility Emergency Bypass Button
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE53935), Color(0xFFFF6F00)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.red.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _handleEmergencyBypass,
                      icon: const Icon(Icons.emergency_outlined, color: Colors.white, size: 22),
                      label: const Text(
                        'QUICK EMERGENCY BYPASS (SOS)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Login Form Card
                  GlassContainer(
                    blur: 16,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Email / Phone Input
                          TextFormField(
                            controller: _emailController,
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: 'Email or Mobile Number',
                              labelStyle: const TextStyle(color: Colors.white60),
                              prefixIcon: const Icon(Icons.email_outlined, color: AppColors.teal),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Email or phone number is required';
                              }
                              final input = val.trim();
                              final isEmail = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(input);
                              final isPhone = RegExp(r'^[+0-9\s-]{8,}$').hasMatch(input);
                              if (!isEmail && !isPhone) {
                                return 'Enter a valid email address or phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password Input
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: Colors.white60),
                              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.teal),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                  color: Colors.white54,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) {
                                return 'Password is required';
                              }
                              if (val.trim().length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          // Sign In Button
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
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
                                      'Sign In',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Alternative Quick Auth Methods: Biometric, PIN, SMS OTP
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Biometric Auth Button
                      OutlinedButton.icon(
                        onPressed: _handleBiometricAuth,
                        icon: const Icon(Icons.fingerprint, color: AppColors.teal, size: 20),
                        label: const Text('Biometric', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      // PIN Fast Login Button
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.pinLock),
                        icon: const Icon(Icons.dialpad, color: AppColors.teal, size: 20),
                        label: const Text('4-Digit PIN', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      // SMS OTP Button
                      OutlinedButton.icon(
                        onPressed: _showSmsOtpDialog,
                        icon: const Icon(Icons.sms_outlined, color: AppColors.teal, size: 20),
                        label: const Text('SMS OTP', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Register Now Link
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pushNamed(context, AppRoutes.register),
                      child: const Text.rich(
                        TextSpan(
                          text: "Don't have an account? ",
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                          children: [
                            TextSpan(
                              text: 'Register Now',
                              style: TextStyle(
                                color: AppColors.teal,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
