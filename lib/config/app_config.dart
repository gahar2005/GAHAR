import 'package:flutter/foundation.dart';

enum Environment { dev, staging, prod }

class AppConfig {
  static Environment currentEnvironment = Environment.dev;

  static String get baseUrl {
    switch (currentEnvironment) {
      case Environment.dev:
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          return 'http://10.0.2.2:3000/api';
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
