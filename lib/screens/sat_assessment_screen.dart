import 'package:flutter/material.dart';
import '../models/sat_models.dart';
import '../services/sat_service.dart';
import '../theme/app_theme.dart';

class SATAssessmentScreen extends StatefulWidget {
  final String? initialChapter;

  const SATAssessmentScreen({super.key, this.initialChapter});

  @override
  State<SATAssessmentScreen> createState() => _SATAssessmentScreenState();
}

class _SATAssessmentScreenState extends State<SATAssessmentScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  List<SATStandard> _allStandards = [];
  Map<String, SATScore> _scoresMap = {}; // standardCode -> SATScore
  final Map<String, SATScore> _modifiedScores = {}; // standardCode -> SATScore (dirty)

  // Filters
  String _searchQuery = '';
  String _selectedCategory = 'ALL';
  String _selectedStatusFilter = 'ALL';

  final TextEditingController _searchController = TextEditingController();
  final Map<String, TextEditingController> _notesControllers = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    for (final controller in _notesControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final standards = await SATService.getSATStandards(
        chapterCode: widget.initialChapter ?? 'GSR',
      );
      final scores = await SATService.getSATScores();

      final scoresMap = <String, SATScore>{};
      for (final s in scores) {
        scoresMap[s.standardCode] = s;
      }

      // Initialize text controllers for notes
      for (final std in standards) {
        final existingNote = scoresMap[std.standardCode]?.notes ?? '';
        _notesControllers[std.standardCode] = TextEditingController(text: existingNote);
      }

      setState(() {
        _allStandards = standards;
        _scoresMap = scoresMap;
        _modifiedScores.clear();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load SAT assessment data: $e';
        _isLoading = false;
      });
    }
  }

  void _onStatusChanged(SATStandard standard, SATScoreStatus newStatus) {
    final code = standard.standardCode;
    final currentScore = _scoresMap[code];
    final currentNote = _notesControllers[code]?.text ?? '';

    final updated = SATScore(
      facilityId: currentScore?.facilityId ?? '',
      standardCode: code,
      scoreStatus: newStatus,
      numericScore: newStatus.numericValue,
      notes: currentNote,
      updatedAt: DateTime.now(),
    );

    setState(() {
      _scoresMap[code] = updated;
      _modifiedScores[code] = updated;
    });
  }

  void _onNotesChanged(SATStandard standard, String newNotes) {
    final code = standard.standardCode;
    final current = _scoresMap[code] ??
        SATScore(
          facilityId: '',
          standardCode: code,
          scoreStatus: SATScoreStatus.notAssessed,
          notes: newNotes,
        );

    final updated = current.copyWith(notes: newNotes);
    _scoresMap[code] = updated;
    _modifiedScores[code] = updated;
  }

  Future<void> _saveSingleScore(String standardCode) async {
    final score = _scoresMap[standardCode];
    if (score == null) return;

    setState(() => _isSaving = true);
    final res = await SATService.saveSATScore(score);
    setState(() => _isSaving = false);

    if (mounted) {
      if (res['success'] == true) {
        _modifiedScores.remove(standardCode);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Standard $standardCode saved successfully'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Error saving score'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _saveAllDirtyScores() async {
    if (_modifiedScores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All changes are already saved.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    final dirtyList = _modifiedScores.values.toList();
    final res = await SATService.saveBulkScores(dirtyList);
    setState(() => _isSaving = false);

    if (mounted) {
      if (res['success'] == true) {
        setState(() {
          _modifiedScores.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${res['count'] ?? dirtyList.length} standards saved successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Error during bulk save'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Filtered standards list
  List<SATStandard> get _filteredStandards {
    return _allStandards.where((std) {
      // Search filter
      final q = _searchQuery.toLowerCase().trim();
      final matchesSearch = q.isEmpty ||
          std.standardCode.toLowerCase().contains(q) ||
          std.standardTitle.toLowerCase().contains(q) ||
          std.category.toLowerCase().contains(q) ||
          std.bookReferenceCode.toLowerCase().contains(q);

      if (!matchesSearch) return false;

      // Category filter
      if (_selectedCategory != 'ALL' && std.category != _selectedCategory) {
        return false;
      }

      // Status filter
      if (_selectedStatusFilter != 'ALL') {
        final score = _scoresMap[std.standardCode];
        final status = score?.scoreStatus ?? SATScoreStatus.notAssessed;
        if (status.value != _selectedStatusFilter) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // Categories list
  List<String> get _categories {
    final cats = _allStandards.map((s) => s.category).toSet().toList();
    cats.sort();
    return ['ALL', ...cats];
  }

  // Progress metrics calculation according to Hospital SAT rules
  double get _overallPercentage {
    int scorableCount = 0;
    int pointsEarned = 0;

    for (final std in _allStandards) {
      final score = _scoresMap[std.standardCode];
      if (score != null && score.scoreStatus != SATScoreStatus.notAssessed) {
        if (score.scoreStatus != SATScoreStatus.notApplicable) {
          scorableCount++;
          pointsEarned += (score.numericScore ?? score.scoreStatus.numericValue ?? 0);
        }
      }
    }

    if (scorableCount == 0) return 0.0;
    return (pointsEarned / (scorableCount * 100)) * 100;
  }

  int get _assessedCount {
    return _allStandards.where((std) {
      final score = _scoresMap[std.standardCode];
      return score != null && score.scoreStatus != SATScoreStatus.notAssessed;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hospital SAT Assessment',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'GAHAR General Safety Requirements (GSR)',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 1,
        actions: [
          if (_modifiedScores.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Badge(
                  label: Text('${_modifiedScores.length}'),
                  backgroundColor: AppColors.warning,
                  child: IconButton(
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded),
                    tooltip: 'Save All Changes (${_modifiedScores.length} pending)',
                    onPressed: _isSaving ? null : _saveAllDirtyScores,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Standards & Scores',
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : Column(
                  children: [
                    _buildKpiHeader(),
                    _buildFilterBar(),
                    Expanded(
                      child: _filteredStandards.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              itemCount: _filteredStandards.length,
                              itemBuilder: (context, index) {
                                return _buildStandardCard(_filteredStandards[index]);
                              },
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: _modifiedScores.isNotEmpty ? _buildStickySaveBar() : null,
    );
  }

  Widget _buildKpiHeader() {
    final pct = _overallPercentage;
    final total = _allStandards.length;
    final assessed = _assessedCount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GSR Compliance Score',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${pct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: pct >= 80
                                ? AppColors.success
                                : pct >= 50
                                    ? AppColors.warning
                                    : AppColors.error,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (pct >= 80 ? AppColors.success : AppColors.warning).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            pct >= 80 ? 'Accreditation Ready' : 'In Progress',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: pct >= 80 ? AppColors.success : AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Assessment Progress',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondaryLight),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$assessed of $total Standards',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? assessed / total : 0.0,
              minHeight: 6,
              backgroundColor: AppColors.borderLight,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryLight),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(
          bottom: BorderSide(color: AppColors.borderLight),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search standard code, title, or reference...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
              isDense: true,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Category filter dropdown
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Category',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  items: _categories.map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Text(
                        c == 'ALL' ? 'All Categories (${_allStandards.length})' : c,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Status filter dropdown
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedStatusFilter,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Status',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All Statuses', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'NOT_ASSESSED', child: Text('Not Assessed', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'FULLY_MET', child: Text('Fully Met (100%)', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'PARTIALLY_MET', child: Text('Partially Met (50%)', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'NOT_MET', child: Text('Not Met (0%)', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: 'NOT_APPLICABLE', child: Text('N/A (Excluded)', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedStatusFilter = val);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStandardCard(SATStandard std) {
    final code = std.standardCode;
    final score = _scoresMap[code];
    final currentStatus = score?.scoreStatus ?? SATScoreStatus.notAssessed;
    final isDirty = _modifiedScores.containsKey(code);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isDirty ? AppColors.warning : AppColors.borderLight,
          width: isDirty ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Code + Reference + Badges
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    std.standardCode,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    'Ref: ${std.bookReferenceCode}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),
                if (std.isEssential) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 12, color: Colors.amber),
                        SizedBox(width: 2),
                        Text(
                          'Essential',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (isDirty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Unsaved',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.warning),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Standard Title
            Text(
              std.standardTitle,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),

            // Category & Subcategory
            Text(
              '${std.category} • ${std.subcategory}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondaryLight),
            ),
            const SizedBox(height: 12),

            // Scoring Selector Buttons
            const Text(
              'Assessment Status:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondaryLight),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildStatusChip(
                  label: 'Fully Met (100%)',
                  status: SATScoreStatus.fullyMet,
                  currentStatus: currentStatus,
                  activeColor: AppColors.success,
                  onTap: () => _onStatusChanged(std, SATScoreStatus.fullyMet),
                ),
                _buildStatusChip(
                  label: 'Partially Met (50%)',
                  status: SATScoreStatus.partiallyMet,
                  currentStatus: currentStatus,
                  activeColor: AppColors.warning,
                  onTap: () => _onStatusChanged(std, SATScoreStatus.partiallyMet),
                ),
                _buildStatusChip(
                  label: 'Not Met (0%)',
                  status: SATScoreStatus.notMet,
                  currentStatus: currentStatus,
                  activeColor: AppColors.error,
                  onTap: () => _onStatusChanged(std, SATScoreStatus.notMet),
                ),
                _buildStatusChip(
                  label: 'N/A (Excluded)',
                  status: SATScoreStatus.notApplicable,
                  currentStatus: currentStatus,
                  activeColor: Colors.grey.shade600,
                  onTap: () => _onStatusChanged(std, SATScoreStatus.notApplicable),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Notes field
            TextField(
              controller: _notesControllers[code],
              decoration: InputDecoration(
                hintText: 'Add findings, evidence links, or compliance notes...',
                hintStyle: const TextStyle(fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: AppColors.borderLight),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  tooltip: 'Save item',
                  onPressed: () => _saveSingleScore(code),
                ),
              ),
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              onChanged: (val) => _onNotesChanged(std, val),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required SATScoreStatus status,
    required SATScoreStatus currentStatus,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final isSelected = currentStatus == status;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : activeColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? activeColor : activeColor.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : activeColor,
          ),
        ),
      ),
    );
  }

  Widget _buildStickySaveBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${_modifiedScores.length} unsaved changes',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveAllDirtyScores,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload_rounded, size: 18),
              label: Text(_isSaving ? 'Saving...' : 'Save All Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryLight,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No standards match your filter criteria',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Try clearing search queries or selecting all categories.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedCategory = 'ALL';
                  _selectedStatusFilter = 'ALL';
                });
              },
              child: const Text('Reset All Filters'),
            ),
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
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
