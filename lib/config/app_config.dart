enum Environment { dev, staging, prod }

class AppConfig {
  static Environment currentEnvironment = Environment.dev;

  static String get baseUrl {
    switch (currentEnvironment) {
      case Environment.dev:
        return 'http://localhost:3000/api';
      case Environment.staging:
        return 'https://staging-api.accredigo.eg/api';
      case Environment.prod:
        return 'https://api.accredigo.eg/api';
    }
  }

  static String get appName => 'AccrediGo Healthcare Accreditation Platform';
  static String get appVersion => '1.0.0+1';
}
