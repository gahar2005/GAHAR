import 'package:flutter/material.dart';
import '../models/sat_models.dart';
import '../services/sat_service.dart';

/// Sub-Evidence Detail Screen
/// Displays the individual 0/1/2 measurement rows for a given SAT standard.
/// Implements the exact Excel hierarchy: Standard → Evidence Row → Score 0/1/2
class SATSubEvidenceScreen extends StatefulWidget {
  final SATStandard standard;

  const SATSubEvidenceScreen({super.key, required this.standard});

  @override
  State<SATSubEvidenceScreen> createState() => _SATSubEvidenceScreenState();
}

class _SATSubEvidenceScreenState extends State<SATSubEvidenceScreen> {
  List<SATSubEvidenceItem> _evidenceItems = [];
  Map<String, SATSubScore> _scoreMap = {}; // evidenceId -> SATSubScore
  SATSubEvidenceCalculation? _calculation;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await SATService.getSubEvidence(widget.standard.standardCode);
      final result = await SATService.getSubScores(widget.standard.standardCode);
      final scoreMap = <String, SATSubScore>{};
      for (final s in result.scores) {
        scoreMap[s.evidenceId] = s;
      }

      if (mounted) {
        setState(() {
          _evidenceItems = items;
          _scoreMap = scoreMap;
          _calculation = result.calculation;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _loading = false; });
      }
    }
  }

  Future<void> _saveScore(SATSubEvidenceItem item, String scoreValue) async {
    setState(() { _saving = true; });
    final result = await SATService.saveSubScore(
      evidenceId: item.id,
      standardCode: widget.standard.standardCode,
      scoreValue: scoreValue,
    );
    if (result['success'] == true) {
      // Update local score map and recalculate
      final newScore = SATSubScore(
        facilityId: '',
        evidenceId: item.id,
        standardCode: widget.standard.standardCode,
        scoreValue: scoreValue,
      );
      setState(() {
        _scoreMap[item.id] = newScore;
        _calculation = SATSubEvidenceCalculation.calculate(
          standardCode: widget.standard.standardCode,
          subScores: _scoreMap.values.toList(),
        );
        _saving = false;
      });
    } else {
      setState(() { _saving = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Failed to save score'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Color _ratingColor(String? rating) {
    switch (rating) {
      case 'MET': return const Color(0xFF22C55E);
      case 'PARTIAL MET': return const Color(0xFFF59E0B);
      case 'NOT MET': return const Color(0xFFEF4444);
      default: return Colors.grey;
    }
  }

  Widget _buildScoreChip(SATSubEvidenceItem item) {
    final current = _scoreMap[item.id]?.scoreValue;
    return PopupMenuButton<String>(
      initialValue: current,
      onSelected: (val) => _saveScore(item, val),
      itemBuilder: (_) => [
        _scoreMenuItem('2', 'Fully Compliant', const Color(0xFF22C55E)),
        _scoreMenuItem('1', 'Partially Compliant', const Color(0xFFF59E0B)),
        _scoreMenuItem('0', 'Not Compliant', const Color(0xFFEF4444)),
        _scoreMenuItem('N/A', 'Not Applicable', Colors.grey),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: current == null
              ? Colors.grey.shade200
              : current == '2'
                  ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                  : current == '1'
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                      : current == '0'
                          ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                          : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: current == null
                ? Colors.grey.shade400
                : current == '2'
                    ? const Color(0xFF22C55E)
                    : current == '1'
                        ? const Color(0xFFF59E0B)
                        : current == '0'
                            ? const Color(0xFFEF4444)
                            : Colors.grey,
          ),
        ),
        child: Text(
          current ?? 'Score',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: current == null
                ? Colors.grey.shade600
                : current == '2'
                    ? const Color(0xFF22C55E)
                    : current == '1'
                        ? const Color(0xFFF59E0B)
                        : current == '0'
                            ? const Color(0xFFEF4444)
                            : Colors.grey,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _scoreMenuItem(String value, String label, Color color) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Container(
            width: 28, height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final std = widget.standard;
    final calc = _calculation;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(std.standardCode, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E40AF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_saving) const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    // Standard Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: const Color(0xFF1E40AF),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            std.standardTitle,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          if (std.bookReferenceCode.isNotEmpty)
                            Text('Book Reference: ${std.bookReferenceCode}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),

                    // Score Summary Card
                    if (calc != null)
                      Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Standard Score', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  Text(calc.percentageDisplay,
                                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _ratingColor(calc.rating))),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: _ratingColor(calc.rating).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _ratingColor(calc.rating)),
                              ),
                              child: Text(calc.rating,
                                  style: TextStyle(fontWeight: FontWeight.bold, color: _ratingColor(calc.rating))),
                            ),
                            const SizedBox(width: 12),
                            Text('${calc.scoredItems}/${calc.totalItems}\nscored',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),

                    // Formula hint
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 14, color: Colors.blueGrey),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Score = SUM(items) ÷ (COUNT × 2)   •   2=Full  1=Partial  0=None  N/A=Excluded',
                              style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Evidence Rows
                    Expanded(
                      child: _evidenceItems.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text('No sub-evidence items found for this standard.',
                                      style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              itemCount: _evidenceItems.length,
                              itemBuilder: (context, idx) {
                                final item = _evidenceItems[idx];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 1,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: const Color(0xFF1E40AF).withValues(alpha: 0.1),
                                          child: Text('${item.itemNumber}',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF))),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(item.requirementText,
                                                  style: const TextStyle(fontSize: 13, height: 1.4)),
                                              if (item.documentsRequired != null && item.documentsRequired!.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.description_outlined, size: 12, color: Colors.grey),
                                                    const SizedBox(width: 4),
                                                    Expanded(child: Text(item.documentsRequired!,
                                                        style: const TextStyle(fontSize: 11, color: Colors.grey))),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildScoreChip(item),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
