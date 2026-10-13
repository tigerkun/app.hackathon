import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/auth_state.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_container.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _emergencyPhoneController = TextEditingController();
  final TextEditingController _emergencyNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _enablePinSetup = false;
  bool _isLoading = false;
  String _selectedRelationship = 'Family';

  final List<String> _relationships = ['Family', 'Parent', 'Spouse', 'Sibling', 'Friend', 'Guardian'];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _dialEmergency() async {
    final uri = Uri.parse('tel:112');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (!mounted) return;
        Navigator.pushNamed(context, AppRoutes.emergency);
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pushNamed(context, AppRoutes.emergency);
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final authState = AuthState();

    final pinVal = _enablePinSetup && _pinController.text.trim().isNotEmpty
        ? _pinController.text.trim()
        : null;

    final phone = _phoneController.text.trim();

    final success = await authState.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim().isNotEmpty
          ? _emailController.text.trim()
          : '$phone@safesphere.org',
      phone: phone,
      password: _passwordController.text,
      emergencyContactPhone: _emergencyPhoneController.text.trim(),
      emergencyContactName: '${_emergencyNameController.text.trim()} ($_selectedRelationship)',
      pin: pinVal,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      // Automatically send OTP and navigate to PhoneOtpPage
      await authState.sendOtp(phone);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Account created. Verification code sent to $phone.'),
          backgroundColor: Colors.teal,
        ),
      );
      Navigator.pushNamed(context, AppRoutes.otp, arguments: phone);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authState.errorMessage ?? 'Registration failed. Please check inputs.'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Citizen Registration',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone_in_talk, color: AppColors.red),
            tooltip: 'Emergency SOS 112',
            onPressed: _dialEmergency,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Join SafeSphere',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Enroll in the community safety and rapid emergency network',
                  style: TextStyle(fontSize: 13, color: Colors.white60),
                ),
                const SizedBox(height: 16),

                GlassContainer(
                  blur: 16,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Full Name
                        TextFormField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Full Name *',
                            labelStyle: const TextStyle(color: Colors.white60),
                            prefixIcon: const Icon(Icons.person_outline, color: AppColors.teal),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().length < 2) {
                              return 'Full name must be at least 2 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Mobile Phone Number
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Mobile Phone Number *',
                            labelStyle: const TextStyle(color: Colors.white60),
                            prefixIcon: const Icon(Icons.phone_android_outlined, color: AppColors.teal),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().length < 8) {
                              return 'Valid mobile phone number is required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Email (Optional)
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Email Address (Optional)',
                            labelStyle: const TextStyle(color: Colors.white60),
                            prefixIcon: const Icon(Icons.email_outlined, color: AppColors.teal),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Emergency Contact Section Header
                        const Row(
                          children: [
                            Icon(Icons.shield, color: AppColors.amber, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Primary Emergency Contact (Mandatory)',
                              style: TextStyle(
                                color: AppColors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Emergency Contact Phone
                        TextFormField(
                          controller: _emergencyPhoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Emergency Contact Phone *',
                            labelStyle: const TextStyle(color: Colors.white60),
                            prefixIcon: const Icon(Icons.contact_phone_outlined, color: AppColors.amber),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().length < 8) {
                              return 'Emergency contact phone is mandatory for citizen safety';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Emergency Contact Name & Relationship Row
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _emergencyNameController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Contact Name *',
                                  labelStyle: const TextStyle(color: Colors.white60),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Contact name required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedRelationship,
                                dropdownColor: AppColors.bgDark,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'Relation',
                                  labelStyle: const TextStyle(color: Colors.white60),
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.05),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                items: _relationships.map((rel) {
                                  return DropdownMenuItem(value: rel, child: Text(rel));
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedRelationship = val);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Password *',
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
                            if (val == null || val.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Confirm Password Field
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Confirm Password *',
                            labelStyle: const TextStyle(color: Colors.white60),
                            prefixIcon: const Icon(Icons.lock_clock_outlined, color: AppColors.teal),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: Colors.white54,
                              ),
                              onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          validator: (val) {
                            if (val != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Optional 4-Digit PIN Enrollment
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Setup 4-digit PIN for rapid unlock',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          value: _enablePinSetup,
                          activeColor: AppColors.teal,
                          checkColor: Colors.black,
                          onChanged: (val) => setState(() => _enablePinSetup = val ?? false),
                        ),

                        if (_enablePinSetup) ...[
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _pinController,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            style: const TextStyle(color: Colors.white, letterSpacing: 4),
                            decoration: InputDecoration(
                              labelText: '4-Digit PIN',
                              counterText: '',
                              labelStyle: const TextStyle(color: Colors.white60),
                              prefixIcon: const Icon(Icons.dialpad, color: AppColors.teal),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            validator: (val) {
                              if (_enablePinSetup && (val == null || val.length != 4)) {
                                return 'PIN must be exactly 4 digits';
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 18),

                        // Register Button
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleRegister,
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
                                    'Register & Verify Phone',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Back to Sign In
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.login),
                    child: const Text.rich(
                      TextSpan(
                        text: 'Already registered? ',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                        children: [
                          TextSpan(
                            text: 'Sign In',
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
    );
  }
}
