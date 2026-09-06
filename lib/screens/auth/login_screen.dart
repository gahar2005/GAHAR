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
  bool _isSuperAdminMode = false;
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

    Map<String, dynamic> response;
    if (_isSuperAdminMode || email.toLowerCase() == 'admin@accredigo.eg') {
      response = await ApiService.superAdminLogin(email, password);
    } else {
      response = await ApiService.login(email, password);
    }

    if (response['success'] == true) {
      final userData = response['user'] ?? {};
      final roleStr = userData['role'] ?? (_isSuperAdminMode ? 'SUPER_ADMIN' : 'FACILITY_ADMIN');
      
      final user = UserProfile(
        id: userData['id'] ?? 'user_1',
        email: email,
        fullName: userData['fullName'] ?? (_isSuperAdminMode ? 'Platform Super Admin' : 'Facility Administrator'),
        role: UserRole.values.firstWhere(
          (r) => r.name == roleStr,
          orElse: () => _isSuperAdminMode ? UserRole.superAdmin : UserRole.facilityAdmin,
        ),
        facilityId: userData['facilityId'] ?? 'fac_01000000-0000-0000-0000-000000000001',
        createdAt: DateTime.now(),
      );

      await StorageService.saveAuthToken(response['token'] ?? '');
      await StorageService.saveUserProfile(user);

      if (mounted) {
        setState(() => _loading = false);
        widget.onLoginSuccess();
      }
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = response['message'] ?? 'Login failed. Please check your credentials.';
          _loading = false;
        });
      }
    }
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
                    color: _isSuperAdminMode 
                        ? AppColors.secondary.withOpacity(0.15)
                        : AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isSuperAdminMode ? Icons.admin_panel_settings : Icons.health_and_safety_rounded,
                    size: 64,
                    color: _isSuperAdminMode ? AppColors.secondary : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isSuperAdminMode ? 'Super Admin Portal' : 'AccrediGo Platform',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isSuperAdminMode 
                      ? 'Platform Administration & Facility Approvals' 
                      : 'Enterprise Healthcare Quality & Compliance Platform',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 28),

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
                  decoration: InputDecoration(
                    labelText: _isSuperAdminMode ? 'Super Admin Email' : 'Work Email / البريد الإلكتروني',
                    prefixIcon: const Icon(Icons.email_outlined),
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSuperAdminMode ? AppColors.secondary : AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isSuperAdminMode ? 'Sign In as Super Admin' : 'Sign In / تسجيل الدخول'),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isSuperAdminMode = !_isSuperAdminMode;
                          _emailController.clear();
                          _passwordController.clear();
                          _errorMessage = null;
                        });
                      },
                      child: Text(
                        _isSuperAdminMode ? '← Facility Sign In' : 'Super Admin Login',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isSuperAdminMode ? AppColors.primary : AppColors.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (!_isSuperAdminMode)
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
