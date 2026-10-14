import 'package:flutter/material.dart';
import '../models/platform_models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class FacilitySettingsScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const FacilitySettingsScreen({super.key, required this.onLogout});

  @override
  State<FacilitySettingsScreen> createState() => _FacilitySettingsScreenState();
}

class _FacilitySettingsScreenState extends State<FacilitySettingsScreen> {
  UserProfile? _user;
  bool _loading = true;

  final List<UserProfile> _teamMembers = [
    UserProfile(
      id: 'usr_01',
      email: 'dr.sarah@hospital.eg',
      fullName: 'Dr. Sarah Ahmed',
      role: UserRole.qualityManager,
      facilityId: 'fac_default',
      department: 'Quality & Accreditation',
      createdAt: DateTime.now(),
    ),
    UserProfile(
      id: 'usr_02',
      email: 'eng.mahmoud@hospital.eg',
      fullName: 'Eng. Mahmoud Hassan',
      role: UserRole.departmentManager,
      facilityId: 'fac_default',
      department: 'Facility & Safety (FMS)',
      createdAt: DateTime.now(),
    ),
    UserProfile(
      id: 'usr_03',
      email: 'nurse.fatma@hospital.eg',
      fullName: 'Head Nurse Fatma Ibrahim',
      role: UserRole.infectionControlOfficer,
      facilityId: 'fac_default',
      department: 'Infection Control',
      createdAt: DateTime.now(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = await StorageService.getUserProfile();
    setState(() {
      _user = user;
      _loading = false;
    });
  }

  void _inviteTeamMember() {
    showDialog(
      context: context,
      builder: (context) {
        final emailCtrl = TextEditingController();
        final nameCtrl = TextEditingController();
        UserRole selectedRole = UserRole.qualityManager;

        return AlertDialog(
          title: const Text('Invite Facility User'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Work Email'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Role & Permissions'),
                items: UserRole.values
                    .where((r) => r != UserRole.superAdmin)
                    .map((r) {
                  return DropdownMenuItem(
                    value: r,
                    child: Text(r.label, style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (val) => selectedRole = val!,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Invitation sent to ${emailCtrl.text}'),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
              child: const Text('Send Invite'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Settings',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Facility Settings & Team / الإعدادات والفريق'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Profile Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 28,
                              backgroundColor: AppColors.primary,
                              child: Icon(Icons.person,
                                  size: 32, color: Colors.white),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _user?.fullName ?? 'Quality Officer',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    _user?.role.label ?? 'Quality Manager',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    _user?.email ?? 'user@hospital.eg',
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Facility Users & RBAC Permissions',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_1_rounded,
                              color: AppColors.primary),
                          onPressed: _inviteTeamMember,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    ..._teamMembers.map((member) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.shield_outlined,
                              color: AppColors.primary),
                          title: Text(member.fullName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${member.role.label} • ${member.email}'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Active',
                                style: TextStyle(
                                    color: AppColors.success, fontSize: 11)),
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 24),
                    const Text(
                      'Subscription Info',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.workspace_premium,
                            color: Colors.amber),
                        title: const Text('Standard Hospital Plan'),
                        subtitle: const Text('Active until Dec 2025 • Multi-User'),
                        trailing: OutlinedButton(
                          child: const Text('Manage'),
                          onPressed: () {},
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('Log Out / خروج'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        onPressed: () async {
                          await StorageService.clearSession();
                          widget.onLogout();
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
