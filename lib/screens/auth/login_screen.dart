import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../models/hospital_profile.dart';
import '../../models/platform_models.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../admin/super_admin_screen.dart';
import '../../main.dart';
import 'facility_registration_screen.dart';

enum AuthViewMode {
  options,
  facilityLogin,
  superAdminLogin,
}

class LoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSuccess;

  const LoginScreen({super.key, this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  AuthViewMode _currentMode = AuthViewMode.options;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  void _switchMode(AuthViewMode mode) {
    setState(() {
      _currentMode = mode;
      _emailController.clear();
      _passwordController.clear();
      _errorMessage = null;
      _obscurePassword = true;
    });
  }

  Future<void> _handleLogin({required bool isSuperAdmin}) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter both email and password.');
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _errorMessage = 'Please enter a valid email address.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final isSuperAdminEmail = isSuperAdmin ||
          email.toLowerCase() == 'superadmin@gahar.gov.eg' ||
          email.toLowerCase() == 'admin@accredigo.eg' ||
          email.toLowerCase() == 'admin@gahar-platform.eg' ||
          email.toLowerCase() == 'gahar2005@gmail.com' ||
          email.toLowerCase().contains('superadmin');

      Map<String, dynamic> response;
      if (isSuperAdminEmail) {
        response = await ApiService.superAdminLogin(email, password);
      } else {
        response = await ApiService.login(email, password);
      }

      if (response['success'] == true) {
        final token = response['token'] as String? ?? '';
        final userData = response['user'] as Map<String, dynamic>? ?? {};
        final roleStr = userData['role'] ?? (isSuperAdminEmail ? 'SUPER_ADMIN' : 'FACILITY_ADMIN');
        final role = UserRoleExt.fromString(roleStr);

        final user = UserProfile(
          id: userData['id'] ?? (isSuperAdminEmail ? 'usr_superadmin_0001' : 'usr_facility_0001'),
          email: email,
          fullName: userData['fullName'] ?? (isSuperAdminEmail ? 'Platform Super Admin' : 'Facility Administrator'),
          role: role,
          facilityId: userData['facilityId'] ?? (isSuperAdminEmail ? '' : 'fac_01000000-0000-0000-0000-000000000001'),
          createdAt: DateTime.now(),
        );

        await StorageService.saveAuthToken(token);
        await StorageService.saveUserProfile(user);

        if (response['facility'] != null) {
          final fac = response['facility'] as Map<String, dynamic>;
          final hospProfile = HospitalProfile(
            name: fac['name'] ?? 'Healthcare Facility',
            type: 'Hospital',
            capacity: '100 beds',
            departments: const ['Emergency', 'ICU', 'Surgery', 'Infection Control'],
            owner: user.fullName,
          );
          await StorageService.saveHospitalProfile(hospProfile);
        }

        if (mounted) {
          setState(() => _loading = false);
          widget.onLoginSuccess?.call();

          if (role == UserRole.superAdmin) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (ctx) => SuperAdminScreen(
                  onLogout: () {
                    Navigator.of(ctx).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const SplashView()),
                      (route) => false,
                    );
                  },
                ),
              ),
              (route) => false,
            );
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (ctx) => MainNavigationShell(
                  onThemeToggle: () => MyApp.of(ctx)?.toggleTheme(),
                  isDark: MyApp.of(ctx)?.isDark ?? true,
                ),
              ),
              (route) => false,
            );
          }
        }
      } else {
        final errorMsg = response['message'] as String? ?? 'Login failed. Please verify your credentials.';
        if (mounted) {
          setState(() {
            _errorMessage = errorMsg;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Network connection error: Unable to connect to server.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF061124), // Midnight Sapphire
              Color(0xFF0B1F3D), // Deep Royal Navy
              Color(0xFF07142A), // Logo Slate Blue
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBrandingHeader(),
                    const SizedBox(height: 32),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _buildCurrentContent(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandingHeader() {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'GAHAR',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 4.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Healthcare Accreditation & Quality Platform',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: const Color(0xFF94A3B8).withValues(alpha: 0.9),
            letterSpacing: 0.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentContent() {
    switch (_currentMode) {
      case AuthViewMode.options:
        return _buildOptionsView();
      case AuthViewMode.facilityLogin:
        return _buildLoginForm(isSuperAdmin: false);
      case AuthViewMode.superAdminLogin:
        return _buildLoginForm(isSuperAdmin: true);
    }
  }

  Widget _buildOptionsView() {
    return Column(
      key: const ValueKey('options_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Select an option to continue',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),

        // Option 1: Existing Account
        _buildOptionCard(
          title: 'Sign In with Existing Account',
          subtitle: 'Log in to your accredited healthcare facility workspace',
          badgeText: 'Active Facility',
          badgeColor: const Color(0xFF2563EB),
          icon: Icons.login_rounded,
          iconColor: const Color(0xFF38BDF8),
          borderColor: const Color(0xFF1E3A8A).withValues(alpha: 0.5),
          onTap: () => _switchMode(AuthViewMode.facilityLogin),
        ),
        const SizedBox(height: 14),

        // Option 2: First-Time Registration
        _buildOptionCard(
          title: 'Register for the First Time',
          subtitle: 'New facility onboarding & accreditation plan subscription',
          badgeText: 'New Facility',
          badgeColor: const Color(0xFF059669),
          icon: Icons.app_registration_rounded,
          iconColor: const Color(0xFF34D399),
          borderColor: const Color(0xFF047857).withValues(alpha: 0.5),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FacilityRegistrationScreen(
                  onSuccess: () => widget.onLoginSuccess?.call(),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),

        // Option 3: Super Admin Portal
        _buildOptionCard(
          title: 'Sign In as Administrator',
          subtitle: 'Platform oversight, facility approvals & audit governance',
          badgeText: 'Super Admin',
          badgeColor: const Color(0xFFD97706),
          icon: Icons.admin_panel_settings_rounded,
          iconColor: const Color(0xFFFBBF24),
          borderColor: const Color(0xFFB45309).withValues(alpha: 0.5),
          onTap: () => _switchMode(AuthViewMode.superAdminLogin),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton.icon(
            onPressed: () => _showServerConfigDialog(context),
            icon: const Icon(Icons.dns_rounded, size: 14, color: Color(0xFF64748B)),
            label: Text(
              'Server: ${AppConfig.baseUrl}',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: iconColor.withValues(alpha: 0.15),
        highlightColor: iconColor.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0D223F).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: iconColor, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              color: badgeColor.withValues(alpha: 0.95),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFF64748B),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm({required bool isSuperAdmin}) {
    final primaryAccent = isSuperAdmin ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);

    return Container(
      key: ValueKey(isSuperAdmin ? 'admin_login_form' : 'facility_login_form'),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0D223F).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryAccent.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header inside card
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                tooltip: 'Back to Options',
                onPressed: () => _switchMode(AuthViewMode.options),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSuperAdmin ? 'Super Admin Portal' : 'Facility Sign In',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      isSuperAdmin
                          ? 'Platform governance & verification'
                          : 'Sign in to your facility dashboard',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.dns_rounded, color: Colors.white54, size: 20),
                tooltip: 'Configure Server IP',
                onPressed: () => _showServerConfigDialog(context),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Error Message Box
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                      ),
                      icon: const Icon(Icons.dns_rounded, size: 14, color: Color(0xFFFBBF24)),
                      label: const Text(
                        'تعديل عنوان السيرفر (Server IP)',
                        style: TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _showServerConfigDialog(context),
                    ),
                  ),
                ],
              ),
            ),

          // Email Field
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              labelText: isSuperAdmin ? 'Super Admin Email' : 'Work Email Address',
              labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              hintText: isSuperAdmin ? 'admin@accredigo.eg' : 'admin@hospital.com',
              hintStyle: TextStyle(color: const Color(0xFF64748B).withValues(alpha: 0.6), fontSize: 13),
              prefixIcon: Icon(
                isSuperAdmin ? Icons.admin_panel_settings_outlined : Icons.email_outlined,
                color: primaryAccent,
              ),
              filled: true,
              fillColor: const Color(0xFF07142A),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primaryAccent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Password Field
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Password',
              labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              prefixIcon: Icon(Icons.lock_outline_rounded, color: primaryAccent),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: const Color(0xFF64748B),
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: const Color(0xFF07142A),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primaryAccent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Submit Button
          ElevatedButton(
            onPressed: _loading ? null : () => _handleLogin(isSuperAdmin: isSuperAdmin),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 4,
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
                : Text(
                    isSuperAdmin ? 'Sign In as Super Admin' : 'Sign In to Facility',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 14),

          // Switch / Back Buttons
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _switchMode(AuthViewMode.options),
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Back to Options'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF94A3B8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              if (!isSuperAdmin)
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FacilityRegistrationScreen(
                          onSuccess: () => widget.onLoginSuccess?.call(),
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Register Facility',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: () => _switchMode(AuthViewMode.facilityLogin),
                  child: const Text(
                    'Facility Sign In',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showServerConfigDialog(BuildContext context) {
    final textController = TextEditingController(text: AppConfig.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.dns_rounded, color: Color(0xFF38BDF8), size: 24),
            SizedBox(width: 8),
            Text(
              'Server IP Settings',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'أدخل عنوان السيرفر والمنفذ 3000:',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'http://192.168.1.7:3000/api',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'خيارات سريعة (Quick Options):',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        backgroundColor: const Color(0xFF334155),
                        label: const Text('Wi-Fi PC (192.168.1.7)', style: TextStyle(color: Colors.white, fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            textController.text = 'http://192.168.1.7:3000/api';
                          });
                        },
                      ),
                      ActionChip(
                        backgroundColor: const Color(0xFF334155),
                        label: const Text('محاكي (10.0.2.2)', style: TextStyle(color: Colors.white, fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            textController.text = 'http://10.0.2.2:3000/api';
                          });
                        },
                      ),
                      ActionChip(
                        backgroundColor: const Color(0xFF334155),
                        label: const Text('Localhost', style: TextStyle(color: Colors.white, fontSize: 11)),
                        onPressed: () {
                          setDialogState(() {
                            textController.text = 'http://localhost:3000/api';
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              await AppConfig.setCustomBaseUrl(textController.text);
              if (mounted) {
                setState(() {
                  _errorMessage = null;
                });
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم ضبط عنوان السيرفر: ${AppConfig.baseUrl}'),
                    backgroundColor: const Color(0xFF059669),
                  ),
                );
              }
            },
            child: const Text('حفظ واتصال', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
