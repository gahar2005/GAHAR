import 'package:flutter/material.dart';
import '../models/platform_models.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class ApplicabilityScreen extends StatefulWidget {
  const ApplicabilityScreen({super.key});

  @override
  State<ApplicabilityScreen> createState() => _ApplicabilityScreenState();
}

class _ApplicabilityScreenState extends State<ApplicabilityScreen> {
  String _selectedChapter = 'ALL';

  final List<ApplicabilityItem> _items = [
    ApplicabilityItem(
      id: 'app_01',
      standardCode: 'GSR.01',
      chapterCode: 'GSR',
      title: 'Patient Rights & Responsibilities Policy',
      arabicTitle: 'سياسة حقوق وواجبات المرضى والعائلات',
      category: 'Governance',
      status: ApplicabilityStatus.applicable,
    ),
    ApplicabilityItem(
      id: 'app_02',
      standardCode: 'PCC.06',
      chapterCode: 'PCC',
      title: 'Informed Consent Process & Documentation',
      arabicTitle: 'إجراءات ونماذج الإقرار الطبي المفصل',
      category: 'Patient Care',
      status: ApplicabilityStatus.applicable,
    ),
    ApplicabilityItem(
      id: 'app_03',
      standardCode: 'SAS.03',
      chapterCode: 'SAS',
      title: 'Surgical Safety Checklist Compliance',
      arabicTitle: 'قائمة التحقق من سلامة العمليات الجراحية',
      category: 'Surgical',
      status: ApplicabilityStatus.applicable,
    ),
    ApplicabilityItem(
      id: 'app_04',
      standardCode: 'SAS.08',
      chapterCode: 'SAS',
      title: 'Bariatric Surgery Special Requirements',
      arabicTitle: 'المتطلبات الخاصة بجراحات السمنة المفرطة',
      category: 'Surgical Speciality',
      status: ApplicabilityStatus.notApplicable,
      reason: 'Facility does not perform bariatric surgical procedures.',
    ),
    ApplicabilityItem(
      id: 'app_05',
      standardCode: 'IPC.04',
      chapterCode: 'IPC',
      title: 'Isolation Rooms Negative Pressure Monitoring',
      arabicTitle: 'مراقبة ضغط الهواء السلبي لغرف العزل',
      category: 'Infection Control',
      status: ApplicabilityStatus.needsReview,
      reason: 'Requires engineering verification of airborne isolation HVAC.',
    ),
  ];

  List<ApplicabilityItem> get _filteredItems {
    if (_selectedChapter == 'ALL') return _items;
    return _items.where((i) => i.chapterCode == _selectedChapter).toList();
  }

  Color _getStatusColor(ApplicabilityStatus status) {
    switch (status) {
      case ApplicabilityStatus.applicable:
        return AppColors.success;
      case ApplicabilityStatus.notApplicable:
        return Colors.grey;
      case ApplicabilityStatus.needsReview:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Requirements',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Applicability Check / فحص انطباق المعايير'),
        ),
        body: Column(
          children: [
            // Chapter Filters
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: ['ALL', 'GSR', 'PCC', 'SAS', 'MSS', 'IPC', 'HRM', 'FMS', 'MIS']
                    .map((code) {
                  final isSelected = _selectedChapter == code;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(code),
                      onSelected: (_) => setState(() => _selectedChapter = code),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),

            // Requirements List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
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
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  item.standardCode,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              DropdownButton<ApplicabilityStatus>(
                                value: item.status,
                                underline: const SizedBox(),
                                items: ApplicabilityStatus.values.map((s) {
                                  return DropdownMenuItem(
                                    value: s,
                                    child: Row(
                                      children: [
                                        Icon(Icons.circle,
                                            size: 10, color: _getStatusColor(s)),
                                        const SizedBox(width: 6),
                                        Text(s.name.toUpperCase(),
                                            style: const TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => item.status = val);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            item.arabicTitle,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey),
                          ),
                          if (item.reason != null && item.reason!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Note: ${item.reason}',
                                style: const TextStyle(
                                    fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
