enum UserRole {
  superAdmin,
  facilityOwner,
  facilityAdmin,
  qualityManager,
  accreditationManager,
  doctor,
  nurse,
  pharmacist,
  infectionControlOfficer,
  hrManager,
  departmentManager,
  auditor,
  readOnly,
}

extension UserRoleExt on UserRole {
  String get label {
    switch (this) {
      case UserRole.superAdmin:
        return 'Platform Super Admin';
      case UserRole.facilityOwner:
        return 'Facility Owner / مدير المنشأة';
      case UserRole.facilityAdmin:
        return 'Facility Administrator';
      case UserRole.qualityManager:
        return 'Quality Manager / مدير الجودة';
      case UserRole.accreditationManager:
        return 'Accreditation Officer / مسؤول الاعتماد';
      case UserRole.doctor:
        return 'Physician / طبيب';
      case UserRole.nurse:
        return 'Nursing Staff / تمريض';
      case UserRole.pharmacist:
        return 'Pharmacist / صيدلي';
      case UserRole.infectionControlOfficer:
        return 'Infection Control Officer / مكافحة العدوى';
      case UserRole.hrManager:
        return 'HR Manager / الموارد البشرية';
      case UserRole.departmentManager:
        return 'Department Head / رئيس قسم';
      case UserRole.auditor:
        return 'External Auditor / مقيم مراجع';
      case UserRole.readOnly:
        return 'Read Only User / مشاهد فقط';
    }
  }

  bool get isSuperAdmin => this == UserRole.superAdmin;
  bool get canManageUsers =>
      this == UserRole.superAdmin ||
      this == UserRole.facilityOwner ||
      this == UserRole.facilityAdmin;
  bool get canManageFacility =>
      this == UserRole.superAdmin ||
      this == UserRole.facilityOwner ||
      this == UserRole.facilityAdmin ||
      this == UserRole.qualityManager;
}

class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String facilityId;
  final String? department;
  final String? phone;
  final bool isActive;
  final DateTime createdAt;

  UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.facilityId,
    this.department,
    this.phone,
    this.isActive = true,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? '',
      role: UserRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => UserRole.qualityManager,
      ),
      facilityId: json['facilityId'] ?? 'default_facility',
      department: json['department'],
      phone: json['phone'],
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'fullName': fullName,
        'role': role.name,
        'facilityId': facilityId,
        'department': department,
        'phone': phone,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };
}

class FacilityTenant {
  final String id;
  final String name;
  final String type; // Hospital, Primary Care, Lab, Radiology, Specialty Center
  final String governorate;
  final int bedCapacity;
  final List<String> departments;
  final String gaharVersion;
  final DateTime targetSurveyDate;
  final String subscriptionPlan; // Free Trial, Standard, Enterprise
  final String subscriptionStatus; // Active, Pending, Expired
  final DateTime createdAt;

  FacilityTenant({
    required this.id,
    required this.name,
    required this.type,
    required this.governorate,
    required this.bedCapacity,
    required this.departments,
    required this.gaharVersion,
    required this.targetSurveyDate,
    required this.subscriptionPlan,
    required this.subscriptionStatus,
    required this.createdAt,
  });

