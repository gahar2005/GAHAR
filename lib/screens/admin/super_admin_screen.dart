import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

class SuperAdminScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const SuperAdminScreen({super.key, required this.onLogout});

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen> {
  final List<Map<String, dynamic>> _registeredFacilities = [
    {
      'id': 'fac_01',
      'name': 'Cairo International Medical Center',
      'type': 'Hospital (300 Beds)',
      'governorate': 'Cairo',
      'plan': 'Enterprise Multi-Branch',
      'status': 'Active',
      'regDate': '2025-01-15',
    },
    {
      'id': 'fac_02',
      'name': 'Alexandria Specialized Children Hospital',
      'type': 'Specialized Hospital (120 Beds)',
      'governorate': 'Alexandria',
      'plan': 'Standard Hospital',
      'status': 'Pending Approval',
      'regDate': '2025-03-02',
    },
    {
      'id': 'fac_03',
      'name': 'Delta Diagnostic Labs Network',
      'type': 'Medical Laboratory',
      'governorate': 'Mansoura',
      'plan': 'Standard Lab',
      'status': 'Active',
      'regDate': '2025-02-20',
    },
  ];

  void _approveFacility(int index) {
    setState(() {
      _registeredFacilities[index]['status'] = 'Active';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Facility "${_registeredFacilities[index]['name']}" Approved!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Platform Portal'),
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await StorageService.clearSession();
              widget.onLogout();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Platform Stats Row
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'Total Facilities',
                    value: '42',
                    icon: Icons.local_hospital_outlined,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Active Subscriptions',
                    value: '38',
                    icon: Icons.workspace_premium,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'Pending Requests',
                    value: '4',
                    icon: Icons.pending_actions,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Monthly ARR',
                    value: 'EGP 185k',
                    icon: Icons.attach_money,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Text(
              'Registered Facilities & Registration Approvals',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            ..._registeredFacilities.asMap().entries.map((entry) {
              final idx = entry.key;
              final fac = entry.value;
              final isPending = fac['status'] == 'Pending Approval';

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
                          Text(
                            fac['name'],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPending
                                  ? AppColors.warning.withOpacity(0.15)
                                  : AppColors.success.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              fac['status'].toUpperCase(),
                              style: TextStyle(
                                color: isPending
                                    ? AppColors.warning
                                    : AppColors.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${fac['type']} • ${fac['governorate']}',
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey)),
                      Text('Plan: ${fac['plan']} | Registered: ${fac['regDate']}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      if (isPending) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Approve & Activate'),
                              onPressed: () => _approveFacility(idx),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              child: const Text('Reject'),
                              onPressed: () {},
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
