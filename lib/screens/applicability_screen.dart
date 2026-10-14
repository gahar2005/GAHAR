import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class ApplicabilityScreen extends StatefulWidget {
  const ApplicabilityScreen({super.key});

  @override
  State<ApplicabilityScreen> createState() => _ApplicabilityScreenState();
}

class _ApplicabilityScreenState extends State<ApplicabilityScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  List<dynamic> _questions = [];
  Map<String, bool> _answers = {};
  List<dynamic> _excludedStandards = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadApplicabilityData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadApplicabilityData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final questions = await ApiService.getApplicabilityQuestions();
      final status = await ApiService.getFacilityApplicability();

      final answersMap = <String, bool>{};
      if (status['success'] == true && status['applicability'] != null) {
        final appData = status['applicability'];
        if (appData['answersMap'] is Map) {
          (appData['answersMap'] as Map).forEach((k, v) {
            answersMap[k.toString()] = v == true;
          });
        } else if (appData['answers'] is List) {
          for (final item in (appData['answers'] as List)) {
            if (item is Map && item['questionId'] != null) {
              answersMap[item['questionId'].toString()] = item['answer'] == true;
            }
          }
        } else if (appData['answers'] is Map) {
          (appData['answers'] as Map).forEach((k, v) {
            answersMap[k.toString()] = v == true;
          });
        }
      }

      // Initialize defaults if not answered yet
      for (final q in questions) {
        final qId = q['id'] as String;
        if (!answersMap.containsKey(qId)) {
          answersMap[qId] = q['defaultAnswer'] == true;
        }
      }

      setState(() {
        _questions = questions;
        _answers = answersMap;
        _excludedStandards = (status['applicability']?['excludedStandards'] as List<dynamic>?) ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load applicability scope: $e';
        _loading = false;
      });
    }
  }

  Future<void> _saveApplicability() async {
    setState(() => _saving = true);
    try {
      final res = await ApiService.submitFacilityApplicability(_answers);
      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Applicability scope saved! ${res['summary']?['excludedStandardsCount'] ?? 0} standards excluded.',
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
        await _loadApplicabilityData();
        _tabController.animateTo(1);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? 'Failed to save applicability'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Applicability Engine',
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GAHAR Applicability Engine',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                'فحص انطباق المعايير وتحديد نطاق الخدمات الطبية',
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
              Tab(icon: Icon(Icons.quiz_rounded), text: 'Scope Questionnaire / الاستبيان'),
              Tab(icon: Icon(Icons.rule_folder_rounded), text: 'Applicable Scope / المعايير المنطبقة'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                          const SizedBox(height: 12),
                          Text(_errorMessage!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadApplicabilityData,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildQuestionnaireTab(),
                      _buildStatusTab(),
                    ],
                  ),
        bottomNavigationBar: _tabController.index == 0
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveApplicability,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(
                      _saving ? 'Calculating Scope...' : 'Calculate & Save Applicability Scope / حفظ وتطبيق النطاق',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildQuestionnaireTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'The GAHAR Applicability Engine automatically configures your hospital\'s accreditation scope. Non-applicable standards are strictly excluded from SAT scores, gap analysis, and policy requirements.',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ..._questions.map((q) {
          final qId = q['id'] as String;
          final isChecked = _answers[qId] ?? false;
          final impacted = (q['impactedStandards'] as List<dynamic>?) ?? [];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 1.5,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentGold.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          q['category'] ?? 'Scope',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8C6D1F),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Switch.adaptive(
                        value: isChecked,
                        activeColor: AppColors.primary,
                        onChanged: (val) {
                          setState(() {
                            _answers[qId] = val;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    q['titleEn'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    q['titleAr'] ?? '',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    q['descriptionEn'] ?? '',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Standards: ',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
                      ),
                      ...impacted.map((std) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isChecked ? AppColors.success.withOpacity(0.1) : Colors.grey.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              std.toString(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isChecked ? AppColors.success : Colors.grey.shade700,
                              ),
                            ),
                          )),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildStatusTab() {
    final totalStandards = 277;
    final excludedCount = _excludedStandards.length;
    final applicableCount = totalStandards - excludedCount;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Metric Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'Total Standards',
                subtitle: 'إجمالي المعايير',
                value: '$totalStandards',
                icon: Icons.list_alt_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Applicable',
                subtitle: 'منطبقة رسمياً',
                value: '$applicableCount',
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'Excluded (N/A)',
                subtitle: 'مستبعدة لعدم التوفر',
                value: '$excludedCount',
                icon: Icons.remove_circle_outline_rounded,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        const Text(
          'Excluded Standards (Non-Applicable Scope) / المعايير المستبعدة',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'These standards are automatically marked as N/A in SAT assessments, omitted from the gap analysis score denominator, and do not require policies.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),

        if (_excludedStandards.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Icon(Icons.verified_rounded, size: 48, color: AppColors.success),
                SizedBox(height: 10),
                Text(
                  'Full Hospital Scope Active',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 4),
                Text(
                  'All 277 GAHAR standards are applicable to your facility.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          )
        else
          ..._excludedStandards.map((std) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.block_rounded, color: Colors.grey, size: 20),
                ),
                title: Text(
                  std.toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                subtitle: const Text(
                  'Excluded by Scope of Service response • Not calculated in SAT denominator',
                  style: TextStyle(fontSize: 11),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'N/A EXCLUDED',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
