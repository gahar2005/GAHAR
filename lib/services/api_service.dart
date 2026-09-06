import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class ApiService {
  static String baseUrl = "http://localhost:3000/api";

  static Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService.getAuthToken();
    final facility = await StorageService.getHospitalProfile();
    final facilityId = facility?.name.replaceAll(' ', '_') ?? 'default_facility';

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'X-Facility-Id': facilityId,
    };
  }

  // ─── Auth API ─────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {'success': false, 'message': jsonDecode(res.body)['message'] ?? 'Login failed'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> registerFacility(Map<String, dynamic> data) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/auth/register-facility'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        return jsonDecode(res.body);
      }
      return {'success': false, 'message': jsonDecode(res.body)['message'] ?? 'Registration failed'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
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
        return data['reply'] ?? 'No response received';
      }
      return 'AI Copilot response unavailable (${res.statusCode})';
    } catch (e) {
      return 'Offline mode fallback: Server connection error ($e)';
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

  static Future<Map<String, dynamic>> getAdminAnalytics() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/admin/analytics'), headers: headers);
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
      return {};
    } catch (_) {
      return {};
    }
  }
}
