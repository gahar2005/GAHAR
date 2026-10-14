import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/saved_document.dart';
import '../services/api_service.dart';
import '../services/export_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class DocumentLibraryScreen extends StatefulWidget {
  const DocumentLibraryScreen({super.key});

  @override
  State<DocumentLibraryScreen> createState() => _DocumentLibraryScreenState();
}

class _DocumentLibraryScreenState extends State<DocumentLibraryScreen> {
  List<SavedDocument> _documents = [];
  bool _loading = true;
  String _searchQuery = '';
  String _selectedCategory = 'All';
  bool _showOnlyFavorites = false;

  final List<String> _categories = [
    'All',
    'Policy',
    'Plan',
    'Program',
    'Procedure',
    'SOP',
    'Risk Assessment',
    'Training Plan',
    'Audit Plan',
  ];

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _loading = true);
    final docs = await StorageService.getSavedDocuments();
    setState(() {
      _documents = docs;
      _loading = false;
    });
  }

  List<SavedDocument> get _filteredDocuments {
    return _documents.where((doc) {
      final matchesQuery = _searchQuery.isEmpty ||
          doc.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          doc.standard.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          doc.content.toLowerCase().contains(_searchQuery.toLowerCase());

      final matchesCategory = _selectedCategory == 'All' ||
          doc.docType.toLowerCase().contains(_selectedCategory.toLowerCase());

      final matchesFav = !_showOnlyFavorites || doc.isFavorite;

      return matchesQuery && matchesCategory && matchesFav;
    }).toList();
  }

  Future<void> _toggleFavorite(SavedDocument doc) async {
    await StorageService.toggleFavoriteDocument(doc.id);
    _loadDocuments();
  }

  Future<void> _deleteDoc(SavedDocument doc) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Move this document to Recycle Bin?'),
          ],
        ),
        content: Text('Are you sure you want to move "${doc.title}" to the Recycle Bin? You can restore it later at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            icon: const Icon(Icons.delete_rounded),
            label: const Text('Move to Recycle Bin'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageService.softDeleteDocument(doc.id);
      try {
        await ApiService.deleteDocument(doc.id);
      } catch (_) {}
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Moved "${doc.title}" to Recycle Bin.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      _loadDocuments();
    }
  }

  void _editDoc(SavedDocument doc) {
    final titleController = TextEditingController(text: doc.title);
    final contentController = TextEditingController(text: doc.content);
    String currentStatus = doc.status;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Edit Document'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Document Title'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: currentStatus,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'Draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'Under Review', child: Text('Under Review')),
                    DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                  ],
                  onChanged: (v) => setDlgState(() => currentStatus = v ?? currentStatus),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Content',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updatedDoc = SavedDocument(
                  id: doc.id,
                  facilityId: doc.facilityId,
                  title: titleController.text.trim().isEmpty ? doc.title : titleController.text.trim(),
                  content: contentController.text,
                  docType: doc.docType,
                  standard: doc.standard,
                  department: doc.department,
                  version: doc.version,
                  status: currentStatus,
                  author: doc.author,
                  reviewedBy: doc.reviewedBy,
                  approvedBy: doc.approvedBy,
                  createdAt: doc.createdAt,
                  lastModified: DateTime.now(),
                  isFavorite: doc.isFavorite,
                  versionHistory: [
                    ...doc.versionHistory,
                    DocumentVersionHistory(
                      version: doc.version,
                      content: doc.content,
                      modifiedBy: 'User',
                      modifiedAt: DateTime.now(),
                      changeNotes: 'Edited in Document Library',
                    ),
                  ],
                );
                final nav = Navigator.of(ctx);
                final messenger2 = ScaffoldMessenger.of(context);
                await StorageService.saveDocument(updatedDoc);
                if (mounted) {
                  nav.pop();
                  _loadDocuments();
                  messenger2.showSnackBar(
                    SnackBar(content: Text('Updated "${updatedDoc.title}"')),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _viewDocumentDetail(SavedDocument doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF16162A) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.description_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          doc.title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          doc.isFavorite
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: Colors.amber,
                        ),
                        onPressed: () {
                          _toggleFavorite(doc);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Export action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () =>
                            ExportService.sharePdf(doc.title, doc.content),
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                        label: const Text('Export PDF', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white),
                      ),
                      ElevatedButton.icon(
                        onPressed: () =>
                            ExportService.shareWordDoc(doc.title, doc.content),
                        icon: const Icon(Icons.article_rounded, size: 16),
                        label: const Text('Word (.doc)', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white),
                      ),
                      ElevatedButton.icon(
                        onPressed: () =>
                            ExportService.printDocument(doc.title, doc.content),
                        icon: const Icon(Icons.print_rounded, size: 16),
                        label: const Text('Print', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: SelectableText(
                        doc.content,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docs = _filteredDocuments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Library'),
        actions: [
          IconButton(
            icon: Icon(_showOnlyFavorites
                ? Icons.star_rounded
                : Icons.star_outline_rounded),
            color: _showOnlyFavorites ? Colors.amber : null,
            onPressed: () =>
                setState(() => _showOnlyFavorites = !_showOnlyFavorites),
            tooltip: 'Filter Favorites',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadDocuments,
            tooltip: 'Refresh Library',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search saved documents & standards...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor:
                    isDark ? const Color(0xFF16162A) : const Color(0xFFF3F3FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // Category Chips
          SizedBox(
            height: 40,
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
                    label: Text(cat, style: const TextStyle(fontSize: 11.5)),
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
                : docs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open_rounded,
                                size: 54,
                                color: isDark ? Colors.white24 : Colors.black26),
                            const SizedBox(height: 12),
                            Text(
                              'No documents found in Library',
                              style: TextStyle(
                                  color:
                                      isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black45),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Generate policies or SOPs in the Assistant and tap "Save to Library"',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    cs.primary.withValues(alpha: 0.15),
                                child: Icon(Icons.description_rounded,
                                    color: cs.primary),
                              ),
                              title: Text(
                                doc.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              subtitle: Text(
                                '${doc.docType.toUpperCase()} • ${DateFormat('yyyy-MM-dd').format(doc.createdAt)}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      doc.isFavorite
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: Colors.amber,
                                    ),
                                    tooltip: 'Favorite',
                                    onPressed: () => _toggleFavorite(doc),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.visibility_outlined, size: 20),
                                    tooltip: 'Open',
                                    onPressed: () => _viewDocumentDetail(doc),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    tooltip: 'Edit',
                                    onPressed: () => _editDoc(doc),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded,
                                        color: AppColors.error, size: 20),
                                    tooltip: 'Move to Recycle Bin',
                                    onPressed: () => _deleteDoc(doc),
                                  ),
                                ],
                              ),
                              onTap: () => _viewDocumentDetail(doc),
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