  factory FacilityTenant.fromJson(Map<String, dynamic> json) {
    return FacilityTenant(
      id: json['id'] ?? 'fac_default',
      name: json['name'] ?? 'Cairo General Hospital',
      type: json['type'] ?? 'Hospital',
      governorate: json['governorate'] ?? 'Cairo',
      bedCapacity: json['bedCapacity'] ?? 150,
      departments: List<String>.from(json['departments'] ?? []),
      gaharVersion: json['gaharVersion'] ?? 'GAHAR 2025 v2',
      targetSurveyDate: json['targetSurveyDate'] != null
          ? DateTime.parse(json['targetSurveyDate'])
          : DateTime.now().add(const Duration(days: 180)),
      subscriptionPlan: json['subscriptionPlan'] ?? 'Standard Hospital',
      subscriptionStatus: json['subscriptionStatus'] ?? 'Active',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'governorate': governorate,
        'bedCapacity': bedCapacity,
        'departments': departments,
        'gaharVersion': gaharVersion,
        'targetSurveyDate': targetSurveyDate.toIso8601String(),
        'subscriptionPlan': subscriptionPlan,
        'subscriptionStatus': subscriptionStatus,
        'createdAt': createdAt.toIso8601String(),
      };
}

enum ApplicabilityStatus { applicable, notApplicable, needsReview }

class ApplicabilityItem {
  final String id;
  final String standardCode; // e.g. GSR.01, PCC.04, SAS.02
  final String chapterCode; // GSR, PCC, SAS, MSS, IPC, HRM, FMS, MIS
  final String title;
  final String arabicTitle;
  final String category;
  ApplicabilityStatus status;
  String? reason;
  String? reviewedBy;
  DateTime? reviewedAt;

  ApplicabilityItem({
    required this.id,
    required this.standardCode,
    required this.chapterCode,
    required this.title,
    required this.arabicTitle,
    required this.category,
    this.status = ApplicabilityStatus.applicable,
    this.reason,
    this.reviewedBy,
    this.reviewedAt,
  });

