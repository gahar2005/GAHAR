library sat_models;

/// SAT (Self-Assessment Tool) data models
/// Source: Hospital Full Accreditation SAT 2025 Excel Workbook

enum SATScoreStatus {
  fullyMet('FULLY_MET', 'Fully Met', 100),
  partiallyMet('PARTIALLY_MET', 'Partially Met', 50),
  notMet('NOT_MET', 'Not Met', 0),
  notApplicable('NOT_APPLICABLE', 'Not Applicable', null),
  notAssessed('NOT_ASSESSED', 'Not Assessed', null);

  final String value;
  final String label;
  final int? numericValue;

  const SATScoreStatus(this.value, this.label, this.numericValue);

  static SATScoreStatus fromString(String? val) {
    if (val == null) return SATScoreStatus.notAssessed;
    switch (val.toUpperCase()) {
      case 'FULLY_MET':
      case 'FULLY MET':
      case 'MET':
        return SATScoreStatus.fullyMet;
      case 'PARTIALLY_MET':
      case 'PARTIALLY MET':
        return SATScoreStatus.partiallyMet;
      case 'NOT_MET':
      case 'NOT MET':
        return SATScoreStatus.notMet;
      case 'NOT_APPLICABLE':
      case 'NOT APPLICABLE':
      case 'NA':
      case 'N/A':
        return SATScoreStatus.notApplicable;
      default:
        return SATScoreStatus.notAssessed;
    }
  }
}

class SATStandard {
  final String id;
  final String standardCode;
  final String standardTitle;
  final String category;
  final String subcategory;
  final String bookReferenceCode;
  final String workbookSheet;
  final int sortOrder;
  final String chapterCode;
  final String chapterTitle;
  final bool isEssential;
  final String evidenceRequired;
  final bool isActive;

  const SATStandard({
    required this.id,
    required this.standardCode,
    required this.standardTitle,
    required this.category,
    required this.subcategory,
    required this.bookReferenceCode,
    required this.workbookSheet,
    required this.sortOrder,
    required this.chapterCode,
    required this.chapterTitle,
    this.isEssential = false,
    this.evidenceRequired = '',
    this.isActive = true,
  });

  factory SATStandard.fromJson(Map<String, dynamic> json) {
    return SATStandard(
      id: json['id']?.toString() ?? '',
      standardCode: json['standard_code']?.toString() ?? '',
      standardTitle: json['standard_title']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      subcategory: json['subcategory']?.toString() ?? '',
      bookReferenceCode: json['book_reference_code']?.toString() ?? '',
      workbookSheet: json['workbook_sheet']?.toString() ?? 'GSR',
      sortOrder: (json['sort_order'] is num) ? (json['sort_order'] as num).toInt() : 0,
      chapterCode: json['chapter_code']?.toString() ?? 'GSR',
      chapterTitle: json['chapter_title']?.toString() ?? 'General Safety Requirements',
      isEssential: json['is_essential'] == true,
      evidenceRequired: json['evidence_required']?.toString() ?? '',
      isActive: json['is_active'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'standard_code': standardCode,
      'standard_title': standardTitle,
      'category': category,
      'subcategory': subcategory,
      'book_reference_code': bookReferenceCode,
      'workbook_sheet': workbookSheet,
      'sort_order': sortOrder,
      'chapter_code': chapterCode,
      'chapter_title': chapterTitle,
      'is_essential': isEssential,
      'evidence_required': evidenceRequired,
      'is_active': isActive,
    };
  }
}

class SATScore {
  final String? id;
  final String facilityId;
  final String standardCode;
  final SATScoreStatus scoreStatus;
  final int? numericScore;
  final String notes;
  final String? updatedBy;
  final DateTime? updatedAt;

  const SATScore({
    this.id,
    required this.facilityId,
    required this.standardCode,
    required this.scoreStatus,
    this.numericScore,
    this.notes = '',
    this.updatedBy,
    this.updatedAt,
  });

