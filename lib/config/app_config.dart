import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum Environment { dev, staging, prod }

class AppConfig {
  static Environment currentEnvironment = Environment.dev;
  static const String _serverUrlKey = 'gahar_custom_api_base_url';
  static String? _customBaseUrl;

  // PC's local LAN IP for physical Android devices
  static const String defaultLanIp = '192.168.1.7';

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customBaseUrl = prefs.getString(_serverUrlKey);
    } catch (_) {}
  }

  // Compile-time environment configuration via --dart-define=API_BASE_URL=https://...
  static const String _configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String _normalizeApiUrl(String input) {
    String clean = input.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    if (!clean.endsWith('/api')) {
      clean = '$clean/api';
    }
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }
    return clean;
  }

  static String? get customBaseUrl => _customBaseUrl;

  static Future<void> setCustomBaseUrl(String? url) async {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _customBaseUrl = null;
    } else {
      _customBaseUrl = _normalizeApiUrl(trimmed);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_customBaseUrl == null) {
        await prefs.remove(_serverUrlKey);
      } else {
        await prefs.setString(_serverUrlKey, _customBaseUrl!);
      }
    } catch (_) {}
  }

  static String get baseUrl {
    // 1. Runtime override from local shared preferences (e.g., debug settings)
    if (_customBaseUrl != null && _customBaseUrl!.isNotEmpty) {
      return _customBaseUrl!;
    }

    // 2. Build-time defined URL (e.g. --dart-define=API_BASE_URL=https://...)
    if (_configuredBaseUrl.isNotEmpty) {
      return _normalizeApiUrl(_configuredBaseUrl);
    }

    // 3. Fallback based on active environment
    switch (currentEnvironment) {
      case Environment.dev:
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          return 'http://$defaultLanIp:3000/api';
        }
        return 'http://localhost:3000/api';
      case Environment.staging:
        return 'https://staging-api.gahar.gov.eg/api';
      case Environment.prod:
        return 'https://api.gahar.gov.eg/api';
    }
  }

  static String get appName => 'GAHAR';
  static String get appVersion => '1.0.0+1';
}
