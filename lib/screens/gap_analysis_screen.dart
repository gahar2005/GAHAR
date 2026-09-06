import 'package:flutter/material.dart';
import '../models/platform_models.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class GapAnalysisScreen extends StatefulWidget {
  const GapAnalysisScreen({super.key});

  @override
  State<GapAnalysisScreen> createState() => _GapAnalysisScreenState();
}

class _GapAnalysisScreenState extends State<GapAnalysisScreen> {
  List<GapItem> _gaps = [];
  bool _loading = true;
  String _selectedFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadGaps();
  }

  Future<void> _loadGaps() async {
    setState(() => _loading = true);
    final gaps = await StorageService.getGaps();
    setState(() {
      _gaps = gaps;
      _loading = false;
    });
  }

  Color _getSeverityColor(GapSeverity severity) {
    switch (severity) {
      case GapSeverity.critical:
        return AppColors.error;
      case GapSeverity.high:
        return AppColors.warning;
      case GapSeverity.medium:
        return AppColors.info;
      case GapSeverity.low:
        return Colors.grey;
    }
  }

  List<GapItem> get _filteredGaps {
    if (_selectedFilter == 'ALL') return _gaps;
    if (_selectedFilter == 'CRITICAL') {
      return _gaps.where((g) => g.severity == GapSeverity.critical).toList();
    }
    return _gaps;
  }

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Gap Analysis',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gap Analysis Engine / تحليل الفجوات'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadGaps,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Filter bar
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('All Gaps'),
                          selected: _selectedFilter == 'ALL',
                          onSelected: (_) =>
                              setState(() => _selectedFilter = 'ALL'),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Critical Gaps Only'),
                          selected: _selectedFilter == 'CRITICAL',
                          selectedColor: AppColors.error.withOpacity(0.2),
                          onSelected: (_) =>
                              setState(() => _selectedFilter = 'CRITICAL'),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredGaps.length,
                      itemBuilder: (context, index) {
                        final gap = _filteredGaps[index];

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _getSeverityColor(gap.severity)
                                            .withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${gap.severity.name.toUpperCase()} SEVERITY',
                                        style: TextStyle(
                                          color: _getSeverityColor(gap.severity),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      gap.standardCode,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  gap.gapTitle,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  gap.description,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      gap.responsiblePerson,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const Spacer(),
                                    const Icon(Icons.calendar_today,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Due: ${gap.dueDate.day}/${gap.dueDate.month}/${gap.dueDate.year}',
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
                ],
              ),
      ),
    );
  }
}
