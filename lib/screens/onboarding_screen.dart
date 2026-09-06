import 'package:flutter/material.dart';
import '../models/hospital_profile.dart';
import '../services/storage_service.dart';

class OnboardingScreen extends StatefulWidget {
  final void Function(BuildContext context) onCompleted;
  const OnboardingScreen({super.key, required this.onCompleted});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController();
  final _ownerController = TextEditingController();

  String _type = 'Private Hospital';
  bool _isTeaching = false;
  bool _isSpecialized = false;

  final Map<String, bool> _departments = {
    'Emergency Department (ER)': true,
    'Intensive Care Unit (ICU)': true,
    'Operating Room (OR)': true,
    'Laboratory & Pathology': true,
    'Radiology & Imaging': true,
    'Pharmacy & Therapeutics': true,
    'Nursing Services': true,
    'Infection Control': true,
    'Quality & Patient Safety': true,
    'Facilities & Safety (FMS)': true,
  };

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final selectedDepts = _departments.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    final profile = HospitalProfile(
      name: _nameController.text.trim(),
      type: _type,
      capacity: _capacityController.text.trim(),
      departments: selectedDepts,
      owner: _ownerController.text.trim(),
      isTeaching: _isTeaching,
      isSpecialized: _isSpecialized,
    );

    await StorageService.saveHospitalProfile(profile);
    if (mounted) {
      widget.onCompleted(context);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    _ownerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.secondary],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.local_hospital_rounded,
                        size: 40, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Hospital Accreditation Setup',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Set up your healthcare organization profile once. All AI-generated policies, SOPs, and reports will be pre-filled with your facility details.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white60 : Colors.black54,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nameController,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Please enter hospital name' : null,
                  decoration: InputDecoration(
                    labelText: 'Hospital / Facility Name *',
                    hintText: 'e.g. Al-Amal Specialized Hospital',
                    filled: true,
                    fillColor: isDark ? const Color(0xFF16162A) : const Color(0xFFF3F3FA),
                    prefixIcon: const Icon(Icons.business_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _type,
                        decoration: InputDecoration(
                          labelText: 'Facility Type',
                          filled: true,
                          fillColor:
                              isDark ? const Color(0xFF16162A) : const Color(0xFFF3F3FA),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none),
                        ),
                        items: ['Private Hospital', 'Public Hospital', 'Medical Center', 'Clinic Network']
                            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) => setState(() => _type = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _capacityController,
                        decoration: InputDecoration(
                          labelText: 'Bed Capacity',
                          hintText: 'e.g. 200 Beds',
                          filled: true,
                          fillColor:
                              isDark ? const Color(0xFF16162A) : const Color(0xFFF3F3FA),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ownerController,
                  decoration: InputDecoration(
                    labelText: 'Ownership / Governing Body',
                    hintText: 'e.g. Ministry of Health, Private Healthcare Group',
                    filled: true,
                    fillColor: isDark ? const Color(0xFF16162A) : const Color(0xFFF3F3FA),
                    prefixIcon: const Icon(Icons.account_balance_rounded),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Teaching Hospital', style: TextStyle(fontSize: 12)),
                        value: _isTeaching,
                        onChanged: (v) => setState(() => _isTeaching = v ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Specialized Care', style: TextStyle(fontSize: 12)),
                        value: _isSpecialized,
                        onChanged: (v) => setState(() => _isSpecialized = v ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Active Departments for Accreditation Scope:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _departments.keys.map((dept) {
                    final isChecked = _departments[dept]!;
                    return FilterChip(
                      label: Text(dept, style: const TextStyle(fontSize: 11)),
                      selected: isChecked,
                      selectedColor: cs.primary.withValues(alpha: 0.25),
                      onSelected: (v) => setState(() => _departments[dept] = v),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: _saveProfile,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Save Profile & Start Accreditation Journey'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => widget.onCompleted(context),
                  child: Text('Skip for now (Use Default Templates)',
                      style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
