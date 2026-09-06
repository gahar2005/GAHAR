// ─── Compliance Score Model ───────────────────────────────────────────────────
class ChapterComplianceScore {
  final String chapterCode; // GSR, PCC, SAS, MSS, HRM, MIS, IPC, FMS
  final String chapterName;
  final String chapterArabicName;
  int score; // 0 - 100
  DateTime lastUpdated;

  ChapterComplianceScore({
    required this.chapterCode,
    required this.chapterName,
    required this.chapterArabicName,
    this.score = 0,
    required this.lastUpdated,
  });

  Map<String, dynamic> toJson() => {
        'chapterCode': chapterCode,
        'chapterName': chapterName,
        'chapterArabicName': chapterArabicName,
        'score': score,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory ChapterComplianceScore.fromJson(Map<String, dynamic> json) =>
      ChapterComplianceScore(
        chapterCode: json['chapterCode'] as String,
        chapterName: json['chapterName'] as String,
        chapterArabicName: json['chapterArabicName'] as String? ?? '',
        score: json['score'] as int? ?? 0,
        lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      );
}
