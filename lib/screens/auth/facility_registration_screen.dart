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
  State<FacilityRegistrationScreen> createState() =>
      _FacilityRegistrationScreenState();
}

class _FacilityRegistrationScreenState
    extends State<FacilityRegistrationScreen> {
  int _currentStep = 0;
  final _nameController = TextEditingController();
  final _governorateController = TextEditingController(text: 'Cairo');
  final _bedsController = TextEditingController(text: '120');
  final _adminNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _facilityType = 'Hospital / مستشفى عام';
  String _selectedPlan = 'Standard Hospital Subscription';
  String _selectedPaymentMethod = 'Bank Transfer / تحويل بنكي';
  bool _loading = false;

  final List<String> _facilityTypes = [
    'Hospital / مستشفى عام',
    'Specialized Hospital / مستشفى تخصصي',
    'Primary Healthcare Unit / وحدة رعاية أولية',
    'Diagnostic Radiology Center / مركز أشعة',
    'Medical Laboratory / معمل تحاليل',
  ];

  final List<String> _plans = [
    'Trial Plan (14 Days Free)',
    'Standard Hospital Subscription',
    'Enterprise Multi-Branch Subscription',
  ];

  final List<String> _paymentMethods = [
    'Bank Transfer / تحويل بنكي',
    'Vodafone Cash Receipt / محفظة فودافون كاش',
    'Credit Card (Online Gateway)',
  ];

  Future<void> _submitRegistration() async {
    setState(() => _loading = true);

    final payload = {
      'facilityName': _nameController.text.trim(),
      'facilityType': _facilityType,
      'governorate': _governorateController.text.trim(),
      'bedCapacity': int.tryParse(_bedsController.text) ?? 100,
      'adminName': _adminNameController.text.trim(),
      'email': _emailController.text.trim(),
      'plan': _selectedPlan,
      'paymentMethod': _selectedPaymentMethod,
    };

    await ApiService.registerFacility(payload);

    // Save locally
    final profile = HospitalProfile(
      name: _nameController.text.trim().isEmpty
          ? 'New Hospital'
          : _nameController.text.trim(),
      type: _facilityType,
      capacity: '${_bedsController.text} beds',
      departments: const ['Emergency', 'ICU', 'Surgery', 'Infection Control'],
      owner: _adminNameController.text.trim().isEmpty
          ? 'Healthcare Admin'
          : _adminNameController.text.trim(),
    );

    await StorageService.saveHospitalProfile(profile);

    final user = UserProfile(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      email: _emailController.text.trim(),
      fullName: _adminNameController.text.trim().isEmpty
          ? 'Quality Manager'
          : _adminNameController.text.trim(),
      role: UserRole.facilityAdmin,
      facilityId: 'fac_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
    );

    await StorageService.saveUserProfile(user);
    await StorageService.saveAuthToken('fac_auth_token');

    setState(() => _loading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration Request Submitted Successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      widget.onSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Register Healthcare Facility'),
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
          // Step 1: Facility Info
          Step(
            title: const Text('Facility Profile'),
            subtitle: const Text('Name, Type, Beds & Location'),
            isActive: _currentStep >= 0,
            content: Column(
              children: [
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
                    return DropdownMenuItem(value: t, child: Text(t));
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
                          labelText: 'Bed Capacity / سعة الأسرة',
                          prefixIcon: Icon(Icons.bed_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Step 2: Administrator Info
          Step(
            title: const Text('Administrator Account'),
            subtitle: const Text('Contact person & authentication'),
            isActive: _currentStep >= 1,
            content: Column(
              children: [
                TextField(
                  controller: _adminNameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name / اسم المسؤول',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Official Work Email / البريد الإلكتروني',
                    prefixIcon: Icon(Icons.email_outlined),
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

          // Step 3: Subscription & Payment
          Step(
            title: const Text('Subscription & Payment'),
            subtitle: const Text('Select Plan & Payment Workflow'),
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
                    return DropdownMenuItem(value: p, child: Text(p));
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
                      Icon(Icons.info_outline, color: AppColors.info),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Note: Subscriptions require verification by Platform Super Admin before full activation.',
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
