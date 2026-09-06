import 'package:flutter/material.dart';
import '../../models/hospital_profile.dart';
import '../../models/platform_models.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

class FacilityRegistrationScreen extends StatefulWidget {
  final VoidCallback onSuccess;

  const FacilityRegistrationScreen({super.key, required this.onSuccess});

  @override
  State<FacilityRegistrationScreen> createState() => _FacilityRegistrationScreenState();
}

class _FacilityRegistrationScreenState extends State<FacilityRegistrationScreen> {
  int _currentStep = 0;
  final _nameController = TextEditingController();
  final _governorateController = TextEditingController(text: 'Cairo');
  final _bedsController = TextEditingController(text: '120');
  final _adminNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController(text: '+201001234567');
  final _passwordController = TextEditingController();
  final _paymentRefController = TextEditingController();

  String _facilityType = 'Hospital';
  String _selectedPlan = 'plan_standard';
  String _selectedPaymentMethod = 'Vodafone Cash';
  bool _loading = false;
  String? _errorMessage;

  final List<Map<String, String>> _facilityTypes = [
    {'value': 'Hospital', 'label': 'Hospital / مستشفى عام'},
    {'value': 'Specialized Hospital', 'label': 'Specialized Hospital / مستشفى تخصصي'},
    {'value': 'Primary Healthcare Unit', 'label': 'Primary Care Unit / وحدة رعاية أولية'},
    {'value': 'Radiology Center', 'label': 'Radiology Center / مركز أشعة'},
    {'value': 'Medical Laboratory', 'label': 'Medical Laboratory / معمل تحاليل'},
  ];

  final List<Map<String, String>> _plans = [
    {'value': 'plan_standard', 'label': 'Standard Hospital (EGP 45,000 / year)'},
    {'value': 'plan_enterprise', 'label': 'Enterprise Multi-Branch (EGP 120,000 / year)'},
    {'value': 'plan_lab', 'label': 'Specialized Center / Lab (EGP 25,000 / year)'},
  ];

  final List<String> _paymentMethods = [
    'Vodafone Cash',
    'Bank Transfer',
    'Online Gateway',
  ];

  Future<void> _submitRegistration() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please complete all required fields.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final payload = {
      'facilityName': name,
      'facilityType': _facilityType,
      'governorate': _governorateController.text.trim(),
      'bedCapacity': _bedsController.text.trim(),
      'contactPerson': _adminNameController.text.trim(),
      'workEmail': email,
      'phone': _phoneController.text.trim(),
      'password': password,
      'subscriptionPlanId': _selectedPlan,
      'paymentMethod': _selectedPaymentMethod,
      'paymentReference': _paymentRefController.text.trim(),
    };

    final response = await ApiService.registerFacility(payload);

    if (response['success'] == true) {
      final fac = response['facility'] ?? {};
      final usr = response['user'] ?? {};

      final userProfile = UserProfile(
        id: usr['id'] ?? 'usr_1',
        email: email,
        fullName: _adminNameController.text.trim().isEmpty ? 'Administrator' : _adminNameController.text.trim(),
        role: UserRole.facilityAdmin,
        facilityId: fac['id'] ?? 'fac_1',
        createdAt: DateTime.now(),
      );

      final hospitalProfile = HospitalProfile(
        name: name,
        type: _facilityType,
        capacity: '${_bedsController.text} beds',
        departments: const ['Emergency', 'ICU', 'Surgery', 'Quality Committee'],
        owner: _adminNameController.text.trim(),
      );

      await StorageService.saveAuthToken(response['token'] ?? '');
      await StorageService.saveUserProfile(userProfile);
      await StorageService.saveHospitalProfile(hospitalProfile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration Request Submitted to Super Admin!'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onSuccess();
      }
    } else {
      setState(() => _errorMessage = response['message'] ?? 'Registration failed.');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Healthcare Facility'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() => _currentStep += 1);
          } else {
            _submitRegistration();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          }
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _loading ? null : details.onStepContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_currentStep == 2 ? 'Submit Registration' : 'Next Step'),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          // Step 1: Facility Profile
          Step(
            title: const Text('Facility Profile'),
            subtitle: const Text('Name, Type & Capacity'),
            isActive: _currentStep >= 0,
            content: Column(
              children: [
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    color: AppColors.error.withOpacity(0.1),
                    child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Facility Name / اسم المنشأة الطبية',
                    prefixIcon: Icon(Icons.local_hospital_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _facilityType,
                  decoration: const InputDecoration(
                    labelText: 'Facility Type / نوع المنشأة',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: _facilityTypes.map((t) {
                    return DropdownMenuItem(value: t['value'], child: Text(t['label']!));
                  }).toList(),
                  onChanged: (v) => setState(() => _facilityType = v!),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _governorateController,
                        decoration: const InputDecoration(
                          labelText: 'Governorate / المحافظة',
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _bedsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Bed Capacity / الأسرة',
                          prefixIcon: Icon(Icons.bed_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Step 2: Administrator Credentials
          Step(
            title: const Text('Administrator Account'),
            subtitle: const Text('Contact Person & Auth'),
            isActive: _currentStep >= 1,
            content: Column(
              children: [
                TextField(
                  controller: _adminNameController,
                  decoration: const InputDecoration(
                    labelText: 'Administrator Name / اسم المسؤول',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Work Email / البريد الرسمي',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number / رقم الهاتف',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password / كلمة المرور',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
              ],
            ),
          ),

          // Step 3: Subscription & Payment Verification
          Step(
            title: const Text('Subscription & Payment'),
            subtitle: const Text('Plan Selection & Payment Proof'),
            isActive: _currentStep >= 2,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedPlan,
                  decoration: const InputDecoration(
                    labelText: 'Subscription Plan / خطة الاشتراك',
                    prefixIcon: Icon(Icons.card_membership_outlined),
                  ),
                  items: _plans.map((p) {
                    return DropdownMenuItem(value: p['value'], child: Text(p['label']!));
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedPlan = v!),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedPaymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method / طريقة الدفع',
                    prefixIcon: Icon(Icons.payment_outlined),
                  ),
                  items: _paymentMethods.map((pm) {
                    return DropdownMenuItem(value: pm, child: Text(pm));
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedPaymentMethod = v!),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _paymentRefController,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Reference / رقم عملية الدفع (Optional)',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.info),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: AppColors.info),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your registration request will be submitted to Super Admin for verification. Account will be activated upon review.',
                          style: TextStyle(fontSize: 12, color: AppColors.info),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
