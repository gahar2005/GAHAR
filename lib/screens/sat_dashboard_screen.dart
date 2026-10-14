import 'package:flutter/material.dart';
import '../models/sat_models.dart';
import '../services/sat_service.dart';
import '../theme/app_theme.dart';
import 'sat_assessment_screen.dart';

class SATDashboardScreen extends StatefulWidget {
  const SATDashboardScreen({super.key});

  @override
  State<SATDashboardScreen> createState() => _SATDashboardScreenState();
}

class _SATDashboardScreenState extends State<SATDashboardScreen> {
  bool _isLoading = true;
  bool _isExporting = false;
  String? _errorMessage;

  SATAssessmentReport? _report;
  List<SATStandard> _standards = [];
  Map<String, SATScore> _scoresMap = {};

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final report = await SATService.getSATReport();
      final standards = await SATService.getSATStandards();
      final scores = await SATService.getSATScores();

      final map = <String, SATScore>{};
      for (final s in scores) {
        map[s.standardCode] = s;
      }

      setState(() {
        _report = report;
        _standards = standards;
        _scoresMap = map;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load SAT Dashboard data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePdfExport() async {
    if (_report == null) return;

    setState(() => _isExporting = true);
    try {
      await SATService.exportSATReportPdf(
        report: _report!,
        standards: _standards,
        scoreMap: _scoresMap,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SAT Report PDF generated successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate PDF: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GAHAR SAT Dashboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Hospital Self-Assessment Accreditation Metrics',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'Export SAT PDF Report',
            onPressed: _isExporting ? null : _handlePdfExport,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Dashboard',
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadDashboardData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroScoreCard(),
                        const SizedBox(height: 16),
                        _buildQuickActionBanner(),
                        const SizedBox(height: 20),
                        _buildStatusDistributionSection(),
                        const SizedBox(height: 20),
                        _buildChapterPerformanceSection(),
                        const SizedBox(height: 20),
                        _buildCategoriesBreakdownSection(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildHeroScoreCard() {
    final report = _report;
    final score = report?.overallScore ?? 0.0;
    final isReady = score >= 80.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_rounded, color: Colors.amberAccent, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Hospital SAT 2025 Standard',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isReady ? AppColors.success : AppColors.warning).withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isReady ? AppColors.success : AppColors.warning,
                  ),
                ),
                child: Text(
                  isReady ? 'Accreditation Ready' : 'Audit Incomplete',
                  style: TextStyle(
                    color: isReady ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                score.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
              const Text(
                '%',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Completion Rate',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  Text(
                    '${(report?.completionRate ?? 0).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (report?.completionRate ?? 0) / 100.0,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryLight),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildHeroKpi(
                label: 'Total Standards',
                value: '${report?.totalStandards ?? _standards.length}',
                icon: Icons.list_alt_rounded,
              ),
              _buildHeroKpi(
                label: 'Assessed',
                value: '${report?.assessedStandards ?? _scoresMap.length}',
                icon: Icons.assignment_turned_in_rounded,
              ),
              _buildHeroKpi(
                label: 'Remaining',
                value: '${(report?.totalStandards ?? _standards.length) - (report?.assessedStandards ?? _scoresMap.length)}',
                icon: Icons.pending_actions_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroKpi({required String label, required String value, required IconData icon}) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildQuickActionBanner() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hospital Assessment Worksheet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Evaluate General Safety Requirements (GSR) standards',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondaryLight),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SATAssessmentScreen()),
                );
                _loadDashboardData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: const Text('Open SAT', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDistributionSection() {
    final dist = _report?.statusDistribution ?? {};
    final fullyMet = dist['FULLY_MET'] ?? 0;
    final partiallyMet = dist['PARTIALLY_MET'] ?? 0;
    final notMet = dist['NOT_MET'] ?? 0;
    final notApplicable = dist['NOT_APPLICABLE'] ?? 0;
    final notAssessed = dist['NOT_ASSESSED'] ?? 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Assessment Status Distribution',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildDistCard('Fully Met', '$fullyMet', AppColors.success, '100%'),
                const SizedBox(width: 8),
                _buildDistCard('Partially', '$partiallyMet', AppColors.warning, '50%'),
                const SizedBox(width: 8),
                _buildDistCard('Not Met', '$notMet', AppColors.error, '0%'),
                const SizedBox(width: 8),
                _buildDistCard('N/A', '$notApplicable', Colors.grey.shade600, 'Excluded'),
                const SizedBox(width: 8),
                _buildDistCard('Pending', '$notAssessed', Colors.blueGrey, 'Unrated'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistCard(String title, String count, Color color, String sub) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              sub,
              style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterPerformanceSection() {
    final chapters = _report?.chapterSummaries ?? [];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Chapters Score (Excel Aggregation)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Icon(Icons.bar_chart_rounded, color: AppColors.primaryLight),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Hierarchical calculation: Item status → Category points → Chapter score',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondaryLight),
            ),
            const SizedBox(height: 14),
            if (chapters.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No chapter data recorded yet.', style: TextStyle(fontSize: 12)),
              )
            else
              ...chapters.map((chap) {
                final pct = chap.scorePercentage;
                final color = pct >= 80
                    ? AppColors.success
                    : pct >= 50
                        ? AppColors.warning
                        : AppColors.error;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${chap.chapterCode} — ${chap.chapterTitle}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          Text(
                            '${pct.toStringAsFixed(1)}%',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Assessed: ${chap.assessedStandards}/${chap.totalStandards} • Met: ${chap.fullyMet} • Partial: ${chap.partiallyMet} • Not Met: ${chap.notMet}',
                            style: const TextStyle(fontSize: 10, color: AppColors.textSecondaryLight),
                          ),
                          if (chap.notApplicable > 0)
                            Text(
                              '(${chap.notApplicable} N/A excluded)',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (pct / 100.0).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: AppColors.borderLight,
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesBreakdownSection() {
    // Group standards by category
    final Map<String, List<SATStandard>> catMap = {};
    for (final s in _standards) {
      catMap.putIfAbsent(s.category, () => []).add(s);
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GSR Category Breakdown',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            ...catMap.entries.map((entry) {
              final cat = entry.key;
              final items = entry.value;

              int scoredCount = 0;
              int points = 0;

              for (final it in items) {
                final sc = _scoresMap[it.standardCode];
                if (sc != null && sc.scoreStatus != SATScoreStatus.notAssessed) {
                  if (sc.scoreStatus != SATScoreStatus.notApplicable) {
                    scoredCount++;
                    points += (sc.numericScore ?? sc.scoreStatus.numericValue ?? 0);
                  }
                }
              }

              final catPct = scoredCount > 0 ? (points / (scoredCount * 100)) * 100 : 0.0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        cat,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: scoredCount > 0 ? (catPct / 100.0).clamp(0.0, 1.0) : 0.0,
                          minHeight: 5,
                          backgroundColor: AppColors.borderLight,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            catPct >= 80
                                ? AppColors.success
                                : catPct >= 50
                                    ? AppColors.warning
                                    : AppColors.primaryLight,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 45,
                      child: Text(
                        scoredCount > 0 ? '${catPct.toStringAsFixed(0)}%' : '0%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'An error occurred',
              style: const TextStyle(fontSize: 14, color: AppColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadDashboardData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
