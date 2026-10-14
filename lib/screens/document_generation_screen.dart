import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api_service.dart';
import '../services/export_service.dart';
import '../services/storage_service.dart';
import '../models/saved_document.dart';
import '../theme/app_theme.dart';
import '../widgets/ai_copilot_fab.dart';

class DocumentGenerationScreen extends StatefulWidget {
  const DocumentGenerationScreen({super.key});

  @override
  State<DocumentGenerationScreen> createState() => _DocumentGenerationScreenState();
}

class _DocumentGenerationScreenState extends State<DocumentGenerationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  String? _errorMessage;

  List<dynamic> _catalog = [];
  Map<String, dynamic>? _dashboardData;
  List<SavedDocument> _localDocs = [];
  String _selectedCategory = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final catalog = await ApiService.getDocumentCatalog();
      final dashboard = await ApiService.getDocumentDashboard();
      final local = await StorageService.getSavedDocuments();

      setState(() {
        _catalog = catalog;
        _dashboardData = dashboard;
        _localDocs = local;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load document catalog: $e';
        _loading = false;
      });
    }
  }

  List<dynamic> get _filteredCatalog {
    return _catalog.where((item) {
      final titleEn = (item['titleEn'] ?? '').toString().toLowerCase();
      final titleAr = (item['titleAr'] ?? '').toString().toLowerCase();
      final code = (item['docCode'] ?? '').toString().toLowerCase();
      final std = (item['standardCode'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();

      final matchesQuery = q.isEmpty ||
          titleEn.contains(q) ||
          titleAr.contains(q) ||
          code.contains(q) ||
          std.contains(q);

      final type = (item['docType'] ?? '').toString();
      final matchesCategory = _selectedCategory == 'All' || type == _selectedCategory;

      return matchesQuery && matchesCategory;
    }).toList();
  }

  void _openGenerateDialog(dynamic template) {
    final facilityNameController = TextEditingController(text: 'Cairo International Medical Center');
    final deptController = TextEditingController(text: 'Quality & Accreditation');
    final ownerController = TextEditingController(text: 'Director of Quality');
    final docCodeController = TextEditingController(text: template['docCode'] ?? 'GAHAR-DOC-01');
    final effectiveDateController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final reviewCycleController = TextEditingController(text: '${template['reviewCycleMonths'] ?? 12} Months');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Customize & Generate: ${template['docCode']}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                template['titleEn'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                template['titleAr'] ?? '',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Divider(height: 24),
              TextField(
                controller: facilityNameController,
                decoration: const InputDecoration(labelText: 'Healthcare Facility Name / اسم المنشأة'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: docCodeController,
                      decoration: const InputDecoration(labelText: 'Document Code / كود الوثيقة'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: deptController,
                      decoration: const InputDecoration(labelText: 'Department / القسم'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ownerController,
                      decoration: const InputDecoration(labelText: 'Document Owner / المسؤول'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: effectiveDateController,
                      decoration: const InputDecoration(labelText: 'Effective Date / تاريخ السريان'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reviewCycleController,
                decoration: const InputDecoration(labelText: 'Review Cycle / دورة المراجعة'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _executeGeneration(
                docCode: template['docCode'],
                title: template['titleEn'],
                docType: template['docType'],
                standard: template['standardCode'],
                customization: {
                  'facilityName': facilityNameController.text,
                  'department': deptController.text,
                  'documentOwner': ownerController.text,
                  'docCode': docCodeController.text,
                  'effectiveDate': effectiveDateController.text,
                  'reviewCycle': reviewCycleController.text,
                },
              );
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate AI Draft'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeGeneration({
    required String docCode,
    required String title,
    required String docType,
    required String standard,
    required Map<String, dynamic> customization,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generating compliant GAHAR draft with AI...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final res = await ApiService.generateDocumentDraft(docCode, customization);
      if (mounted) Navigator.pop(context); // Close loading

      if (res['success'] == true && res['draft'] != null) {
        final draftText = res['draft']['content'] as String? ?? '';
        final newDoc = SavedDocument(
          id: 'doc_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          content: draftText,
          docType: docType,
          standard: standard,
          department: customization['department'] ?? 'Quality',
          version: 'v1.0',
          status: 'Draft',
          author: 'AI Grounded Generator & Quality Team',
          createdAt: DateTime.now(),
        );

        await StorageService.saveDocument(newDoc);
        await _loadData();

        if (mounted) {
          _openDocumentEditor(newDoc);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Generation failed'), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _openDocumentEditor(SavedDocument doc) {
    final titleController = TextEditingController(text: doc.title);
    final contentController = TextEditingController(text: doc.content);
    final changeSummaryController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${doc.docType.toUpperCase()} • ${doc.standard}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentGold.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        doc.version,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF8C6D1F)),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(doc.status).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        doc.status.toUpperCase(),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: _getStatusColor(doc.status)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Document Title'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: contentController,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
                    decoration: InputDecoration(
                      labelText: 'Document Policy & Procedure Body / متن السياسة والإجراءات',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Action Buttons
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      tooltip: 'Export PDF',
                      onPressed: () {
                        ExportService.exportToPdf(
                          title: titleController.text,
                          content: contentController.text,
                          documentType: doc.docType,
                          standard: doc.standard,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.description_rounded),
                      tooltip: 'Export Formatted Word/Text',
                      onPressed: () {
                        ExportService.exportToWord(
                          title: titleController.text,
                          content: contentController.text,
                          documentType: doc.docType,
                          standard: doc.standard,
                        );
                      },
                    ),
                    const Spacer(),
                    // Governance Workflow Buttons
                    if (doc.status == 'Draft' || doc.status == 'Revision Required')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
                        onPressed: () async {
                          doc.status = 'Under Review';
                          await StorageService.updateDocumentStatus(doc.id, 'Under Review');
                          setSheetState(() {});
                          await _loadData();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Document submitted for Quality Committee review!')),
                            );
                          }
                        },
                        icon: const Icon(Icons.send_rounded, size: 16),
                        label: const Text('Submit for Review'),
                      ),
                    if (doc.status == 'Under Review' || doc.status == 'Pending Approval') ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                        onPressed: () async {
                          doc.status = 'Revision Required';
                          await StorageService.updateDocumentStatus(doc.id, 'Revision Required');
                          setSheetState(() {});
                          await _loadData();
                        },
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: const Text('Request Revision'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                        onPressed: () async {
                          doc.status = 'Approved';
                          await StorageService.updateDocumentStatus(doc.id, 'Approved');
                          setSheetState(() {});
                          await _loadData();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Document officially APPROVED by Quality Committee!')),
                            );
                          }
                        },
                        icon: const Icon(Icons.verified_rounded, size: 16),
                        label: const Text('Approve Document'),
                      ),
                    ],
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                      onPressed: () async {
                        // Prompt for change summary
                        final changeNote = await showDialog<String>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Save New Version'),
                            content: TextField(
                              controller: changeSummaryController,
                              decoration: const InputDecoration(
                                labelText: 'Change Summary / ملاحظات التعديل',
                                hintText: 'e.g. Added two identifiers verification procedure',
                              ),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, changeSummaryController.text),
                                child: const Text('Save Version'),
                              ),
                            ],
                          ),
                        );

                        if (changeNote != null) {
                          // Version increment
                          final vNum = double.tryParse(doc.version.replaceAll('v', '')) ?? 1.0;
                          final nextVersion = 'v${(vNum + 0.1).toStringAsFixed(1)}';

                          final updatedDoc = SavedDocument(
                            id: doc.id,
                            facilityId: doc.facilityId,
                            title: titleController.text,
                            content: contentController.text,
                            docType: doc.docType,
                            standard: doc.standard,
                            department: doc.department,
                            version: nextVersion,
                            status: doc.status,
                            author: doc.author,
                            createdAt: doc.createdAt,
                            lastModified: DateTime.now(),
                            versionHistory: [
                              ...doc.versionHistory,
                              DocumentVersionHistory(
                                version: doc.version,
                                content: doc.content,
                                modifiedBy: 'Quality Team',
                                modifiedAt: DateTime.now(),
                                changeNotes: changeNote.isEmpty ? 'Version update' : changeNote,
                              ),
                            ],
                          );

                          await StorageService.saveDocument(updatedDoc);
                          await _loadData();
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Saved as $nextVersion!'), backgroundColor: AppColors.success),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: const Text('Save Changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppColors.success;
      case 'under review':
      case 'pending approval':
        return AppColors.warning;
      case 'revision required':
      case 'rejected':
        return AppColors.error;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AICopilotFAB(
      currentScreenName: 'Document Generation',
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GAHAR Document Generation Engine',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                'توليد وتخصيص السياسات والإجراءات واللوائح المعتمدة',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.library_books_rounded), text: 'Templates Catalog / النماذج'),
              Tab(icon: Icon(Icons.pie_chart_rounded), text: 'Coverage Dashboard / التغطية'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text(_errorMessage!),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
                      ],
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCatalogTab(),
                      _buildDashboardTab(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildCatalogTab() {
    return Column(
      children: [
        // Search & Filter Bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search templates by code, title, standard... (e.g. GSR.01)',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['All', 'Policy', 'Procedure', 'Form', 'Checklist', 'Plan'].map((cat) {
                    final isSelected = _selectedCategory == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(cat),
                        selectedColor: AppColors.primary.withOpacity(0.2),
                        checkmarkColor: AppColors.primary,
                        onSelected: (val) => setState(() => _selectedCategory = cat),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _filteredCatalog.isEmpty
              ? const Center(child: Text('No templates matching filters'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: _filteredCatalog.length,
                  itemBuilder: (context, index) {
                    final item = _filteredCatalog[index];
                    final isApplicable = item['isApplicable'] != false;
                    final docCode = item['docCode'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: isApplicable ? AppColors.primary.withOpacity(0.12) : Colors.grey.shade200,
                          child: Icon(
                            item['docType'] == 'Form' ? Icons.assignment_rounded : Icons.description_rounded,
                            color: isApplicable ? AppColors.primary : Colors.grey,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              docCode,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isApplicable ? AppColors.success.withOpacity(0.1) : Colors.grey.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isApplicable ? 'APPLICABLE' : 'EXCLUDED (N/A)',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isApplicable ? AppColors.success : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          item['titleEn'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['titleAr'] ?? '',
                                  textDirection: TextDirection.rtl,
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  item['descriptionEn'] ?? '',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 12),
                                if (item['mandatorySections'] is List) ...[
                                  const Text(
                                    'Mandatory GAHAR Sections / الأقسام الإلزامية:',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: (item['mandatorySections'] as List)
                                        .map((sec) => Chip(
                                              label: Text(sec.toString(), style: const TextStyle(fontSize: 10)),
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                            ))
                                        .toList(),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => _openGenerateDialog(item),
                                      icon: const Icon(Icons.auto_awesome, size: 16),
                                      label: const Text('Generate Document / توليد الوثيقة'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDashboardTab() {
    final d = _dashboardData?['dashboard'] ?? {};
    final totalDocs = d['totalCatalogDocuments'] ?? _catalog.length;
    final generated = _localDocs.length;
    final approved = _localDocs.where((doc) => doc.status.toLowerCase() == 'approved').length;
    final underReview = _localDocs.where((doc) => doc.status.toLowerCase() == 'under review').length;
    final draft = _localDocs.where((doc) => doc.status.toLowerCase() == 'draft').length;
    final coveragePct = totalDocs > 0 ? ((generated / totalDocs) * 100).clamp(0, 100).toStringAsFixed(0) : '0';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Hero Progress Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFF00796B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.fact_check_rounded, color: Colors.white, size: 28),
                  SizedBox(width: 10),
                  Text(
                    'DOCUMENTATION READINESS',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$coveragePct%',
                    style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Coverage ($generated of $totalDocs Documents Generated)',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: totalDocs > 0 ? (generated / totalDocs).clamp(0.0, 1.0) : 0.0,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accentGold),
                  minHeight: 10,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Status Breakdown
        const Text(
          'Document Lifecycle Status / حالة دورة حياة الوثائق',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildLifecycleCard(
                title: 'Draft',
                count: '$draft',
                color: Colors.blueGrey,
                icon: Icons.edit_note_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildLifecycleCard(
                title: 'In Review',
                count: '$underReview',
                color: AppColors.warning,
                icon: Icons.pending_actions_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildLifecycleCard(
                title: 'Approved',
                count: '$approved',
                color: AppColors.success,
                icon: Icons.verified_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Generated Documents List
        const Text(
          'Active Facility Documents / الوثائق النشطة للمنشأة',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_localDocs.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text('No documents generated yet. Use the catalog tab to generate GAHAR policies.'),
          )
        else
          ..._localDocs.map((doc) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(doc.status).withOpacity(0.12),
                    child: Icon(Icons.article_rounded, color: _getStatusColor(doc.status), size: 20),
                  ),
                  title: Text(doc.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('${doc.standard} • ${doc.version} • ${doc.department}'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(doc.status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      doc.status,
                      style: TextStyle(color: _getStatusColor(doc.status), fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                  onTap: () => _openDocumentEditor(doc),
                ),
              )),
      ],
    );
  }

  Widget _buildLifecycleCard({
    required String title,
    required String count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(count, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
