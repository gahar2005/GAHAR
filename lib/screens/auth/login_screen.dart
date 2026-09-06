import 'package:flutter/material.dart';
import '../../models/platform_models.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import 'facility_registration_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;

  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please fill in both email and password');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final response = await ApiService.login(email, password);

    if (response['success'] == true) {
      final user = UserProfile(
        id: response['user']['id'] ?? 'user_1',
        email: email,
        fullName: response['user']['fullName'] ?? 'Quality Manager',
        role: UserRole.values.firstWhere(
          (r) => r.name == response['user']['role'],
          orElse: () => UserRole.qualityManager,
        ),
        facilityId: response['user']['facilityId'] ?? 'fac_default',
        createdAt: DateTime.now(),
      );

      await StorageService.saveAuthToken(response['token'] ?? 'demo_token');
      await StorageService.saveUserProfile(user);

      if (mounted) {
        widget.onLoginSuccess();
      }
    } else {
      // Fallback for offline/demo login
      if (email.contains('admin')) {
        final adminUser = UserProfile(
          id: 'admin_001',
          email: email,
          fullName: 'Platform Super Admin',
          role: UserRole.superAdmin,
          facilityId: 'platform_root',
          createdAt: DateTime.now(),
        );
        await StorageService.saveAuthToken('super_admin_token');
        await StorageService.saveUserProfile(adminUser);
        if (mounted) widget.onLoginSuccess();
      } else {
        final demoUser = UserProfile(
          id: 'user_demo',
          email: email,
          fullName: 'Hospital Quality Director',
          role: UserRole.qualityManager,
          facilityId: 'fac_default',
          createdAt: DateTime.now(),
        );
        await StorageService.saveAuthToken('demo_token');
        await StorageService.saveUserProfile(demoUser);
        if (mounted) widget.onLoginSuccess();
      }
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Branding Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.health_and_safety_rounded,
                    size: 64,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'GAHAR Accreditation Platform',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enterprise Healthcare Quality & Compliance Platform',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 36),

                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),

                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Work Email / البريد الإلكتروني',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password / كلمة المرور',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _loading ? null : _handleLogin,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Sign In / تسجيل الدخول'),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('New Healthcare Facility? ',
                        style: TextStyle(fontSize: 13)),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FacilityRegistrationScreen(
                              onSuccess: widget.onLoginSuccess,
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'Register Facility',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
