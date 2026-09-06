import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

class SuperAdminScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const SuperAdminScreen({super.key, required this.onLogout});

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _facilities = [];
  Map<String, dynamic> _analytics = {};
  List<dynamic> _auditLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    setState(() => _loading = true);
    final facilitiesData = await ApiService.getAdminFacilities();
    final analyticsData = await ApiService.getAdminAnalytics();
    final auditLogsData = await ApiService.getAdminAuditLogs();

    if (mounted) {
      setState(() {
        _facilities = facilitiesData;
        _analytics = analyticsData;
        _auditLogs = auditLogsData;
        _loading = false;
      });
    }
  }

  Future<void> _updateStatus(String facilityId, String status, {String? reason}) async {
    final res = await ApiService.updateFacilityStatus(facilityId, status, reason: reason);
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Facility status updated to $status'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadAdminData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Failed to update status'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
            icon: const Icon(Icons.refresh),
            onPressed: _loadAdminData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await StorageService.clearSession();
              widget.onLogout();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.local_hospital), text: 'Facilities'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
            Tab(icon: Icon(Icons.security), text: 'Audit Logs'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildFacilitiesTab(),
                _buildAnalyticsTab(),
                _buildAuditLogsTab(),
              ],
            ),
    );
  }

  Widget _buildFacilitiesTab() {
    return RefreshIndicator(
      onRefresh: _loadAdminData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Registered Facilities & Approval Queue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_facilities.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No facilities registered yet.'),
                ),
              ),
            ..._facilities.map((fac) {
              final status = fac['status'] ?? 'PENDING_REVIEW';
              final isPending = status == 'PENDING_REVIEW' || status == 'PENDING_PAYMENT';
              final isApproved = status == 'APPROVED' || status == 'ACTIVE';

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
                          Expanded(
                            child: Text(
                              fac['name'] ?? 'Hospital Name',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPending
                                  ? AppColors.warning.withOpacity(0.15)
                                  : isApproved
                                      ? AppColors.success.withOpacity(0.15)
                                      : AppColors.error.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: isPending
                                    ? AppColors.warning
                                    : isApproved
                                        ? AppColors.success
                                        : AppColors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${fac['type']} • ${fac['governorate']}',
                          style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      Text('Email: ${fac['work_email']} | Phone: ${fac['phone']}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (!isApproved)
                            ElevatedButton.icon(
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Approve & Activate'),
                              onPressed: () => _updateStatus(fac['id'], 'APPROVED'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          const SizedBox(width: 8),
                          if (isApproved)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.pause, size: 16),
                              label: const Text('Suspend'),
                              onPressed: () => _updateStatus(fac['id'], 'SUSPENDED'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.warning,
                              ),
                            ),
                          if (isPending)
                            OutlinedButton.icon(
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Reject'),
                              onPressed: () => _updateStatus(fac['id'], 'REJECTED'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.error,
                              ),
                            ),
                        ],
                      ),
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

  Widget _buildAnalyticsTab() {
    final total = _analytics['totalFacilities']?.toString() ?? '0';
    final active = _analytics['activeSubscriptions']?.toString() ?? '0';
    final pending = _analytics['pendingRegistrations']?.toString() ?? '0';
    final arr = _analytics['monthlyArrEgp']?.toString() ?? '0';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Platform Revenue & Growth Analytics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Total Facilities',
                  value: total,
                  icon: Icons.local_hospital_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: 'Active Subscriptions',
                  value: active,
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
                  value: pending,
                  icon: Icons.pending_actions,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: 'Estimated Monthly ARR',
                  value: 'EGP $arr',
                  icon: Icons.attach_money,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLogsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _auditLogs.length,
      itemBuilder: (context, index) {
        final log = _auditLogs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.security, color: AppColors.primary),
            title: Text(log['action'] ?? 'SYSTEM_EVENT',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('User: ${log['user_email'] ?? 'System'} | IP: ${log['ip_address'] ?? '127.0.0.1'}'),
            trailing: Text(
              log['timestamp'] != null ? log['timestamp'].substring(0, 10) : '',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        );
      },
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
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
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
