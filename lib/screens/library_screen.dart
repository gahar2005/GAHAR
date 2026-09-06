import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/saved_document.dart';
import '../services/export_service.dart';
import '../services/storage_service.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Are you sure you want to delete "${doc.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageService.deleteDocument(doc.id);
      _loadDocuments();
    }
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
                                    onPressed: () => _toggleFavorite(doc),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded,
                                        size: 20),
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
