import 'package:flutter/material.dart';
import '../models/evidence_item.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class EvidenceTrackerScreen extends StatefulWidget {
  const EvidenceTrackerScreen({super.key});

  @override
  State<EvidenceTrackerScreen> createState() => _EvidenceTrackerScreenState();
}

class _EvidenceTrackerScreenState extends State<EvidenceTrackerScreen> {
  List<EvidenceItem> _items = [];
  bool _loading = true;
  String _selectedCategory = 'All';
  final String _searchQuery = '';

  final List<String> _categories = [
    'All',
    'Governance',
    'Meeting Minutes',
    'Training',
    'Log',
    'Audit',
    'KPI',
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    final items = await StorageService.getEvidenceItems();
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _toggleItem(EvidenceItem item) async {
    await StorageService.toggleEvidenceItem(item.id);
    _loadItems();
  }

  List<EvidenceItem> get _filteredItems {
    return _items.where((i) {
      final matchesQuery = _searchQuery.isEmpty ||
          i.label.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          i.standardCode.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCat =
          _selectedCategory == 'All' || i.category == _selectedCategory;
      return matchesQuery && matchesCat;
    }).toList();
  }

  int get _completedCount => _items.where((i) => i.isCompleted).length;
  double get _completionRatio =>
      _items.isEmpty ? 0 : _completedCount / _items.length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredItems;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Evidence Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadItems,
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress Header
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary.withValues(alpha: 0.8), cs.secondary],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Accreditation Evidence Readiness',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    Text(
                      '${(_completionRatio * 100).round()}%',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _completionRatio,
                    minHeight: 8,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_completedCount of ${_items.length} Required Evidence Items Completed',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          // Filter Chips
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cat, style: const TextStyle(fontSize: 11)),
                    selected: isSelected,
                    onSelected: (s) {
                      if (s) setState(() => _selectedCategory = cat);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
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
                                child: Icon(
                                  Icons.file_present_outlined,
                                  size: 56,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'No evidence items tracked yet.',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Upload documents, policies, audit checklists, and meeting minutes linked to specific GAHAR standards to track compliance evidence.',
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
                    : filtered.isEmpty
                        ? const Center(child: Text('No evidence items match filter'))
                        : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: CheckboxListTile(
                              value: item.isCompleted,
                              onChanged: (_) => _toggleItem(item),
                              title: Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  decoration: item.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              subtitle: Text(
                                '${item.standardCode} • ${item.category}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.5)
                                      : Colors.black54,
                                ),
                              ),
                              secondary: CircleAvatar(
                                radius: 14,
                                backgroundColor: item.isCompleted
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.2),
                                child: Icon(
                                  item.isCompleted
                                      ? Icons.check_rounded
                                      : Icons.pending_actions_rounded,
                                  size: 16,
                                  color: item.isCompleted
                                      ? Colors.green
                                      : Colors.orange,
                                ),
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
