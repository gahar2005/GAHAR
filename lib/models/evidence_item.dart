// ─── Evidence Item Model ──────────────────────────────────────────────────────
class EvidenceItem {
  final String id;
  final String standardCode; // e.g. IPC.01
  final String label;
  final String category; // Governance, Meeting Minutes, Training, Log, KPI
  bool isCompleted;
  DateTime? completedAt;
  String notes;

  EvidenceItem({
    required this.id,
    required this.standardCode,
    required this.label,
    required this.category,
    this.isCompleted = false,
    this.completedAt,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'standardCode': standardCode,
        'label': label,
        'category': category,
        'isCompleted': isCompleted,
        'completedAt': completedAt?.toIso8601String(),
        'notes': notes,
      };

  factory EvidenceItem.fromJson(Map<String, dynamic> json) => EvidenceItem(
        id: json['id'] as String,
        standardCode: json['standardCode'] as String? ?? 'GENERAL',
        label: json['label'] as String,
        category: json['category'] as String? ?? 'General',
        isCompleted: json['isCompleted'] as bool? ?? false,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
        notes: json['notes'] as String? ?? '',
      );
}
