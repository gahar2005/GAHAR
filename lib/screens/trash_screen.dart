import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Trash / Recycle Bin screen for the GAHAR platform.
/// All data is scoped to the authenticated facility tenant via JWT.
/// No mock data — all records come from the real backend.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<dynamic> _items = [];
  bool _loading = true;
  String? _error;

  String? _selectedType;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const Map<String?, String> _typeLabels = {
    null: 'All',
    'document': 'Documents',
    'gap': 'Gaps',
    'action_plan': 'Action Plans',
    'license': 'Licenses',
  };

  static const Map<String, IconData> _typeIcons = {
    'document': Icons.description_rounded,
    'gap': Icons.analytics_rounded,
    'action_plan': Icons.task_alt_rounded,
    'license': Icons.badge_rounded,
  };

  static const Map<String, Color> _typeColors = {
    'document': AppColors.accent,
    'gap': AppColors.warning,
    'action_plan': AppColors.primaryLight,
    'license': AppColors.accentGold,
  };

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTrash() async {
    setState(() { _loading = true; _error = null; });
    try {
      final items = await ApiService.getTrash(
        type: _selectedType,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    final ok = await _confirm(
      title: 'Restore Item',
      message: 'Restore "${item['item_name']}" to ${item['module'] ?? 'its original module'}?',
      confirmLabel: 'Restore',
      confirmColor: AppColors.success,
      confirmIcon: Icons.restore_rounded,
    );
    if (ok != true || !mounted) return;
    final res = await ApiService.restoreTrashItem(item['id'] as String);
    if (!mounted) return;
    _showSnack(
      res['success'] == true
          ? 'Restored "${item['item_name']}" to ${item['module'] ?? 'original module'}.'
          : (res['message'] as String? ?? 'Failed to restore item.'),
      res['success'] == true ? AppColors.success : AppColors.error,
    );
    if (res['success'] == true) _loadTrash();
  }

  Future<void> _permanentDelete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_rounded, color: AppColors.error),
          SizedBox(width: 8),
          Text('Permanently Delete'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are about to permanently delete:', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            _warnBox('"${item['item_name']}"', bold: true),
            const SizedBox(height: 10),
            _warnBox('This action CANNOT be undone. The record will be permanently removed.', icon: Icons.info_outline),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Delete Permanently'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await ApiService.permanentDeleteTrashItem(item['id'] as String);
    if (!mounted) return;
    _showSnack(
      res['success'] == true
          ? '"${item['item_name']}" permanently deleted.'
          : (res['message'] as String? ?? 'Failed to delete item.'),
      AppColors.error,
    );
    if (res['success'] == true) _loadTrash();
  }

  Future<void> _emptyTrash() async {
    if (_items.isEmpty) return;
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 26),
          SizedBox(width: 8),
          Text('Empty Trash'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are about to permanently delete all ${_items.length} item(s) in Trash.', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            _warnBox('This action CANNOT be undone. All trashed records will be permanently removed.', icon: Icons.block),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Empty Trash'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Final Confirmation'),
        content: const Text('Are you absolutely sure? This permanently deletes ALL trashed items and cannot be reversed.', style: TextStyle(fontWeight: FontWeight.w500)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, Go Back')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Delete All'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;
    final res = await ApiService.emptyTrash();
    if (!mounted) return;
    _showSnack(
      res['success'] == true
          ? 'Trash emptied — ${res['deletedCount'] ?? 0} item(s) permanently deleted.'
          : (res['message'] as String? ?? 'Failed to empty trash.'),
      AppColors.error,
    );
    if (res['success'] == true) _loadTrash();
  }

  Future<void> _restoreAll() async {
    if (_items.isEmpty) return;
    final ok = await _confirm(
      title: 'Restore All Items',
      message: 'Restore all ${_items.length} item(s) back to their original modules?',
      confirmLabel: 'Restore All',
      confirmColor: AppColors.success,
      confirmIcon: Icons.restore_page_rounded,
    );
    if (ok != true || !mounted) return;
    final res = await ApiService.restoreAllTrash();
    if (!mounted) return;
    _showSnack(
      res['success'] == true
          ? 'Restored ${res['restoredCount'] ?? 0} item(s) successfully.'
          : (res['message'] as String? ?? 'Failed to restore all items.'),
      res['success'] == true ? AppColors.success : AppColors.error,
    );
    if (res['success'] == true) _loadTrash();
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required IconData confirmIcon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton.icon(
            icon: Icon(confirmIcon),
            label: Text(confirmLabel),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  static Widget _warnBox(String text, {bool bold = false, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, color: AppColors.error, size: 15), const SizedBox(width: 7)],
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.error, fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
        ],
      ),
    );
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '\u2014';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.cardDark : Colors.white;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final subColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.delete_rounded, color: AppColors.error, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Trash / Recycle Bin', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('\u0633\u0644\u0629 \u0627\u0644\u0645\u062d\u0630\u0648\u0641\u0627\u062a', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh', onPressed: _loadTrash),
          if (_items.isNotEmpty) ...[
            TextButton.icon(
              icon: const Icon(Icons.restore_page_rounded, color: AppColors.success, size: 18),
              label: const Text('Restore All', style: TextStyle(color: AppColors.success, fontSize: 13)),
              onPressed: _restoreAll,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 18),
                label: const Text('Empty Trash', style: TextStyle(color: AppColors.error, fontSize: 13)),
                onPressed: _emptyTrash,
              ),
            ),
          ],
        ],
      ),
      body: Column(children: [
        // Search + Filters
        Container(
          color: cardColor,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(children: [
            TextField(
              controller: _searchController,
              onChanged: (v) { setState(() => _searchQuery = v); _loadTrash(); },
              decoration: InputDecoration(
                hintText: 'Search trashed items... / \u0627\u0628\u062d\u062b',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); _loadTrash(); })
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _typeLabels.entries.map((e) {
                  final sel = _selectedType == e.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: sel,
                      label: Text(e.value, style: TextStyle(fontSize: 12, color: sel ? Colors.white : textColor, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                      avatar: e.key != null ? Icon(_typeIcons[e.key]!, size: 14, color: sel ? Colors.white : (_typeColors[e.key] ?? AppColors.primary)) : null,
                      selectedColor: AppColors.primary,
                      checkmarkColor: Colors.white,
                      onSelected: (_) { setState(() => _selectedType = e.key); _loadTrash(); },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),

        // Warning banner
        if (!_loading && _items.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.22)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 15),
              const SizedBox(width: 8),
              Expanded(child: Text(
                '${_items.length} item${_items.length == 1 ? '' : 's'} in Trash. Restore to recover, or permanently delete. Only Facility Admins can permanently delete.',
                style: const TextStyle(fontSize: 11, color: AppColors.warning),
              )),
            ]),
          ),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError(subColor)
                  : _items.isEmpty
                      ? _buildEmpty(isDark, textColor, subColor)
                      : _buildList(cardColor, textColor, subColor, isDark),
        ),
      ]),
    );
  }

  Widget _buildError(Color subColor) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 52),
    const SizedBox(height: 14),
    const Text('Failed to load Trash', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.error)),
    const SizedBox(height: 8),
    Text(_error ?? '', style: TextStyle(color: subColor, fontSize: 13)),
    const SizedBox(height: 18),
    ElevatedButton.icon(icon: const Icon(Icons.refresh_rounded), label: const Text('Retry'), onPressed: _loadTrash),
  ]));

  Widget _buildEmpty(bool isDark, Color textColor, Color subColor) => Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(
      width: 88, height: 88,
      decoration: BoxDecoration(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04), shape: BoxShape.circle),
      child: const Icon(Icons.delete_outline_rounded, size: 48, color: Colors.grey),
    ),
    const SizedBox(height: 20),
    Text('Trash is Empty', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: textColor)),
    const SizedBox(height: 8),
    Text('Deleted items appear here.\nYou can restore them or permanently delete them.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: subColor, height: 1.5)),
    const SizedBox(height: 6),
    Text('\u0633\u0644\u0629 \u0627\u0644\u0645\u062d\u0630\u0648\u0641\u0627\u062a \u0641\u0627\u0631\u063a\u0629', style: TextStyle(fontSize: 12, color: subColor.withValues(alpha: 0.55))),
  ])));

  Widget _buildList(Color cardColor, Color textColor, Color subColor, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _items.length,
      itemBuilder: (ctx, i) {
        final item = _items[i] as Map<String, dynamic>;
        final it = item['item_type'] as String? ?? 'unknown';
        final icon = _typeIcons[it] ?? Icons.help_outline_rounded;
        final tc = _typeColors[it] ?? AppColors.primary;
        final tl = _typeLabels[it] ?? it;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: tc.withValues(alpha: 0.18)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.04), blurRadius: 5, offset: const Offset(0, 2))],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: tc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: tc, size: 21),
            ),
            title: Text(item['item_name'] as String? ?? '\u2014', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: tc.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
                  child: Text(tl, style: TextStyle(fontSize: 10, color: tc, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(item['module'] as String? ?? '', style: TextStyle(fontSize: 10, color: subColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.access_time_rounded, size: 10, color: subColor),
                const SizedBox(width: 3),
                Text(_fmtDate(item['deleted_at'] as String?), style: TextStyle(fontSize: 10, color: subColor)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.person_outline_rounded, size: 10, color: subColor),
                const SizedBox(width: 3),
                Flexible(child: Text('By: ${item['deleted_by'] ?? '\u2014'}', style: TextStyle(fontSize: 10, color: subColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ]),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              _Btn(icon: Icons.restore_rounded, color: AppColors.success, tip: 'Restore', onTap: () => _restore(item)),
              const SizedBox(width: 6),
              _Btn(icon: Icons.delete_forever_rounded, color: AppColors.error, tip: 'Delete Permanently', onTap: () => _permanentDelete(item)),
            ]),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tip;
  final VoidCallback onTap;
  const _Btn({required this.icon, required this.color, required this.tip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 19),
      ),
    ),
  );
}

