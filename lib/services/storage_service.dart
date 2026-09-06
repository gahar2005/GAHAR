import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_session.dart';
import '../models/compliance_score.dart';
import '../models/evidence_item.dart';
import '../models/hospital_profile.dart';
import '../models/platform_models.dart';
import '../models/saved_document.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  // flutter_secure_storage is not supported on web; we fall back to SharedPreferences
  static FlutterSecureStorage? get _secureStorage =>
      kIsWeb ? null : const FlutterSecureStorage();
  static const String _profileKey = 'gahar_hospital_profile';
  static const String _docsKey = 'gahar_saved_documents';
  static const String _evidenceKey = 'gahar_evidence_items';
  static const String _scoresKey = 'gahar_compliance_scores';
  static const String _chatKey = 'gahar_chat_sessions';
  
  // New Platform Keys
  static const String _tokenKey = 'gahar_auth_token';
  static const String _userKey = 'gahar_user_profile';
  static const String _gapsKey = 'gahar_gap_items';
  static const String _actionsKey = 'gahar_action_plans';
  static const String _licensesKey = 'gahar_licenses';

  // ─── Authentication & User Session (Secure Storage with web fallback) ───────
  static Future<String?> getAuthToken() async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_tokenKey);
      }
      return await _secureStorage!.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAuthToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } else {
      await _secureStorage!.write(key: _tokenKey, value: token);
    }
  }

  static Future<UserProfile?> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveUserProfile(UserProfile user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  static Future<void> clearSession() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } else {
      await _secureStorage!.delete(key: _tokenKey);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }

  // ─── Hospital Profile ───────────────────────────────────────────────────────
  static Future<HospitalProfile?> getHospitalProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return HospitalProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveHospitalProfile(HospitalProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  // ─── Document Library ───────────────────────────────────────────────────────
  static Future<List<SavedDocument>> getSavedDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_docsKey) ?? [];
    return rawList
        .map((item) =>
            SavedDocument.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveDocument(SavedDocument doc) async {
    final docs = await getSavedDocuments();
    final index = docs.indexWhere((d) => d.id == doc.id);
    if (index >= 0) {
      docs[index] = doc;
    } else {
      docs.insert(0, doc);
    }
    final prefs = await SharedPreferences.getInstance();
    final rawList = docs.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_docsKey, rawList);
  }

  static Future<void> deleteDocument(String id) async {
    final docs = await getSavedDocuments();
    docs.removeWhere((d) => d.id == id);
    final prefs = await SharedPreferences.getInstance();
    final rawList = docs.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_docsKey, rawList);
  }

  static Future<void> toggleFavoriteDocument(String id) async {
    final docs = await getSavedDocuments();
    final index = docs.indexWhere((d) => d.id == id);
    if (index >= 0) {
      docs[index].isFavorite = !docs[index].isFavorite;
      final prefs = await SharedPreferences.getInstance();
      final rawList = docs.map((d) => jsonEncode(d.toJson())).toList();
      await prefs.setStringList(_docsKey, rawList);
    }
  }

  // ─── Evidence Items ─────────────────────────────────────────────────────────
  static Future<List<EvidenceItem>> getEvidenceItems() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_evidenceKey) ?? [];
    if (rawList.isEmpty) {
      final defaults = _getDefaultEvidenceItems();
      await saveEvidenceItems(defaults);
      return defaults;
    }
    return rawList
        .map((item) =>
            EvidenceItem.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveEvidenceItems(List<EvidenceItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = items.map((i) => jsonEncode(i.toJson())).toList();
    await prefs.setStringList(_evidenceKey, rawList);
  }

  static Future<void> toggleEvidenceItem(String id) async {
    final items = await getEvidenceItems();
    final index = items.indexWhere((i) => i.id == id);
    if (index >= 0) {
      items[index].isCompleted = !items[index].isCompleted;
      items[index].completedAt =
          items[index].isCompleted ? DateTime.now() : null;
      await saveEvidenceItems(items);
    }
  }

  static List<EvidenceItem> _getDefaultEvidenceItems() {
    return [
      EvidenceItem(
          id: 'ev_01',
          standardCode: 'GSR.01',
          label: 'Patient Rights & Responsibilities Policy Approval',
          category: 'Governance'),
      EvidenceItem(
          id: 'ev_02',
          standardCode: 'PCC.06',
          label: 'Informed Consent Form & Signed Samples',
          category: 'Governance'),
      EvidenceItem(
          id: 'ev_03',
          standardCode: 'IPC.01',
          label: 'Infection Control Committee Meeting Minutes (Quarterly)',
          category: 'Meeting Minutes'),
      EvidenceItem(
          id: 'ev_04',
          standardCode: 'IPC.02',
          label: 'Hand Hygiene Compliance Observation Audits',
          category: 'Audit'),
      EvidenceItem(
          id: 'ev_05',
          standardCode: 'SAS.03',
          label: 'Surgical Safety Checklist Operational Logs',
          category: 'Log'),
      EvidenceItem(
          id: 'ev_06',
          standardCode: 'HRM.04',
          label: 'Staff Annual Competency Assessment Checklists',
          category: 'Training'),
      EvidenceItem(
          id: 'ev_07',
          standardCode: 'FMS.02',
          label: 'Fire Safety & Disaster Drill Evacuation Report',
          category: 'Audit'),
      EvidenceItem(
          id: 'ev_08',
          standardCode: 'MSS.01',
          label: 'High-Alert Medication Double-Check Log',
          category: 'Log'),
      EvidenceItem(
          id: 'ev_09',
          standardCode: 'MIS.03',
          label: 'Medical Records Quality Audit Reports',
          category: 'KPI'),
    ];
  }

  // ─── Compliance Scores ──────────────────────────────────────────────────────
  static Future<List<ChapterComplianceScore>> getComplianceScores() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_scoresKey) ?? [];
    if (rawList.isEmpty) {
      final defaults = _getDefaultComplianceScores();
      await saveComplianceScores(defaults);
      return defaults;
    }
    return rawList
        .map((item) => ChapterComplianceScore.fromJson(
            jsonDecode(item) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveComplianceScores(
      List<ChapterComplianceScore> scores) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = scores.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_scoresKey, rawList);
  }

  static Future<void> updateComplianceScore(
      String chapterCode, int newScore) async {
    final scores = await getComplianceScores();
    final index = scores.indexWhere((s) => s.chapterCode == chapterCode);
    if (index >= 0) {
      scores[index].score = newScore.clamp(0, 100);
      scores[index].lastUpdated = DateTime.now();
      await saveComplianceScores(scores);
    }
  }

  static List<ChapterComplianceScore> _getDefaultComplianceScores() {
    final now = DateTime.now();
    return [
      ChapterComplianceScore(
          chapterCode: 'GSR',
          chapterName: 'General Safety Requirements',
          chapterArabicName: 'متطلبات السلامة العامة',
          score: 85,
          lastUpdated: now),
      ChapterComplianceScore(
          chapterCode: 'PCC',
          chapterName: 'Patient Centered Care',
          chapterArabicName: 'الرعاية المتمركزة حول المريض',
          score: 92,
          lastUpdated: now),
      ChapterComplianceScore(
          chapterCode: 'SAS',
          chapterName: 'Surgical & Anesthesia Care',
          chapterArabicName: 'الجراحة والتخدير',
          score: 78,
          lastUpdated: now),
      ChapterComplianceScore(
          chapterCode: 'MSS',
          chapterName: 'Medication Safety & System',
          chapterArabicName: 'سلامة ووحدة الدواء',
          score: 70,
          lastUpdated: now),
      ChapterComplianceScore(
          chapterCode: 'IPC',
          chapterName: 'Infection Prevention & Control',
          chapterArabicName: 'مكافحة العدوى',
          score: 88,
          lastUpdated: now),
      ChapterComplianceScore(
          chapterCode: 'HRM',
          chapterName: 'Human Resource Management',
          chapterArabicName: 'إدارة الموارد البشرية',
          score: 65,
          lastUpdated: now),
      ChapterComplianceScore(
          chapterCode: 'FMS',
          chapterName: 'Facility & Safety Management',
          chapterArabicName: 'إدارة المنشأة والسلامة',
          score: 75,
          lastUpdated: now),
      ChapterComplianceScore(
          chapterCode: 'MIS',
          chapterName: 'Management & Information System',
          chapterArabicName: 'إدارة النظم والمعلومات',
          score: 80,
          lastUpdated: now),
    ];
  }

  // ─── Gaps & Action Plans ───────────────────────────────────────────────────
  static Future<List<GapItem>> getGaps() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_gapsKey) ?? [];
    if (rawList.isEmpty) {
      final defaults = _getDefaultGaps();
      await saveGaps(defaults);
      return defaults;
    }
    return rawList.map((i) => GapItem.fromJson(jsonDecode(i))).toList();
  }

  static Future<void> saveGaps(List<GapItem> gaps) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = gaps.map((g) => jsonEncode(g.toJson())).toList();
    await prefs.setStringList(_gapsKey, raw);
  }

  static List<GapItem> _getDefaultGaps() {
    final now = DateTime.now();
    return [
      GapItem(
        id: 'gap_01',
        facilityId: 'fac_default',
        standardCode: 'IPC.02',
        chapterCode: 'IPC',
        gapTitle: 'Hand Hygiene Observation Audits Incomplete',
        description: 'Quarterly hand hygiene compliance observation rate is below 80% threshold in ICU.',
        severity: GapSeverity.high,
        status: GapStatus.inProgress,
        responsiblePerson: 'Dr. Sarah Ahmed (Infection Control)',
        dueDate: now.add(const Duration(days: 14)),
        createdAt: now,
      ),
      GapItem(
        id: 'gap_02',
        facilityId: 'fac_default',
        standardCode: 'FMS.02',
        chapterCode: 'FMS',
        gapTitle: 'Annual Fire Safety Evacuation Drill Missing',
        description: 'No documentation found for second annual mandatory disaster drill.',
        severity: GapSeverity.critical,
        status: GapStatus.notStarted,
        responsiblePerson: 'Eng. Mahmoud Hassan (Safety)',
        dueDate: now.add(const Duration(days: 7)),
        createdAt: now,
      ),
    ];
  }

  static Future<List<ActionPlanItem>> getActionPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_actionsKey) ?? [];
    if (rawList.isEmpty) {
      final defaults = _getDefaultActionPlans();
      await saveActionPlans(defaults);
      return defaults;
    }
    return rawList.map((i) => ActionPlanItem.fromJson(jsonDecode(i))).toList();
  }

  static Future<void> saveActionPlans(List<ActionPlanItem> plans) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = plans.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_actionsKey, raw);
  }

  static List<ActionPlanItem> _getDefaultActionPlans() {
    final now = DateTime.now();
    return [
      ActionPlanItem(
        id: 'plan_01',
        facilityId: 'fac_default',
        gapId: 'gap_01',
        title: 'Conduct Intensive ICU Hand Hygiene Retraining & Weekly Audits',
        description: 'Implement weekly secret-shopper audits and mandatory online retraining for ICU nurses.',
        assignedUser: 'Dr. Sarah Ahmed',
        department: 'Infection Control',
        priority: GapSeverity.high,
        startDate: now,
        dueDate: now.add(const Duration(days: 14)),
        status: 'In Progress',
        progress: 0.4,
      ),
    ];
  }

  // ─── Licenses ─────────────────────────────────────────────────────────────
  static Future<List<LicenseItem>> getLicenses() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_licensesKey) ?? [];
    if (rawList.isEmpty) {
      final defaults = _getDefaultLicenses();
      await saveLicenses(defaults);
      return defaults;
    }
    return rawList.map((i) => LicenseItem.fromJson(jsonDecode(i))).toList();
  }

  static Future<void> saveLicenses(List<LicenseItem> licenses) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = licenses.map((l) => jsonEncode(l.toJson())).toList();
    await prefs.setStringList(_licensesKey, raw);
  }

  static List<LicenseItem> _getDefaultLicenses() {
    final now = DateTime.now();
    return [
      LicenseItem(
        id: 'lic_01',
        facilityId: 'fac_default',
        licenseName: 'Ministry of Health Operating License / ترخيص وزارة الصحة',
        licenseNumber: 'MOH-EG-99824',
        issuingAuthority: 'Ministry of Health & Population',
        issueDate: now.subtract(const Duration(days: 300)),
        expirationDate: now.add(const Duration(days: 65)),
        status: LicenseStatus.valid,
        responsiblePerson: 'Legal Affairs Dept',
      ),
      LicenseItem(
        id: 'lic_02',
        facilityId: 'fac_default',
        licenseName: 'Radiation Protection License (Radiology Dept) / ترخيص الوقاية الإشعاعية',
        licenseNumber: 'RPA-2024-551',
        issuingAuthority: 'Egyptian Atomic Energy Authority',
        issueDate: now.subtract(const Duration(days: 350)),
        expirationDate: now.add(const Duration(days: 15)),
        status: LicenseStatus.expiringSoon,
        responsiblePerson: 'Radiology Head',
      ),
    ];
  }

  // ─── Chat Sessions ──────────────────────────────────────────────────────────
  static Future<List<ChatSession>> getChatSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_chatKey) ?? [];
    return rawList
        .map((item) =>
            ChatSession.fromJson(jsonDecode(item) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveChatSession(ChatSession session) async {
    final sessions = await getChatSessions();
    final index = sessions.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      sessions[index] = session;
    } else {
      sessions.insert(0, session);
    }
    final prefs = await SharedPreferences.getInstance();
    final rawList = sessions.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_chatKey, rawList);
  }

  static Future<void> deleteChatSession(String id) async {
    final sessions = await getChatSessions();
    sessions.removeWhere((s) => s.id == id);
    final prefs = await SharedPreferences.getInstance();
    final rawList = sessions.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_chatKey, rawList);
  }
}
