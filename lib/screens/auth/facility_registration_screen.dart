import 'package:flutter/material.dart';
import '../../models/hospital_profile.dart';
import '../../models/platform_models.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../main.dart';

class FacilityRegistrationScreen extends StatefulWidget {
  final VoidCallback onSuccess;

  const FacilityRegistrationScreen({super.key, required this.onSuccess});

  @override
  State<FacilityRegistrationScreen> createState() => _FacilityRegistrationScreenState();
}

class _FacilityRegistrationScreenState extends State<FacilityRegistrationScreen> {
  int _currentStep = 0;
  final _nameController = TextEditingController();
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

  // Egyptian Governorates & Cities
  String _selectedGovernorate = 'Cairo';
  final _cityController = TextEditingController(text: 'New Cairo');

  final Map<String, List<String>> _governorateCities = {
    'Cairo': [
      'New Cairo',
      'Nasr City',
      'Heliopolis',
      'Maadi',
      'Downtown',
      'Zamalek',
      'Shubra',
      'Helwan',
      'El Shorouk',
      'Badr City',
      '15th of May',
      'New Administrative Capital',
    ],
    'Giza': [
      'Dokki',
      'Mohandessin',
      '6th of October',
      'Sheikh Zayed',
      'Haram',
      'Faisal',
      'Agouza',
      'Imbaba',
      'Hawamdia',
    ],
    'Alexandria': [
      'Smouha',
      'Sidi Gaber',
      'Miami',
      'Montaza',
      'Sporting',
      'Gleem',
      'Mansheya',
      'Borg El Arab',
      'Agami',
    ],
    'Port Said': [
      'Port Fouad',
      'Al Sharq',
      'Al Dawahy',
      'Al Arab',
      'Al Zohour',
      'Al Manakh',
    ],
    'Suez': [
      'Faisal',
      'Al Arbaeen',
      'Al Ganayen',
      'Ataqah',
      'Al Suweis',
    ],
    'Ismailia': [
      'Ismailia City',
      'Fayed',
      'El Qantara',
      'Tell El Kebir',
      'Abu Suwir',
    ],
    'Qalyubia': [
      'Banha',
      'Qalyub',
      'Shubra El Kheima',
      'Khanka',
      'Tokh',
      'Qaha',
      'El Obour',
    ],
    'Sharkia': [
      'Zagazig',
      '10th of Ramadan',
      'Belbeis',
      'Minya El Qamh',
      'Faqous',
      'Abu Hammad',
    ],
    'Gharbia': [
      'Tanta',
      'El Mahalla El Kubra',
      'Kafr El Zayat',
      'Zifta',
      'Samanoud',
    ],
    'Menoufia': [
      'Shibin El Kom',
      'Menouf',
      'Ashmoun',
      'Sadat City',
      'Quesna',
      'Berket El Sabaa',
    ],
    'Dakahlia': [
      'Mansoura',
      'Talkha',
      'Mit Ghamr',
      'Dikirnis',
      'Belqas',
      'Sinbillawin',
    ],
    'Kafr El Sheikh': [
      'Kafr El Sheikh City',
      'Desouk',
      'Baltim',
      'Fowa',
      'Metobas',
    ],
    'Damietta': [
      'Damietta City',
      'New Damietta',
      'Ras El Bar',
      'Fareskour',
      'Kafr Saad',
    ],
    'Beheira': [
      'Damanhur',
      'Kafr El Dawwar',
      'Rashid',
      'Kom Hamada',
      'Edko',
      'Abu Hummus',
    ],
    'Matrouh': [
      'Marsa Matrouh',
      'El Alamein',
      'Siwa',
      'Dabaa',
      'Salloum',
    ],
    'North Sinai': [
      'Arish',
      'Sheikh Zuweid',
      'Rafah',
      'Bir al-Abed',
    ],
    'South Sinai': [
      'Sharm El Sheikh',
      'Dahab',
      'Nuweiba',
      'Ras Sedr',
      'Saint Catherine',
      'Tor Sinai',
    ],
    'Fayoum': [
      'Fayoum City',
      'Senuris',
      'Itsa',
      'Tamiya',
      'Youssef El Seddik',
    ],
    'Beni Suef': [
      'Beni Suef City',
      'Nasser',
      'Biba',
      'El Wasta',
      'Samasta',
      'Ihnasya',
    ],
    'Minya': [
      'Minya City',
      'Mallawi',
      'Maghagha',
      'Beni Mazar',
      'Samalut',
      'Abu Qurqas',
    ],
    'Asyut': [
      'Asyut City',
      'Dairut',
      'Manfalut',
      'Qusiya',
      'Abnub',
      'El Badari',
    ],
    'Sohag': [
      'Sohag City',
      'Akhmim',
      'Girga',
      'Tahta',
      'Maragha',
      'Balyana',
    ],
    'Qena': [
      'Qena City',
      'Nag Hammadi',
      'Qus',
      'Dishna',
      'Farshut',
      'Abu Tesht',
    ],
    'Luxor': [
      'Luxor City',
      'Esna',
      'Armant',
      'El Bayadiya',
      'El Tod',
      'El Qurna',
    ],
    'Aswan': [
      'Aswan City',
      'Edfu',
      'Kom Ombo',
      'Daraw',
      'Nasr El Nuba',
    ],
    'Red Sea': [
      'Hurghada',
      'El Gouna',
      'Safaga',
      'Marsa Alam',
      'Quseir',
      'Ras Ghareb',
    ],
    'New Valley': [
      'Kharga',
      'Dakhla',
      'Farafra',
      'Paris',
      'Balat',
    ],
  };