  factory ApplicabilityItem.fromJson(Map<String, dynamic> json) {
    return ApplicabilityItem(
      id: json['id'] ?? '',
      standardCode: json['standardCode'] ?? '',
      chapterCode: json['chapterCode'] ?? '',
      title: json['title'] ?? '',
      arabicTitle: json['arabicTitle'] ?? '',
      category: json['category'] ?? '',
      status: ApplicabilityStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ApplicabilityStatus.applicable,
      ),
      reason: json['reason'],
      reviewedBy: json['reviewedBy'],
      reviewedAt: json['reviewedAt'] != null
          ? DateTime.parse(json['reviewedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'standardCode': standardCode,
        'chapterCode': chapterCode,
        'title': title,
        'arabicTitle': arabicTitle,
        'category': category,
        'status': status.name,
        'reason': reason,
        'reviewedBy': reviewedBy,
        'reviewedAt': reviewedAt?.toIso8601String(),
      };
}

enum GapSeverity { critical, high, medium, low }
enum GapStatus { notStarted, inProgress, partiallyCompliant, compliant, needsReview }

class GapItem {
  final String id;
  final String facilityId;
  final String standardCode;
  final String chapterCode;
  final String gapTitle;
  final String description;
  final GapSeverity severity;
  GapStatus status;
  final String responsiblePerson;
  final DateTime dueDate;
  final String? actionPlanId;
  final List<String> evidenceIds;
  final DateTime createdAt;

  GapItem({
    required this.id,
    required this.facilityId,
    required this.standardCode,
    required this.chapterCode,
    required this.gapTitle,
    required this.description,
    required this.severity,
    required this.status,
    required this.responsiblePerson,
    required this.dueDate,
    this.actionPlanId,
    this.evidenceIds = const [],
    required this.createdAt,
  });

  factory GapItem.fromJson(Map<String, dynamic> json) {
    return GapItem(
      id: json['id'] ?? '',
      facilityId: json['facilityId'] ?? '',
      standardCode: json['standardCode'] ?? '',
      chapterCode: json['chapterCode'] ?? '',
      gapTitle: json['gapTitle'] ?? '',
      description: json['description'] ?? '',
      severity: GapSeverity.values.firstWhere(
        (s) => s.name == json['severity'],
        orElse: () => GapSeverity.medium,
      ),
      status: GapStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => GapStatus.inProgress,
      ),
      responsiblePerson: json['responsiblePerson'] ?? 'Quality Officer',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'])
          : DateTime.now().add(const Duration(days: 30)),
      actionPlanId: json['actionPlanId'],
      evidenceIds: List<String>.from(json['evidenceIds'] ?? []),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'facilityId': facilityId,
        'standardCode': standardCode,
        'chapterCode': chapterCode,
        'gapTitle': gapTitle,
        'description': description,
        'severity': severity.name,
        'status': status.name,
        'responsiblePerson': responsiblePerson,
        'dueDate': dueDate.toIso8601String(),
        'actionPlanId': actionPlanId,
        'evidenceIds': evidenceIds,
        'createdAt': createdAt.toIso8601String(),
      };
}

class ActionPlanItem {
  final String id;
  final String facilityId;
  final String gapId;
  final String title;
  final String description;
  final String assignedUser;
  final String department;
  final GapSeverity priority;
  final DateTime startDate;
  final DateTime dueDate;
  String status; // Pending, In Progress, Under Review, Completed
  double progress; // 0.0 to 1.0
  final List<String> notes;
  DateTime? completionDate;

  ActionPlanItem({
    required this.id,
    required this.facilityId,
    required this.gapId,
    required this.title,
    required this.description,
    required this.assignedUser,
    required this.department,
    required this.priority,
    required this.startDate,
    required this.dueDate,
    this.status = 'In Progress',
    this.progress = 0.25,
    this.notes = const [],
    this.completionDate,
  });

  factory ActionPlanItem.fromJson(Map<String, dynamic> json) {
    return ActionPlanItem(
      id: json['id'] ?? '',
      facilityId: json['facilityId'] ?? '',
      gapId: json['gapId'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      assignedUser: json['assignedUser'] ?? '',
      department: json['department'] ?? 'Quality',
      priority: GapSeverity.values.firstWhere(
        (s) => s.name == json['priority'],
        orElse: () => GapSeverity.high,
      ),
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'])
          : DateTime.now(),
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'])
          : DateTime.now().add(const Duration(days: 14)),
      status: json['status'] ?? 'In Progress',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      notes: List<String>.from(json['notes'] ?? []),
      completionDate: json['completionDate'] != null
          ? DateTime.parse(json['completionDate'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'facilityId': facilityId,
        'gapId': gapId,
        'title': title,
        'description': description,
        'assignedUser': assignedUser,
        'department': department,
        'priority': priority.name,
        'startDate': startDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'status': status,
        'progress': progress,
        'notes': notes,
        'completionDate': completionDate?.toIso8601String(),
      };
}

enum LicenseStatus { valid, expiringSoon, expired, underRenewal }

class LicenseItem {
  final String id;
  final String facilityId;
  final String licenseName;
  final String licenseNumber;
  final String issuingAuthority;
  final DateTime issueDate;
  final DateTime expirationDate;
  LicenseStatus status;
  final String responsiblePerson;
  final String? documentUrl;
  final String? notes;

  LicenseItem({
    required this.id,
    required this.facilityId,
    required this.licenseName,
    required this.licenseNumber,
    required this.issuingAuthority,
    required this.issueDate,
    required this.expirationDate,
    required this.status,
    required this.responsiblePerson,
    this.documentUrl,
    this.notes,
  });

  factory LicenseItem.fromJson(Map<String, dynamic> json) {
    return LicenseItem(
      id: json['id'] ?? '',
      facilityId: json['facilityId'] ?? '',
      licenseName: json['licenseName'] ?? '',
      licenseNumber: json['licenseNumber'] ?? '',
      issuingAuthority: json['issuingAuthority'] ?? '',
      issueDate: json['issueDate'] != null
          ? DateTime.parse(json['issueDate'])
          : DateTime.now(),
      expirationDate: json['expirationDate'] != null
          ? DateTime.parse(json['expirationDate'])
          : DateTime.now().add(const Duration(days: 365)),
      status: LicenseStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => LicenseStatus.valid,
      ),
      responsiblePerson: json['responsiblePerson'] ?? '',
      documentUrl: json['documentUrl'],
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'facilityId': facilityId,
        'licenseName': licenseName,
        'licenseNumber': licenseNumber,
        'issuingAuthority': issuingAuthority,
        'issueDate': issueDate.toIso8601String(),
        'expirationDate': expirationDate.toIso8601String(),
        'status': status.name,
        'responsiblePerson': responsiblePerson,
        'documentUrl': documentUrl,
        'notes': notes,
      };
}

class ExpertProfile {
  final String id;
  final String name;
  final String title;
  final String specialty;
  final String gaharCertNumber;
  final int yearsExperience;
  final double rating;
  final int reviewsCount;
  final String avatarUrl;
  final bool isAvailable;

  ExpertProfile({
    required this.id,
    required this.name,
    required this.title,
    required this.specialty,
    required this.gaharCertNumber,
    required this.yearsExperience,
    required this.rating,
    required this.reviewsCount,
    required this.avatarUrl,
    this.isAvailable = true,
  });

  factory ExpertProfile.fromJson(Map<String, dynamic> json) {
    return ExpertProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      title: json['title'] ?? '',
      specialty: json['specialty'] ?? '',
      gaharCertNumber: json['gaharCertNumber'] ?? '',
      yearsExperience: json['yearsExperience'] ?? 5,
      rating: (json['rating'] as num?)?.toDouble() ?? 4.9,
      reviewsCount: json['reviewsCount'] ?? 12,
      avatarUrl: json['avatarUrl'] ?? '',
      isAvailable: json['isAvailable'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'title': title,
        'specialty': specialty,
        'gaharCertNumber': gaharCertNumber,
        'yearsExperience': yearsExperience,
        'rating': rating,
        'reviewsCount': reviewsCount,
        'avatarUrl': avatarUrl,
        'isAvailable': isAvailable,
      };
}

class BadgeItem {
  final String id;
  final String title;
  final String description;
  final String iconName;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  BadgeItem({
    required this.id,
    required this.title,
    required this.description,
    required this.iconName,
    this.isUnlocked = false,
    this.unlockedAt,
  });

  factory BadgeItem.fromJson(Map<String, dynamic> json) {
    return BadgeItem(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      iconName: json['iconName'] ?? 'star',
      isUnlocked: json['isUnlocked'] ?? false,
      unlockedAt: json['unlockedAt'] != null
          ? DateTime.parse(json['unlockedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'iconName': iconName,
        'isUnlocked': isUnlocked,
        'unlockedAt': unlockedAt?.toIso8601String(),
      };
}

class SurveyReadiness {
  final double readinessScore; // 0 to 100
  final int totalApplicableRequirements;
  final int compliantRequirements;
  final int openGapsCount;
  final int criticalGapsCount;
  final int missingEvidenceCount;
  final int expiringLicensesCount;
  final List<String> highRiskAreas;

  SurveyReadiness({
    required this.readinessScore,
    required this.totalApplicableRequirements,
    required this.compliantRequirements,
    required this.openGapsCount,
    required this.criticalGapsCount,
    required this.missingEvidenceCount,
    required this.expiringLicensesCount,
    required this.highRiskAreas,
  });

  factory SurveyReadiness.fromJson(Map<String, dynamic> json) {
    return SurveyReadiness(
      readinessScore: (json['readinessScore'] as num?)?.toDouble() ?? 78.5,
      totalApplicableRequirements: json['totalApplicableRequirements'] ?? 140,
      compliantRequirements: json['compliantRequirements'] ?? 110,
      openGapsCount: json['openGapsCount'] ?? 12,
      criticalGapsCount: json['criticalGapsCount'] ?? 2,
      missingEvidenceCount: json['missingEvidenceCount'] ?? 5,
      expiringLicensesCount: json['expiringLicensesCount'] ?? 1,
      highRiskAreas: List<String>.from(json['highRiskAreas'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        'readinessScore': readinessScore,
        'totalApplicableRequirements': totalApplicableRequirements,
        'compliantRequirements': compliantRequirements,
        'openGapsCount': openGapsCount,
        'criticalGapsCount': criticalGapsCount,
        'missingEvidenceCount': missingEvidenceCount,
        'expiringLicensesCount': expiringLicensesCount,
        'highRiskAreas': highRiskAreas,
      };
}
