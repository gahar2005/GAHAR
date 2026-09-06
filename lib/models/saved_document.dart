// ─── Saved Document Model with Version History ──────────────────────────────────
class DocumentVersionHistory {
  final String version;
  final String content;
  final String modifiedBy;
  final DateTime modifiedAt;
  final String changeNotes;

  DocumentVersionHistory({
    required this.version,
    required this.content,
    required this.modifiedBy,
    required this.modifiedAt,
    required this.changeNotes,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'content': content,
        'modifiedBy': modifiedBy,
        'modifiedAt': modifiedAt.toIso8601String(),
        'changeNotes': changeNotes,
      };

  factory DocumentVersionHistory.fromJson(Map<String, dynamic> json) =>
      DocumentVersionHistory(
        version: json['version'] ?? 'v1.0',
        content: json['content'] ?? '',
        modifiedBy: json['modifiedBy'] ?? 'AI Generator',
        modifiedAt: json['modifiedAt'] != null
            ? DateTime.parse(json['modifiedAt'])
            : DateTime.now(),
        changeNotes: json['changeNotes'] ?? 'Initial Draft',
      );
}

class SavedDocument {
  final String id;
  final String facilityId;
  final String title;
  final String content;
  final String docType; // policy, sop, plan, form, riskAssessment, etc.
  final String standard; // e.g. PCC.06
  final String department;
  final String version; // e.g. "v1.0", "v1.1"
  String status; // "Draft", "Under Review", "Approved"
  final String author;
  final String? reviewedBy;
  final String? approvedBy;
  final DateTime createdAt;
  DateTime lastModified;
  bool isFavorite;
  final List<DocumentVersionHistory> versionHistory;

  SavedDocument({
    required this.id,
    this.facilityId = 'default_facility',
    required this.title,
    required this.content,
    required this.docType,
    required this.standard,
    required this.department,
    this.version = 'v1.0',
    this.status = 'Draft',
    this.author = 'AI Assistant & Quality Team',
    this.reviewedBy,
    this.approvedBy,
    required this.createdAt,
    DateTime? lastModified,
    this.isFavorite = false,
    List<DocumentVersionHistory>? versionHistory,
  })  : lastModified = lastModified ?? createdAt,
        versionHistory = versionHistory ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'facilityId': facilityId,
        'title': title,
        'content': content,
        'docType': docType,
        'standard': standard,
        'department': department,
        'version': version,
        'status': status,
        'author': author,
        'reviewedBy': reviewedBy,
        'approvedBy': approvedBy,
        'createdAt': createdAt.toIso8601String(),
        'lastModified': lastModified.toIso8601String(),
        'isFavorite': isFavorite,
        'versionHistory': versionHistory.map((v) => v.toJson()).toList(),
      };

  factory SavedDocument.fromJson(Map<String, dynamic> json) => SavedDocument(
        id: json['id'] as String,
        facilityId: json['facilityId'] as String? ?? 'default_facility',
        title: json['title'] as String,
        content: json['content'] as String,
        docType: json['docType'] as String? ?? 'document',
        standard: json['standard'] as String? ?? '',
        department: json['department'] as String? ?? '',
        version: json['version'] as String? ?? 'v1.0',
        status: json['status'] as String? ?? 'Draft',
        author: json['author'] as String? ?? 'AI Assistant',
        reviewedBy: json['reviewedBy'] as String?,
        approvedBy: json['approvedBy'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastModified: json['lastModified'] != null
            ? DateTime.parse(json['lastModified'] as String)
            : DateTime.parse(json['createdAt'] as String),
        isFavorite: json['isFavorite'] as bool? ?? false,
        versionHistory: (json['versionHistory'] as List<dynamic>?)
                ?.map((item) =>
                    DocumentVersionHistory.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
