import 'package:flutter/material.dart';
import '../models/platform_models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class ActionPlansScreen extends StatefulWidget {
  const ActionPlansScreen({super.key});

  @override
  State<ActionPlansScreen> createState() => _ActionPlansScreenState();
}

class _ActionPlansScreenState extends State<ActionPlansScreen> {
  List<ActionPlanItem> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _loading = true);
    final plans = await StorageService.getActionPlans();
    setState(() {
      _plans = plans;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Action Plans',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Action Plan Manager / خطط العمل التصحيحية'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _plans.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.assignment_outlined,
                              size: 56,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'No action plans generated yet.',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Action plans (CAPA) are assigned to hospital departments and quality teams when compliance gaps are identified during your GAHAR assessment.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Colors.grey.shade600,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _plans.length,
                    itemBuilder: (context, index) {
                  final plan = _plans[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Chip(
                                label: Text(
                                  plan.status,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white),
                                ),
                                backgroundColor: plan.status == 'Completed'
                                    ? AppColors.success
                                    : AppColors.primary,
                                padding: EdgeInsets.zero,
                              ),
                              Text(
                                '${(plan.progress * 100).toInt()}% Done',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            plan.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            plan.description,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: plan.progress,
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade200,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.person_pin_outlined,
                                  size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(plan.assignedUser,
                                  style: const TextStyle(fontSize: 12)),
                              const Spacer(),
                              const Icon(Icons.business_outlined,
                                  size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(plan.department,
                                  style: const TextStyle(fontSize: 12)),
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
