import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/config/app_config.dart';
import 'package:my_app/models/platform_models.dart';
import 'package:my_app/services/api_service.dart';
import 'package:my_app/services/storage_service.dart';
import 'package:my_app/screens/auth/login_screen.dart';
import 'package:my_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserRole & UserProfile Authentication Tests', () {
    test('UserRoleExt.fromString correctly parses backend role strings', () {
      expect(UserRoleExt.fromString('SUPER_ADMIN'), equals(UserRole.superAdmin));
      expect(UserRoleExt.fromString('superAdmin'), equals(UserRole.superAdmin));
      expect(UserRoleExt.fromString('FACILITY_ADMIN'), equals(UserRole.facilityAdmin));
      expect(UserRoleExt.fromString('facilityAdmin'), equals(UserRole.facilityAdmin));
      expect(UserRoleExt.fromString('FACILITY_OWNER'), equals(UserRole.facilityOwner));
      expect(UserRoleExt.fromString('QUALITY_MANAGER'), equals(UserRole.qualityManager));
      expect(UserRoleExt.fromString('ACCREDITATION_MANAGER'), equals(UserRole.accreditationManager));
      expect(UserRoleExt.fromString('DOCTOR'), equals(UserRole.doctor));
      expect(UserRoleExt.fromString('NURSE'), equals(UserRole.nurse));
      expect(UserRoleExt.fromString('PHARMACIST'), equals(UserRole.pharmacist));
      expect(UserRoleExt.fromString(null), equals(UserRole.facilityAdmin));
    });

    test('UserProfile serialization handles backend uppercase roles cleanly', () {
      final backendJson = {
        'id': 'usr_001',
        'email': 'admin@cairohospital.eg',
        'fullName': 'Dr. Ahmed Hassan',
        'role': 'FACILITY_ADMIN',
        'facilityId': 'fac_01000000-0000-0000-0000-000000000001',
        'createdAt': '2025-01-01T00:00:00.000Z',
      };

      final profile = UserProfile.fromJson(backendJson);
      expect(profile.id, equals('usr_001'));
      expect(profile.email, equals('admin@cairohospital.eg'));
      expect(profile.role, equals(UserRole.facilityAdmin));
      expect(profile.fullName, equals('Dr. Ahmed Hassan'));
    });
  });

  group('StorageService Auth Session Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('StorageService saves and retrieves auth token', () async {
      const mockToken = 'mock_jwt_token_sample_12345';
      final saved = await StorageService.saveAuthToken(mockToken);
      expect(saved, isTrue);

      final retrieved = await StorageService.getAuthToken();
      expect(retrieved, equals(mockToken));

      await StorageService.clearSession();
      final afterClear = await StorageService.getAuthToken();
      expect(afterClear, isNull);
    });

    test('StorageService saves and retrieves UserProfile', () async {
      final user = UserProfile(
        id: 'usr_test_1',
        email: 'test@gahar.gov.eg',
        fullName: 'Test User',
        role: UserRole.superAdmin,
        facilityId: 'fac_test',
        createdAt: DateTime(2025, 1, 1),
      );

      await StorageService.saveUserProfile(user);
      final retrieved = await StorageService.getUserProfile();
      expect(retrieved, isNotNull);
      expect(retrieved!.email, equals('test@gahar.gov.eg'));
      expect(retrieved.role, equals(UserRole.superAdmin));
    });

    test('ApiService.checkUnauthorized(401) triggers session expiration and clears stored credentials', () async {
      await StorageService.saveAuthToken('active_jwt_token_123');
      expect(await StorageService.getAuthToken(), equals('active_jwt_token_123'));

      bool sessionExpiredFired = false;
      ApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      ApiService.checkUnauthorized(401);
      // Allow async session clear
      await Future.delayed(const Duration(milliseconds: 50));

      expect(sessionExpiredFired, isTrue);
      expect(await StorageService.getAuthToken(), isNull);
    });

    test('AppConfig normalizes custom base URL and preserves /api suffix', () async {
      await AppConfig.setCustomBaseUrl('https://my-backend.onrender.com');
      expect(AppConfig.baseUrl, equals('https://my-backend.onrender.com/api'));

      await AppConfig.setCustomBaseUrl('https://my-backend.onrender.com/api/');
      expect(AppConfig.baseUrl, equals('https://my-backend.onrender.com/api'));

      await AppConfig.setCustomBaseUrl(null);
      expect(AppConfig.baseUrl, contains('/api'));
    });
  });

  group('LoginScreen UI & Form Validation Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget createTestWidget() {
      return MaterialApp(
        theme: AppTheme.lightTheme,
        home: const LoginScreen(),
      );
    }

    testWidgets('LoginScreen renders option cards on initial load', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Sign In with Existing Account'), findsOneWidget);
      expect(find.text('Register for the First Time'), findsOneWidget);
      expect(find.text('Sign In as Administrator'), findsOneWidget);
    });

    testWidgets('Empty fields display validation error and do not proceed', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter facility login
      await tester.tap(find.text('Sign In with Existing Account'));
      await tester.pumpAndSettle();

      // Tap Sign In with empty fields
      await tester.tap(find.text('Sign In to Facility'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Please enter both email and password'), findsOneWidget);
    });

    testWidgets('Invalid email format displays validation error', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter facility login
      await tester.tap(find.text('Sign In with Existing Account'));
      await tester.pumpAndSettle();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'invalidemailformat');
      await tester.enterText(textFields.at(1), 'password123');
      await tester.tap(find.text('Sign In to Facility'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets('Selecting Administrator option updates UI to Super Admin Portal', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Sign In as Administrator'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign In as Administrator'));
      await tester.tap(find.text('Sign In as Administrator'));
      await tester.pumpAndSettle();

      expect(find.text('Super Admin Portal'), findsOneWidget);
      expect(find.text('Sign In as Super Admin'), findsOneWidget);
      expect(find.text('Back to Options'), findsOneWidget);
    });
  });
}
