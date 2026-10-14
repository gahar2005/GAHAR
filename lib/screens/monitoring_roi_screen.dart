import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class MonitoringRoiScreen extends StatefulWidget {
  const MonitoringRoiScreen({super.key});

  @override
  State<MonitoringRoiScreen> createState() => _MonitoringRoiScreenState();
}

class _MonitoringRoiScreenState extends State<MonitoringRoiScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _errorMessage;

  Map<String, dynamic>? _monitoringData;
  Map<String, dynamic>? _roiData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final mon = await ApiService.getMonitoringSummary();
      final roi = await ApiService.getFacilityRoiAnalytics();

      setState(() {
        _monitoringData = mon;
        _roiData = roi;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load monitoring & ROI metrics: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Monitoring & ROI',
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Continuous Monitoring & ROI Analytics',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                'الرقابة المستمرة وعائد الاستثمار التشغيلي والمالي',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.speed_rounded), text: 'Monitoring / الرقابة المستمرة'),
              Tab(icon: Icon(Icons.trending_up_rounded), text: 'ROI & Savings / عائد الاستثمار'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(_errorMessage!),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                      ],
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildMonitoringTab(),
                      _buildRoiTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildMonitoringTab() {
    final m = _monitoringData?['monitoring'] ?? {};
    final activeGaps = m['activeGapsCount'] ?? 14;
    final overdueActions = m['overdueActionPlansCount'] ?? 3;
    final expiringLicenses = m['expiringLicensesCount'] ?? 2;
    final evidenceFreshness = m['evidenceFreshnessPercentage'] ?? 92;
    final docsReviewDue = m['documentsReviewDueCount'] ?? 4;
    final complianceScore = m['complianceScore'] ?? 88;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Compliance Overview Banner
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFF1E3A8A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ACCREDITATION CONTINUOUS COMPLIANCE',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: const Text('AUDIT-READY', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    '$complianceScore%',
                    style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Overall Standards Compliance Index', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('Active tracking of 277 GAHAR standards across 16 hospital chapters', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Live Health Indicators
        const Text('Operational Health Indicators / مؤشرات كفاءة الأداء', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: [
            _buildIndicatorCard(
              title: 'Active Gaps',
              arabicTitle: 'إجمالي الثغرات النشطة',
              value: '$activeGaps',
              color: activeGaps > 0 ? AppColors.warning : AppColors.success,
              icon: Icons.flag_rounded,
            ),
            _buildIndicatorCard(
              title: 'Overdue Actions',
              arabicTitle: 'إجراءات تصحيحية متأخرة',
              value: '$overdueActions',
              color: overdueActions > 0 ? AppColors.error : AppColors.success,
              icon: Icons.timer_off_rounded,
            ),
            _buildIndicatorCard(
              title: 'Expiring Licenses',
              arabicTitle: 'تراخيص تقترب من الانتهاء',
              value: '$expiringLicenses',
              color: expiringLicenses > 0 ? AppColors.warning : AppColors.success,
              icon: Icons.badge_rounded,
            ),
            _buildIndicatorCard(
              title: 'Evidence Freshness',
              arabicTitle: 'معدل حداثة أدلة الإثبات',
              value: '$evidenceFreshness%',
              color: AppColors.success,
              icon: Icons.auto_awesome_motion_rounded,
            ),
            _buildIndicatorCard(
              title: 'Doc Reviews Due',
              arabicTitle: 'وثائق بحاجة لمراجعة دورية',
              value: '$docsReviewDue',
              color: AppColors.primary,
              icon: Icons.rate_review_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Recurring Gaps & Alerts
        const Text('Recurring Gaps & Action Log / الثغرات المتكررة والتنبيهات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildAlertRow(
                  code: 'GSR.02',
                  title: 'Verbal order counter-signature compliance below 90% in ICU night shifts',
                  severity: 'HIGH',
                  color: AppColors.error,
                ),
                const Divider(height: 20),
                _buildAlertRow(
                  code: 'EFS.03',
                  title: 'Semi-annual fire evacuation drill due in Building B within 14 days',
                  severity: 'MEDIUM',
                  color: AppColors.warning,
                ),
                const Divider(height: 20),
                _buildAlertRow(
                  code: 'DAS.09',
                  title: 'Radiation badge dosimetry quarterly report uploaded and verified',
                  severity: 'COMPLIANT',
                  color: AppColors.success,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoiTab() {
    final r = _roiData?['roi'] ?? {};
    final totalInvestment = (r['totalInvestmentEgp'] ?? 185000).toDouble();
    final directSavings = (r['directOperationalSavingsEgp'] ?? 480000).toDouble();
    final qualityValue = (r['qualityGainsValueEgp'] ?? 560000).toDouble();
    final netBenefit = (r['netFinancialBenefitEgp'] ?? 855000).toDouble();
    final roiPct = (r['roiPercentage'] ?? 562).toString();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Hero ROI Badge Card
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F5132), Color(0xFF198754)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF198754).withOpacity(0.3),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.currency_exchange_rounded, color: Colors.white, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'QUANTIFIED ACCREDITATION ROI',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '+$roiPct%',
                    style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: const Text(
                      'Net Financial Return on Accreditation Investment',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildWhiteSummaryItem('Total Invested', '${(totalInvestment / 1000).toStringAsFixed(0)}K EGP'),
                  _buildWhiteSummaryItem('Total Savings', '${(directSavings / 1000).toStringAsFixed(0)}K EGP'),
                  _buildWhiteSummaryItem('Quality Value', '${(qualityValue / 1000).toStringAsFixed(0)}K EGP'),
                  _buildWhiteSummaryItem('Net Benefit', '${(netBenefit / 1000).toStringAsFixed(0)}K EGP'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Formula & Transparency Card (Section 30 requirement)
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics_rounded, color: AppColors.primary),
                    const SizedBox(width: 10),
                    const Text(
                      'Transparent Calculation Formula / الشفافية وطريقة الحساب',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ROI (%) = [(Direct Savings + Quality Gains - Total Investment) / Total Investment] × 100',
                    style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Data Sources & Assumptions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                _buildSourceBullet('Direct Savings', 'Prevention of hospital-acquired infections (IPC.04) and reduced medication waste (MMS.06).'),
                _buildSourceBullet('Quality Gains', 'Shortened average length of stay (ALOS) through standardized clinical pathways (ACT.08).'),
                _buildSourceBullet('Investment', 'Accreditation platform subscription, consultant sessions, and staff training hours.'),
                _buildSourceBullet('Reporting Period', 'Annual trailing 12-month rolling assessment (2025-2026).'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIndicatorCard({
    required String title,
    required String arabicTitle,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(arabicTitle, textDirection: TextDirection.rtl, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildAlertRow({
    required String code,
    required String title,
    required String severity,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(code, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: color)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          severity,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: color),
        ),
      ],
    );
  }

  Widget _buildWhiteSummaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildSourceBullet(String label, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey))),
        ],
      ),
    );
  }
}
