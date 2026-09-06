import 'package:flutter/material.dart';
import '../models/platform_models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class LicensesScreen extends StatefulWidget {
  const LicensesScreen({super.key});

  @override
  State<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends State<LicensesScreen> {
  List<LicenseItem> _licenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLicenses();
  }

  Future<void> _loadLicenses() async {
    setState(() => _loading = true);
    final licenses = await StorageService.getLicenses();
    setState(() {
      _licenses = licenses;
      _loading = false;
    });
  }

  Color _getStatusColor(LicenseStatus status) {
    switch (status) {
      case LicenseStatus.valid:
        return AppColors.success;
      case LicenseStatus.expiringSoon:
        return AppColors.warning;
      case LicenseStatus.expired:
        return AppColors.error;
      case LicenseStatus.underRenewal:
        return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Licenses Tracker',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Licenses Tracker / التراخيص والموافقات'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _licenses.length,
                itemBuilder: (context, index) {
                  final lic = _licenses[index];
                  final statusColor = _getStatusColor(lic.status);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  lic.status.name.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Text(
                                lic.licenseNumber,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            lic.licenseName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Authority: ${lic.issuingAuthority}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.event_outlined,
                                  size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                'Expires: ${lic.expirationDate.day}/${lic.expirationDate.month}/${lic.expirationDate.year}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: lic.status == LicenseStatus.expiringSoon
                                      ? AppColors.warning
                                      : Colors.black,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                lic.responsiblePerson,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
