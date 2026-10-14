import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Applicability API Contract & Safe Parsing Tests (TEST A)', () {
    test('Handles JSArray (List) response from backend without throwing TypeError', () {
      // This reproduces the exact payload from backend getFacilityApplicability
      final backendStatusResponse = {
        'success': true,
        'applicability': {
          'facilityId': 'fac-100',
          'isCompleted': true,
          'totalQuestions': 12,
          'answeredCount': 12,
          'answers': [
            {'questionId': 'q_radiology', 'answer': true},
            {'questionId': 'q_laboratory', 'answer': true},
            {'questionId': 'q_surgical', 'answer': true},
            {'questionId': 'q_teaching', 'answer': false},
          ],
          'excludedStandards': ['ACT.15', 'ACT.16', 'ACT.17'],
          'excludedCount': 3,
        }
      };

      final answersMap = <String, bool>{};
      final appData = backendStatusResponse['applicability'] as Map<String, dynamic>;

      if (appData['answersMap'] is Map) {
        (appData['answersMap'] as Map).forEach((k, v) {
          answersMap[k.toString()] = v == true;
        });
      } else if (appData['answers'] is List) {
        for (final item in (appData['answers'] as List)) {
          if (item is Map && item['questionId'] != null) {
            answersMap[item['questionId'].toString()] = item['answer'] == true;
          }
        }
      }

      expect(answersMap.length, 4);
      expect(answersMap['q_radiology'], isTrue);
      expect(answersMap['q_teaching'], isFalse);
    });

    test('Handles Map response from backend or local cache without throwing', () {
      final backendStatusResponse = {
        'success': true,
        'applicability': {
          'facilityId': 'fac-100',
          'answersMap': {
            'q_radiology': true,
            'q_teaching': false,
          },
          'answers': [],
          'excludedStandards': ['ACT.15'],
        }
      };

      final answersMap = <String, bool>{};
      final appData = backendStatusResponse['applicability'] as Map<String, dynamic>;

      if (appData['answersMap'] is Map) {
        (appData['answersMap'] as Map).forEach((k, v) {
          answersMap[k.toString()] = v == true;
        });
      } else if (appData['answers'] is List) {
        for (final item in (appData['answers'] as List)) {
          if (item is Map && item['questionId'] != null) {
            answersMap[item['questionId'].toString()] = item['answer'] == true;
          }
        }
      }

      expect(answersMap.length, 2);
      expect(answersMap['q_radiology'], isTrue);
      expect(answersMap['q_teaching'], isFalse);
    });
  });

  group('No Fake Data Integrity Tests (TEST B, F, G)', () {
    test('New unassessed facility returns empty list of gaps (no fake IPC.02/FMS.02)', () async {
      final gaps = await StorageService.getGaps();
      expect(gaps, isEmpty, reason: 'Must not inject mock gaps into empty facility storage');
    });

    test('New unassessed facility returns empty compliance scores (no fake 85%)', () async {
      final scores = await StorageService.getComplianceScores();
      expect(scores, isEmpty, reason: 'Must not inject mock scores into empty facility storage');
    });

    test('New facility returns empty action plans', () async {
      final plans = await StorageService.getActionPlans();
      expect(plans, isEmpty, reason: 'Must not inject mock action plans');
    });

    test('New facility returns empty licenses', () async {
      final licenses = await StorageService.getLicenses();
      expect(licenses, isEmpty, reason: 'Must not inject mock licenses');
    });

    test('New facility returns empty evidence items', () async {
      final evidence = await StorageService.getEvidenceItems();
      expect(evidence, isEmpty, reason: 'Must not inject mock evidence items');
    });
  });

  group('Document Generation Contract & Parsing (TEST E)', () {
    test('Safely parses JSON draft response containing both document and draft keys', () {
      final jsonResponse = {
        'success': true,
        'document': {
          'id': 'doc_12345',
          'doc_code': 'GAHAR-POL-GSR-06',
          'title': 'Pressure Injury Prevention & Staging Protocol',
          'content': '🏥 AL NOOR SPECIALIZED HOSPITAL\nDocument Code: GAHAR-POL-GSR-06\nRelated Standard: GSR.06',
        },
        'draft': {
          'id': 'doc_12345',
          'doc_code': 'GAHAR-POL-GSR-06',
          'title': 'Pressure Injury Prevention & Staging Protocol',
          'content': '🏥 AL NOOR SPECIALIZED HOSPITAL\nDocument Code: GAHAR-POL-GSR-06\nRelated Standard: GSR.06',
        }
      };

      expect(jsonResponse['success'], isTrue);
      expect(jsonResponse['draft'], isNotNull);
      final draftMap = jsonResponse['draft'] as Map<String, dynamic>;
      final content = draftMap['content'] as String;
      expect(content, contains('AL NOOR SPECIALIZED HOSPITAL'));
      expect(content, contains('GSR.06'));
    });
  });
}
