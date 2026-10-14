import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'storage_service.dart';

class ApiService {
  static String get baseUrl => AppConfig.baseUrl;

  static Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService.getAuthToken();
    final user = await StorageService.getUserProfile();

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (user != null && user.facilityId.isNotEmpty) 'X-Facility-Id': user.facilityId,
    };
  }

  // ─── Auth API ─────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> superAdminLogin(String email, String password) async {
    final url = '$baseUrl/auth/super-admin/login';
    debugPrint('[API] Calling Super Admin Login endpoint: $url (Email: $email)');
    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('[API] Super Admin Login HTTP status: ${res.statusCode}');
      
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (err) {
        debugPrint('[API] Failed to parse response body as JSON: $err');
        data = {'success': false, 'message': 'Invalid response from server (HTTP ${res.statusCode})'};
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return data;
      } else {
        final errorMsg = data['message'] ?? 'Super Admin Login failed (HTTP ${res.statusCode})';
        debugPrint('[API] Super Admin Login error message: $errorMsg');
        return {'success': false, 'message': errorMsg};
      }
    } catch (e) {
      debugPrint('[API] Super Admin Login network error: $e');
      return {'success': false, 'message': 'Network connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final url = '$baseUrl/auth/login';
    debugPrint('[API] Calling Facility Login endpoint: $url (Email: $email)');
    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 15));
      
      debugPrint('[API] Facility Login HTTP status: ${res.statusCode}');
      
      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (err) {
        debugPrint('[API] Failed to parse response body as JSON: $err');
        data = {'success': false, 'message': 'Invalid response from server (HTTP ${res.statusCode})'};
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return data;
      } else {
        final errorMsg = data['message'] ?? 'Login failed (HTTP ${res.statusCode})';
        debugPrint('[API] Facility Login error message: $errorMsg');
        return {'success': false, 'message': errorMsg};
      }
    } catch (e) {
      debugPrint('[API] Facility Login network error: $e');
      return {'success': false, 'message': 'Network connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> registerFacility(Map<String, dynamic> data) async {
    final url = '$baseUrl/auth/register-facility';
    debugPrint('[API] Calling Register Facility endpoint: $url');
    try {
      final res = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 20));
      
      debugPrint('[API] Register Facility HTTP status: ${res.statusCode}');
      
      Map<String, dynamic> responseData = {};
      try {
        responseData = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (err) {
        debugPrint('[API] Failed to parse registration response body: $err');
        responseData = {'success': false, 'message': 'Invalid response from server (HTTP ${res.statusCode})'};
      }

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return responseData;
      } else {
        final errorMsg = responseData['message'] ?? 'Facility registration failed (HTTP ${res.statusCode})';
        debugPrint('[API] Facility registration error message: $errorMsg');
        return {'success': false, 'message': errorMsg};
      }
    } catch (e) {
      debugPrint('[API] Facility registration network error: $e');
      return {'success': false, 'message': 'Network connection error: $e'};
    }
  }

  // ─── AI Copilot API ────────────────────────────────────────────────────────
  static Future<String> getCopilotResponse({
    required String prompt,
    String? message,
    required String screenContext,
    Map<String, dynamic>? entityData,
    List<Map<String, String>>? conversationHistory,
  }) async {
    try {
      final headers = await _getHeaders();
      final cleanMessage = message ?? (prompt.contains('[USER QUESTION]:') ? prompt.split('[USER QUESTION]:')[1].split('[GAHAR STANDARDS CONTEXT]:')[0].trim() : prompt);
      final res = await http.post(
        Uri.parse('$baseUrl/ai/copilot'),
        headers: headers,
        body: jsonEncode({
          'prompt': prompt,
          'message': cleanMessage,
          'query': cleanMessage,
          'screenContext': screenContext,
          'entityData': entityData ?? {},
          'conversationHistory': conversationHistory ?? [],
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['reply'] ?? 'No response received from GAHAR Copilot';
      }
      return 'GAHAR Copilot guidance unavailable (HTTP ${res.statusCode})';
    } catch (e) {
      return 'Offline GAHAR Copilot Guidance: For $screenContext, ensure full EOC compliance documentation is verified by your Quality Manager prior to audit.';
    }
  }

  // ─── Super Admin Endpoints ────────────────────────────────────────────────
  static Future<List<dynamic>> getAdminFacilities() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/admin/facilities'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['facilities'] ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> updateFacilityStatus(String facilityId, String status, {String? reason}) async {
    try {
      final headers = await _getHeaders();
      final res = await http.put(
        Uri.parse('$baseUrl/admin/facilities/$facilityId/status'),
        headers: headers,
        body: jsonEncode({'status': status, 'reason': reason ?? ''}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getAdminAnalytics() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/admin/analytics'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['analytics'] ?? {};
      }
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<List<dynamic>> getAdminAuditLogs() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/admin/audit-logs'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['auditLogs'] ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<List<dynamic>> getSubscriptionPlans() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/admin/plans'));
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['plans'] ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ─── Payment Endpoints ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>> submitPaymentProof({
    required String planId,
    required double amount,
    required String paymentMethod,
    required String transactionRef,
    String? proofUrl,
  }) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/payments/submit-proof'),
        headers: headers,
        body: jsonEncode({
          'planId': planId,
          'amount': amount,
          'paymentMethod': paymentMethod,
          'transactionRef': transactionRef,
          'proofUrl': proofUrl ?? '',
        }),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── Password Reset Endpoints ──────────────────────────────────────────
  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(String token, String newPassword) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'newPassword': newPassword}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── Users Management Endpoints ────────────────────────────────────────
  static Future<List<dynamic>> getFacilityUsers() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/users'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['users'] ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> createFacilityUser(Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: headers,
        body: jsonEncode(data),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> toggleUserStatus(String userId, bool isActive) async {
    try {
      final headers = await _getHeaders();
      final res = await http.put(
        Uri.parse('$baseUrl/users/$userId/status'),
        headers: headers,
        body: jsonEncode({'isActive': isActive}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── Real Document Storage Endpoints ──────────────────────────────────
  static Future<Map<String, dynamic>> uploadDocument({
    required String title,
    required String category,
    required String base64Content,
    String? originalName,
    String? mimeType,
    String? requirementCode,
  }) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/documents/upload'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'category': category,
          'base64Content': base64Content,
          'originalName': originalName,
          'mimeType': mimeType,
          'requirementCode': requirementCode,
        }),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<List<dynamic>> getDocuments() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/documents'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['documents'] ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> deleteDocument(String docId) async {
    try {
      final headers = await _getHeaders();
      final res = await http.delete(Uri.parse('$baseUrl/documents/$docId'), headers: headers);
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── Real Badges & Achievements Endpoint ──────────────────────────────
  static Future<Map<String, dynamic>> getFacilityBadges() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/facilities/badges'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false, 'badges': []};
    } catch (_) {
      return {'success': false, 'badges': []};
    }
  }

  // ─── Consultation Requests (Experts Hub) ───────────────────────────────
  static Future<Map<String, dynamic>> requestConsultation(Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/experts/request-consultation'),
        headers: headers,
        body: jsonEncode(data),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── Applicability Engine ───────────────────────────────────────────
  static Future<List<dynamic>> getApplicabilityQuestions() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/applicability/questions'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['questions'] ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> getFacilityApplicability() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/applicability/status'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> submitFacilityApplicability(Map<String, dynamic> answers) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/applicability/submit'),
        headers: headers,
        body: jsonEncode({'answers': answers}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getApplicabilityDashboard() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/applicability/dashboard'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── Document Generation & Governance V2 ───────────────────────────────
  static Future<List<dynamic>> getDocumentCatalog() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/documents/catalog'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['catalog'] ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> generateDocumentDraft(String docCode, Map<String, dynamic> customization) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/documents/draft'),
        headers: headers,
        body: jsonEncode({
          'docCode': docCode,
          'customization': customization,
        }),
      );
      if (res.body.trim().startsWith('<')) {
        return {
          'success': false,
          'message': 'Unable to generate the document. The document service returned an unexpected response. Please try again.',
        };
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'success': false, 'message': 'Invalid response format from document service.'};
    } catch (e) {
      return {
        'success': false,
        'message': 'Unable to generate the document. The document service returned an unexpected response. Please try again.',
      };
    }
  }

  static Future<Map<String, dynamic>> saveDocumentVersion(String docCode, Map<String, dynamic> versionData) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/documents/version'),
        headers: headers,
        body: jsonEncode({
          'docCode': docCode,
          ...versionData,
        }),
      );
      if (res.body.trim().startsWith('<')) {
        return {
          'success': false,
          'message': 'Failed to save document version due to an unexpected server response.',
        };
      }
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'success': false, 'message': 'Invalid response format.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> updateDocumentApprovalStatus(String docId, String status, {String? notes}) async {
    try {
      final headers = await _getHeaders();
      final res = await http.put(
        Uri.parse('$baseUrl/documents/$docId/approval'),
        headers: headers,
        body: jsonEncode({
          'status': status,
          'notes': notes ?? '',
        }),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<List<dynamic>> getDocumentVersions(String docId) async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/documents/$docId/versions'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['versions'] ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>> getDocumentDashboard() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/documents/dashboard'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── Survey Preparation & Mock Survey ──────────────────────────────────
  static Future<Map<String, dynamic>> createMockSurveyRequest(Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/surveys/mock/request'),
        headers: headers,
        body: jsonEncode(data),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<List<dynamic>> getMockSurveys() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/surveys/mock'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['surveys'] ?? [];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ─── Continuous Monitoring & ROI Analytics ─────────────────────────────
  static Future<Map<String, dynamic>> getMonitoringSummary() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/monitoring/summary'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getFacilityRoiAnalytics() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/monitoring/roi'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ─── Trash / Recycle Bin API ───────────────────────────────────────────────

  /// Fetches all trashed items for the current facility.
  /// Optional filters: [type] ('document','gap','action_plan','license'),
  /// [search] string, [from]/[to] ISO date strings.
  static Future<List<dynamic>> getTrash({
    String? type,
    String? search,
    String? from,
    String? to,
  }) async {
    try {
      final headers = await _getHeaders();
      final params = <String, String>{};
      if (type != null) params['type'] = type;
      if (search != null && search.isNotEmpty) params['search'] = search;
      if (from != null) params['from'] = from;
      if (to != null) params['to'] = to;

      final uri = Uri.parse('$baseUrl/trash').replace(queryParameters: params.isEmpty ? null : params);
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['trash'] ?? [];
      }
      debugPrint('[API] getTrash error ${res.statusCode}: ${res.body}');
      return [];
    } catch (e) {
      debugPrint('[API] getTrash network error: $e');
      return [];
    }
  }

  /// Restores a trashed item back to its original module.
  static Future<Map<String, dynamic>> restoreTrashItem(String trashId) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/trash/$trashId/restore'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Restores all trashed items for the current facility.
  static Future<Map<String, dynamic>> restoreAllTrash() async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/trash/restore-all'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Permanently deletes a single trash item (requires FACILITY_ADMIN role).
  static Future<Map<String, dynamic>> permanentDeleteTrashItem(String trashId) async {
    try {
      final headers = await _getHeaders();
      final res = await http.delete(
        Uri.parse('$baseUrl/trash/$trashId/permanent'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Empties the entire trash for the current facility (requires FACILITY_ADMIN role).
  static Future<Map<String, dynamic>> emptyTrash() async {
    try {
      final headers = await _getHeaders();
      final res = await http.delete(
        Uri.parse('$baseUrl/trash/empty'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Soft-deletes a gap (moves to Trash).
  static Future<Map<String, dynamic>> deleteGap(String gapId) async {
    try {
      final headers = await _getHeaders();
      final res = await http.delete(Uri.parse('$baseUrl/gaps/$gapId'), headers: headers);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Soft-deletes an action plan (moves to Trash).
  static Future<Map<String, dynamic>> deleteActionPlan(String planId) async {
    try {
      final headers = await _getHeaders();
      final res = await http.delete(Uri.parse('$baseUrl/action-plans/$planId'), headers: headers);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Soft-deletes a license (moves to Trash).
  static Future<Map<String, dynamic>> deleteLicense(String licenseId) async {
    try {
      final headers = await _getHeaders();
      final res = await http.delete(Uri.parse('$baseUrl/licenses/$licenseId'), headers: headers);
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}
