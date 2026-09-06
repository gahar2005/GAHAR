import 'dart:convert';
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
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/super-admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Network connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Network connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> registerFacility(Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/register-facility'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'message': 'Network connection error: $e'};
    }
  }

  // ─── AI Copilot API ────────────────────────────────────────────────────────
  static Future<String> getCopilotResponse({
    required String prompt,
    required String screenContext,
    Map<String, dynamic>? entityData,
  }) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/ai/copilot'),
        headers: headers,
        body: jsonEncode({
          'prompt': prompt,
          'screenContext': screenContext,
          'entityData': entityData ?? {},
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
}