  factory SATScore.fromJson(Map<String, dynamic> json) {
    final statusStr = json['score_status']?.toString();
    final status = SATScoreStatus.fromString(statusStr);
    return SATScore(
      id: json['id']?.toString(),
      facilityId: json['facility_id']?.toString() ?? '',
      standardCode: json['standard_code']?.toString() ?? '',
      scoreStatus: status,
      numericScore: (json['numeric_score'] is num)
          ? (json['numeric_score'] as num).toInt()
          : status.numericValue,
      notes: json['notes']?.toString() ?? '',
      updatedBy: json['updated_by']?.toString(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'facility_id': facilityId,
      'standard_code': standardCode,
      'score_status': scoreStatus.value,
      'numeric_score': numericScore ?? scoreStatus.numericValue,
      'notes': notes,
      if (updatedBy != null) 'updated_by': updatedBy,
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  SATScore copyWith({
    SATScoreStatus? scoreStatus,
    int? numericScore,
    String? notes,
  }) {
    return SATScore(
      id: id,
      facilityId: facilityId,
      standardCode: standardCode,
      scoreStatus: scoreStatus ?? this.scoreStatus,
      numericScore: numericScore ?? this.numericScore,
      notes: notes ?? this.notes,
      updatedBy: updatedBy,
      updatedAt: DateTime.now(),
    );
  }
}

class SATChapterSummary {
  final String chapterCode;
  final String chapterTitle;
  final int totalStandards;
  final int assessedStandards;
  final int fullyMet;
  final int partiallyMet;
  final int notMet;
  final int notApplicable;
  final double scorePercentage;

  const SATChapterSummary({
    required this.chapterCode,
    required this.chapterTitle,
    required this.totalStandards,
    required this.assessedStandards,
    required this.fullyMet,
    required this.partiallyMet,
    required this.notMet,
    required this.notApplicable,
    required this.scorePercentage,
  });

  factory SATChapterSummary.fromJson(Map<String, dynamic> json) {
    return SATChapterSummary(
      chapterCode: json['chapter_code']?.toString() ?? json['chapterCode']?.toString() ?? '',
      chapterTitle: json['chapter_title']?.toString() ?? json['chapterTitle']?.toString() ?? '',
      totalStandards: (json['total_standards'] ?? json['totalStandards'] ?? 0) as int,
      assessedStandards: (json['assessed_standards'] ?? json['assessedStandards'] ?? 0) as int,
      fullyMet: (json['fully_met'] ?? json['fullyMet'] ?? 0) as int,
      partiallyMet: (json['partially_met'] ?? json['partiallyMet'] ?? 0) as int,
      notMet: (json['not_met'] ?? json['notMet'] ?? 0) as int,
      notApplicable: (json['not_applicable'] ?? json['notApplicable'] ?? 0) as int,
      scorePercentage: ((json['score_percentage'] ?? json['scorePercentage'] ?? 0) as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chapter_code': chapterCode,
      'chapter_title': chapterTitle,
      'total_standards': totalStandards,
      'assessed_standards': assessedStandards,
      'fully_met': fullyMet,
      'partially_met': partiallyMet,
      'not_met': notMet,
      'not_applicable': notApplicable,
      'score_percentage': scorePercentage,
    };
  }
}

class SATAssessmentReport {
  final String facilityId;
  final String facilityName;
  final DateTime assessmentDate;
  final double overallScore;
  final int totalStandards;
  final int assessedStandards;
  final double completionRate;
  final List<SATChapterSummary> chapterSummaries;
  final Map<String, int> statusDistribution;

  const SATAssessmentReport({
    required this.facilityId,
    required this.facilityName,
    required this.assessmentDate,
    required this.overallScore,
    required this.totalStandards,
    required this.assessedStandards,
    required this.completionRate,
    required this.chapterSummaries,
    required this.statusDistribution,
  });

  factory SATAssessmentReport.fromJson(Map<String, dynamic> json) {
    final chaptersRaw = json['chapter_summaries'] ?? json['chapterSummaries'] ?? [];
    final chapters = (chaptersRaw as List)
        .map((e) => SATChapterSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final distRaw = json['status_distribution'] ?? json['statusDistribution'] ?? {};
    final dist = Map<String, int>.from(
      (distRaw as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
    );

    return SATAssessmentReport(
      facilityId: json['facility_id']?.toString() ?? '',
      facilityName: json['facility_name']?.toString() ?? 'Hospital Facility',
      assessmentDate: json['assessment_date'] != null
          ? DateTime.tryParse(json['assessment_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      overallScore: ((json['overall_score'] ?? json['overallScore'] ?? 0) as num).toDouble(),
      totalStandards: (json['total_standards'] ?? json['totalStandards'] ?? 0) as int,
      assessedStandards: (json['assessed_standards'] ?? json['assessedStandards'] ?? 0) as int,
      completionRate: ((json['completion_rate'] ?? json['completionRate'] ?? 0) as num).toDouble(),
      chapterSummaries: chapters,
      statusDistribution: dist,
    );
  }
}

// =============================================================================
// Sub-Evidence / Measurement Item Models
// Implements the actual Excel row-level scoring hierarchy:
// Chapter → Standard → Sub-Evidence Row → Score 0/1/2
// =============================================================================

/// A single evidence / measurement row within a standard.
/// Source: Excel column D (scored 0, 1, or 2)
class SATSubEvidenceItem {
  final String id;
  final String standardCode;
  final int itemNumber;
  final String requirementText;
  final String? documentsRequired;
  final String? interviewRequired;
  final String? observationRequired;
  final int sortOrder;

  const SATSubEvidenceItem({
    required this.id,
    required this.standardCode,
    required this.itemNumber,
    required this.requirementText,
    this.documentsRequired,
    this.interviewRequired,
    this.observationRequired,
    this.sortOrder = 0,
  });

  factory SATSubEvidenceItem.fromJson(Map<String, dynamic> json) {
    return SATSubEvidenceItem(
      id: json['id']?.toString() ?? '',
      standardCode: json['standard_code']?.toString() ?? '',
      itemNumber: (json['item_number'] as num? ?? 0).toInt(),
      requirementText: json['requirement_text']?.toString() ?? '',
      documentsRequired: json['documents_required']?.toString(),
      interviewRequired: json['interview_required']?.toString(),
      observationRequired: json['observation_required']?.toString(),
      sortOrder: (json['sort_order'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'standard_code': standardCode,
    'item_number': itemNumber,
    'requirement_text': requirementText,
    'documents_required': documentsRequired,
    'interview_required': interviewRequired,
    'observation_required': observationRequired,
    'sort_order': sortOrder,
  };
}

/// Score for a single evidence item — values: '0', '1', '2', or 'N/A'
class SATSubScore {
  final String facilityId;
  final String evidenceId;
  final String standardCode;
  final String scoreValue; // '0' | '1' | '2' | 'N/A'
  final String? notes;
  final DateTime? updatedAt;

  const SATSubScore({
    required this.facilityId,
    required this.evidenceId,
    required this.standardCode,
    required this.scoreValue,
    this.notes,
    this.updatedAt,
  });

  factory SATSubScore.fromJson(Map<String, dynamic> json) {
    return SATSubScore(
      facilityId: json['facility_id']?.toString() ?? '',
      evidenceId: json['evidence_id']?.toString() ?? '',
      standardCode: json['standard_code']?.toString() ?? '',
      scoreValue: json['score_value']?.toString() ?? 'N/A',
      notes: json['notes']?.toString(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'facility_id': facilityId,
    'evidence_id': evidenceId,
    'standard_code': standardCode,
    'score_value': scoreValue,
    'notes': notes,
  };
}

/// Result of calculating a standard's score from its sub-evidence rows.
/// Implements Excel formula: SUM(scores) / (COUNT(scored_items) × 2)
/// N/A items are excluded from denominator.
class SATSubEvidenceCalculation {
  final String standardCode;
  final int? percentage;       // null = N/A
  final String percentageDisplay; // e.g. '75%' or 'N/A'
  final String rating;            // 'MET' | 'PARTIAL MET' | 'NOT MET' | 'N/A'
  final int scoredItems;
  final int totalItems;
  final int sumScores;
  final int maxPossible;

  const SATSubEvidenceCalculation({
    required this.standardCode,
    required this.percentage,
    required this.percentageDisplay,
    required this.rating,
    required this.scoredItems,
    required this.totalItems,
    required this.sumScores,
    required this.maxPossible,
  });

  factory SATSubEvidenceCalculation.fromJson(Map<String, dynamic> json) {
    return SATSubEvidenceCalculation(
      standardCode: json['standard_code']?.toString() ?? '',
      percentage: json['percentage'] != null ? (json['percentage'] as num).toInt() : null,
      percentageDisplay: json['percentage_display']?.toString() ?? 'N/A',
      rating: json['rating']?.toString() ?? 'N/A',
      scoredItems: (json['scored_items'] as num? ?? 0).toInt(),
      totalItems: (json['total_items'] as num? ?? 0).toInt(),
      sumScores: (json['sum_scores'] as num? ?? 0).toInt(),
      maxPossible: (json['max_possible'] as num? ?? 0).toInt(),
    );
  }

  /// Local calculation — mirrors the Excel/backend formula exactly
  static SATSubEvidenceCalculation calculate({
    required String standardCode,
    required List<SATSubScore> subScores,
  }) {
    final scorable = subScores.where((s) => s.scoreValue != 'N/A').toList();
    if (scorable.isEmpty) {
      return SATSubEvidenceCalculation(
        standardCode: standardCode,
        percentage: null,
        percentageDisplay: 'N/A',
        rating: 'N/A',
        scoredItems: 0,
        totalItems: subScores.length,
        sumScores: 0,
        maxPossible: 0,
      );
    }
    final sum = scorable.fold(0, (acc, s) => acc + (int.tryParse(s.scoreValue) ?? 0));
    final maxPossible = scorable.length * 2;
    final pct = maxPossible > 0 ? (sum / maxPossible) : 0.0;
    final pctRounded = (pct * 100).round();
    final String rating;
    if (pct >= 0.80) {
      rating = 'MET';
    } else if (pct >= 0.50) {
      rating = 'PARTIAL MET';
    } else {
      rating = 'NOT MET';
    }
    return SATSubEvidenceCalculation(
      standardCode: standardCode,
      percentage: pctRounded,
      percentageDisplay: '$pctRounded%',
      rating: rating,
      scoredItems: scorable.length,
      totalItems: subScores.length,
      sumScores: sum,
      maxPossible: maxPossible,
    );
  }
}
