import 'package:flutter/material.dart';
import '../models/platform_models.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class SurveyPrepScreen extends StatefulWidget {
  const SurveyPrepScreen({super.key});

  @override
  State<SurveyPrepScreen> createState() => _SurveyPrepScreenState();
}

class _SurveyPrepScreenState extends State<SurveyPrepScreen> {
  final SurveyReadiness _readiness = SurveyReadiness(
    readinessScore: 82.5,
    totalApplicableRequirements: 140,
    compliantRequirements: 115,
    openGapsCount: 12,
    criticalGapsCount: 2,
    missingEvidenceCount: 4,
    expiringLicensesCount: 1,
    highRiskAreas: [
      'Fire Evacuation Disaster Drills Documentation (FMS.02)',
      'High-Alert Medication Double-Check Log (MSS.01)',
      'ICU Hand Hygiene Compliance Audits (IPC.02)',
    ],
  );

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Survey Readiness',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accreditation Survey Preparation / الاستعداد للاعتماد'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Readiness Score Card
              Card(
                color: AppColors.primary,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 80,
                            height: 80,
                            child: CircularProgressIndicator(
                              value: _readiness.readinessScore / 100,
                              strokeWidth: 8,
                              color: AppColors.success,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                          Text(
                            '${_readiness.readinessScore.toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Survey Readiness Score',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_readiness.compliantRequirements} of ${_readiness.totalApplicableRequirements} Requirements Verified',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Target Survey: Nov 2025',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Text(
                'Pre-Survey Checklist & Warnings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              _buildWarningTile(
                icon: Icons.warning_amber_rounded,
                color: AppColors.error,
                title: '${_readiness.criticalGapsCount} Critical Open Gaps',
                subtitle: 'Requires immediate action plan resolution',
              ),
              _buildWarningTile(
                icon: Icons.fact_check_outlined,
                color: AppColors.warning,
                title: '${_readiness.missingEvidenceCount} Missing Evidence Documents',
                subtitle: 'Auditor verification pending',
              ),
              _buildWarningTile(
                icon: Icons.assignment_late_outlined,
                color: AppColors.info,
                title: '${_readiness.expiringLicensesCount} License Expiring Soon',
                subtitle: 'Radiation Protection License renewal',
              ),

              const SizedBox(height: 20),
              const Text(
                'High Risk Areas Identified by AI',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              ..._readiness.highRiskAreas.map((area) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.shield_sharp, color: AppColors.warning),
                    title: Text(area, style: const TextStyle(fontSize: 13)),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWarningTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