  final List<Map<String, String>> _facilityTypes = [
    {'value': 'Hospital', 'label': 'General Hospital'},
    {'value': 'Specialized Hospital', 'label': 'Specialized Hospital'},
    {'value': 'Primary Healthcare Unit', 'label': 'Primary Healthcare Unit'},
    {'value': 'Radiology Center', 'label': 'Radiology Center'},
    {'value': 'Medical Laboratory', 'label': 'Medical Laboratory'},
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

  @override
  void dispose() {
    _nameController.dispose();
    _bedsController.dispose();
    _adminNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _paymentRefController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _submitRegistration() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final city = _cityController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please complete all required fields.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final locationString = city.isNotEmpty ? '$_selectedGovernorate - $city' : _selectedGovernorate;

    final payload = {
      'facilityName': name,
      'facilityType': _facilityType,
      'governorate': locationString,
      'city': city,
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
        capacity: '${_bedsController.text} beds ($locationString)',
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
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Register Healthcare Facility'),
        backgroundColor: AppColors.surfaceDark,
        foregroundColor: Colors.white,
        elevation: 0,
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
            padding: const EdgeInsets.only(top: 24),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: _loading ? null : details.onStepContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
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
                  const SizedBox(width: 14),
                  OutlinedButton(
                    onPressed: details.onStepCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: AppColors.borderDark),
                    ),
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
            subtitle: const Text('Name, Location & Capacity'),
            isActive: _currentStep >= 0,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                    ),
                    child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
                  ),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Facility Name',
                    hintText: 'e.g. Cairo Specialized Hospital',
                    prefixIcon: Icon(Icons.local_hospital_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _facilityType,
                  decoration: const InputDecoration(
                    labelText: 'Facility Type',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
                  items: _facilityTypes.map((t) {
                    return DropdownMenuItem(value: t['value'], child: Text(t['label']!));
                  }).toList(),
                  onChanged: (v) => setState(() => _facilityType = v!),
                ),
                const SizedBox(height: 14),
                // Location Row: Governorate & City
                Row(
                  children: [
                    // Governorate Dropdown with Arrow
                    Expanded(
                      flex: 1,
                      child: DropdownButtonFormField<String>(
                        value: _selectedGovernorate,
                        decoration: const InputDecoration(
                          labelText: 'Governorate',
                          prefixIcon: Icon(Icons.location_city_outlined),
                        ),
                        icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
                        isExpanded: true,
                        items: _governorateCities.keys.map((gov) {
                          return DropdownMenuItem(
                            value: gov,
                            child: Text(gov, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedGovernorate = val;
                              final cities = _governorateCities[val] ?? ['Central District'];
                              _cityController.text = cities.first;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // City / District with Dropdown Arrow Selector
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _cityController,
                        decoration: InputDecoration(
                          labelText: 'City / District',
                          hintText: 'Type or pick city',
                          prefixIcon: const Icon(Icons.apartment_outlined),
                          suffixIcon: PopupMenuButton<String>(
                            tooltip: 'Select City in $_selectedGovernorate',
                            icon: const Icon(Icons.arrow_drop_down_rounded, size: 28, color: AppColors.primaryLight),
                            onSelected: (city) {
                              setState(() {
                                _cityController.text = city;
                              });
                            },
                            itemBuilder: (context) {
                              final cities = _governorateCities[_selectedGovernorate] ?? ['Central District'];
                              return cities.map((c) {
                                return PopupMenuItem<String>(
                                  value: c,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.location_on_outlined, size: 18, color: AppColors.primaryLight),
                                      const SizedBox(width: 8),
                                      Text(c),
                                    ],
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Bed Capacity
                TextField(
                  controller: _bedsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Bed Capacity',
                    hintText: 'Number of inpatient beds',
                    prefixIcon: Icon(Icons.bed_outlined),
                  ),
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
                    labelText: 'Administrator Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Work Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
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
                    labelText: 'Subscription Plan',
                    prefixIcon: Icon(Icons.card_membership_outlined),
                  ),
                  icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
                  items: _plans.map((p) {
                    return DropdownMenuItem(value: p['value'], child: Text(p['label']!));
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedPlan = v!),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedPaymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    prefixIcon: Icon(Icons.payment_outlined),
                  ),
                  icon: const Icon(Icons.arrow_drop_down_rounded, size: 28),
                  items: _paymentMethods.map((pm) {
                    return DropdownMenuItem(value: pm, child: Text(pm));
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedPaymentMethod = v!),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _paymentRefController,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Reference (Optional)',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.info.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: AppColors.info),
                      SizedBox(width: 12),
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
