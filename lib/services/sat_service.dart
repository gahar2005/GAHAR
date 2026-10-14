import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../config/app_config.dart';
import '../models/sat_models.dart';
import 'storage_service.dart';

class SATService {
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

  // ─── 1. Get SAT Standards ──────────────────────────────────────────────────
  static Future<List<SATStandard>> getSATStandards({String? chapterCode}) async {
    try {
      final headers = await _getHeaders();
      String url = '$baseUrl/sat/standards';
      if (chapterCode != null && chapterCode.isNotEmpty) {
        url += '?chapter=${Uri.encodeComponent(chapterCode)}';
      }

      final res = await http.get(Uri.parse(url), headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['standards'] is List) {
          return (data['standards'] as List)
              .map((item) => SATStandard.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[SATService] Error fetching standards: $e');
    }

    // Fallback: return default GSR standards if offline or server is unreachable
    return _getDefaultGSRStandards();
  }

  // ─── 2. Get Facility SAT Scores ────────────────────────────────────────────
  static Future<List<SATScore>> getSATScores() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/sat/scores'), headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['scores'] is List) {
          return (data['scores'] as List)
              .map((item) => SATScore.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[SATService] Error fetching scores: $e');
    }
    return [];
  }

  // ─── 3. Save Single Score ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>> saveSATScore(SATScore score) async {
    try {
      final headers = await _getHeaders();
      final res = await http.put(
        Uri.parse('$baseUrl/sat/scores/${Uri.encodeComponent(score.standardCode)}'),
        headers: headers,
        body: jsonEncode({
          'score_status': score.scoreStatus.value,
          'numeric_score': score.numericScore ?? score.scoreStatus.numericValue,
          'notes': score.notes,
        }),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error saving score: $e'};
    }
  }

  // ─── 4. Save Bulk Scores ───────────────────────────────────────────────────
  static Future<Map<String, dynamic>> saveBulkScores(List<SATScore> scores) async {
    try {
      final headers = await _getHeaders();
      final payload = scores
          .map((s) => {
                'standard_code': s.standardCode,
                'score_status': s.scoreStatus.value,
                'numeric_score': s.numericScore ?? s.scoreStatus.numericValue,
                'notes': s.notes,
              })
          .toList();

      final res = await http.post(
        Uri.parse('$baseUrl/sat/scores/bulk'),
        headers: headers,
        body: jsonEncode({'scores': payload}),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error saving bulk scores: $e'};
    }
  }

  // ─── 5. Get Chapter Summary ────────────────────────────────────────────────
  static Future<List<SATChapterSummary>> getChapterSummary() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/sat/summary'), headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['summary'] is List) {
          return (data['summary'] as List)
              .map((item) => SATChapterSummary.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[SATService] Error fetching summary: $e');
    }
    return [];
  }

  // ─── 6. Get Assessment Report ──────────────────────────────────────────────
  static Future<SATAssessmentReport?> getSATReport() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(Uri.parse('$baseUrl/sat/report'), headers: headers);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['report'] != null) {
          return SATAssessmentReport.fromJson(Map<String, dynamic>.from(data['report'] as Map));
        }
      }
    } catch (e) {
      debugPrint('[SATService] Error fetching report: $e');
    }
    return null;
  }

  // ─── 7. Super Admin Platform Summary ───────────────────────────────────────
  static Future<Map<String, dynamic>> getAdminPlatformSummary() async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('$baseUrl/admin/sat/platform-summary'),
        headers: headers,
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Error fetching platform summary: $e'};
    }
  }

  // ─── 8. Get Sub-Evidence Items for a Standard ──────────────────────────────
  static Future<List<SATSubEvidenceItem>> getSubEvidence(String standardCode) async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('$baseUrl/sat/sub-evidence/${Uri.encodeComponent(standardCode)}'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true && data['evidence_items'] is List) {
          return (data['evidence_items'] as List)
              .map((item) => SATSubEvidenceItem.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[SATService] Error fetching sub-evidence for $standardCode: $e');
    }
    return [];
  }

  // ─── 9. Get Sub-Scores for a Standard (with calculation) ───────────────────
  static Future<({List<SATSubScore> scores, SATSubEvidenceCalculation? calculation})>
      getSubScores(String standardCode) async {
    try {
      final headers = await _getHeaders();
      final res = await http.get(
        Uri.parse('$baseUrl/sat/sub-scores/${Uri.encodeComponent(standardCode)}'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final scores = data['sub_scores'] is List
            ? (data['sub_scores'] as List)
                .map((s) => SATSubScore.fromJson(Map<String, dynamic>.from(s as Map)))
                .toList()
            : <SATSubScore>[];
        final calc = data['calculated_score'] != null
            ? SATSubEvidenceCalculation.fromJson(
                Map<String, dynamic>.from(data['calculated_score'] as Map))
            : null;
        return (scores: scores, calculation: calc);
      }
    } catch (e) {
      debugPrint('[SATService] Error fetching sub-scores for $standardCode: $e');
    }
    return (scores: <SATSubScore>[], calculation: null);
  }

  // ─── 10. Save a Single Sub-Evidence Score ──────────────────────────────────
  static Future<Map<String, dynamic>> saveSubScore({
    required String evidenceId,
    required String standardCode,
    required String scoreValue, // '0', '1', '2', or 'N/A'
    String? notes,
  }) async {
    try {
      final headers = await _getHeaders();
      final res = await http.put(
        Uri.parse('$baseUrl/sat/sub-scores/${Uri.encodeComponent(evidenceId)}'),
        headers: headers,
        body: jsonEncode({
          'score_value': scoreValue,
          'standard_code': standardCode,
          'notes': notes,
        }),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  // ─── 11. Bulk Save Sub-Evidence Scores ─────────────────────────────────────
  static Future<Map<String, dynamic>> bulkSaveSubScores(
      List<Map<String, dynamic>> scoreItems) async {
    try {
      final headers = await _getHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/sat/sub-scores/bulk'),
        headers: headers,
        body: jsonEncode({'scores': scoreItems}),
      );
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }


  static Future<void> exportSATReportPdf({
    required SATAssessmentReport report,
    required List<SATStandard> standards,
    required Map<String, SATScore> scoreMap,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blue900, width: 1.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'GAHAR Self-Assessment Tool (SAT)',
                  style: const pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
                pw.Text(
                  report.facilityName,
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'General Authority for Healthcare Accreditation and Regulation (GAHAR)',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            pw.SizedBox(height: 10),
            // Title block
            pw.Text(
              'Hospital Accreditation Self-Assessment Report',
              style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Evaluation Date: ${report.assessmentDate.toLocal().toString().split(' ')[0]} | Source: Hospital Full Accreditation SAT 2025',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),

            // Summary KPIs card
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.blue200),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _pdfKpiColumn('Overall SAT Score', '${report.overallScore.toStringAsFixed(1)}%', PdfColors.blue900),
                  _pdfKpiColumn('Total Standards', '${report.totalStandards}', PdfColors.grey800),
                  _pdfKpiColumn('Assessed Items', '${report.assessedStandards}', PdfColors.grey800),
                  _pdfKpiColumn('Completion Rate', '${report.completionRate.toStringAsFixed(1)}%', PdfColors.teal800),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Chapter Performance Table
            pw.Text(
              'Chapter Performance & Totals',
              style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Chapter', 'Total Items', 'Assessed', 'Fully Met', 'Partially Met', 'Not Met', 'N/A', 'Score %'],
              data: report.chapterSummaries.map((c) {
                return [
                  '${c.chapterCode} - ${c.chapterTitle}',
                  c.totalStandards.toString(),
                  c.assessedStandards.toString(),
                  c.fullyMet.toString(),
                  c.partiallyMet.toString(),
                  c.notMet.toString(),
                  c.notApplicable.toString(),
                  '${c.scorePercentage.toStringAsFixed(1)}%',
                ];
              }).toList(),
              headerStyle: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            ),
            pw.SizedBox(height: 20),

            // Standards Detailed Assessment Table
            pw.Text(
              'Detailed Standards Assessment (GSR Chapter)',
              style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Code', 'Category', 'Standard Title & Reference', 'Status', 'Score', 'Notes'],
              data: standards.map((std) {
                final sc = scoreMap[std.standardCode];
                final status = sc?.scoreStatus.label ?? 'Not Assessed';
                final numVal = sc?.scoreStatus == SATScoreStatus.notApplicable
                    ? 'N/A'
                    : (sc?.numericScore != null ? '${sc!.numericScore}%' : '-');
                final notes = (sc?.notes ?? '').isNotEmpty ? sc!.notes : '-';

                return [
                  std.standardCode,
                  std.category,
                  '${std.standardTitle}\n[Ref: ${std.bookReferenceCode}]',
                  status,
                  numVal,
                  notes,
                ];
              }).toList(),
              headerStyle: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.all(3),
            ),
          ];
        },
      ),
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'GAHAR_SAT_Report_${report.facilityName.replaceAll(' ', '_')}.pdf',
    );
  }

  static pw.Widget _pdfKpiColumn(String label, String value, PdfColor valueColor) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }

  // ─── Default 29 GSR Standards Reference Fallback ───────────────────────────
  static List<SATStandard> _getDefaultGSRStandards() {
    return [
      const SATStandard(
        id: 'gsr-1',
        standardCode: 'GSR.01',
        standardTitle: 'Facility License and Legal Compliance',
        category: 'Legal & Facility Compliance',
        subcategory: 'Facility Operations',
        bookReferenceCode: 'NSR.01',
        workbookSheet: 'GSR',
        sortOrder: 1,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-2',
        standardCode: 'GSR.02',
        standardTitle: 'Building and Construction Safety',
        category: 'Building Safety',
        subcategory: 'Infrastructure',
        bookReferenceCode: 'NSR.02',
        workbookSheet: 'GSR',
        sortOrder: 2,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-3',
        standardCode: 'GSR.03',
        standardTitle: 'Civil Defense and Fire Safety Approval',
        category: 'Fire Safety',
        subcategory: 'Civil Protection',
        bookReferenceCode: 'NSR.03',
        workbookSheet: 'GSR',
        sortOrder: 3,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-4',
        standardCode: 'GSR.04',
        standardTitle: 'Fire Alarm and Detection Systems',
        category: 'Fire Safety',
        subcategory: 'Alarm Systems',
        bookReferenceCode: 'NSR.04',
        workbookSheet: 'GSR',
        sortOrder: 4,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-5',
        standardCode: 'GSR.05',
        standardTitle: 'Fire Suppression and Extinguishing Systems',
        category: 'Fire Safety',
        subcategory: 'Suppression',
        bookReferenceCode: 'NSR.05',
        workbookSheet: 'GSR',
        sortOrder: 5,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-6',
        standardCode: 'GSR.06',
        standardTitle: 'Emergency Exits and Evacuation Routes',
        category: 'Life Safety',
        subcategory: 'Evacuation',
        bookReferenceCode: 'NSR.06',
        workbookSheet: 'GSR',
        sortOrder: 6,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-7',
        standardCode: 'GSR.07',
        standardTitle: 'Electrical Safety and Emergency Backup Generators',
        category: 'Utility Systems',
        subcategory: 'Power Systems',
        bookReferenceCode: 'NSR.07',
        workbookSheet: 'GSR',
        sortOrder: 7,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-8',
        standardCode: 'GSR.08',
        standardTitle: 'Medical Gas Systems Safety and Inspection',
        category: 'Utility Systems',
        subcategory: 'Medical Gases',
        bookReferenceCode: 'NSR.08',
        workbookSheet: 'GSR',
        sortOrder: 8,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-9',
        standardCode: 'GSR.09',
        standardTitle: 'Water Supply and Safe Potable Water Testing',
        category: 'Utility Systems',
        subcategory: 'Water Safety',
        bookReferenceCode: 'NSR.09',
        workbookSheet: 'GSR',
        sortOrder: 9,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-10',
        standardCode: 'GSR.10',
        standardTitle: 'HVAC and Air Filtration Systems in Critical Areas',
        category: 'Utility Systems',
        subcategory: 'Ventilation',
        bookReferenceCode: 'NSR.10',
        workbookSheet: 'GSR',
        sortOrder: 10,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-11',
        standardCode: 'GSR.11',
        standardTitle: 'Hazardous Materials and Waste Management Plan',
        category: 'Environmental Safety',
        subcategory: 'Hazardous Materials',
        bookReferenceCode: 'NSR.11',
        workbookSheet: 'GSR',
        sortOrder: 11,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-12',
        standardCode: 'GSR.12',
        standardTitle: 'Medical Waste Safe Handling and Disposal',
        category: 'Environmental Safety',
        subcategory: 'Medical Waste',
        bookReferenceCode: 'NSR.12',
        workbookSheet: 'GSR',
        sortOrder: 12,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-13',
        standardCode: 'GSR.13',
        standardTitle: 'Radiation Safety and Protection Controls',
        category: 'Environmental Safety',
        subcategory: 'Radiation',
        bookReferenceCode: 'NSR.13',
        workbookSheet: 'GSR',
        sortOrder: 13,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-14',
        standardCode: 'GSR.14',
        standardTitle: 'Medical Equipment Preventive Maintenance Program',
        category: 'Medical Equipment',
        subcategory: 'Maintenance',
        bookReferenceCode: 'NSR.14',
        workbookSheet: 'GSR',
        sortOrder: 14,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-15',
        standardCode: 'GSR.15',
        standardTitle: 'Medical Equipment Calibration and Certification',
        category: 'Medical Equipment',
        subcategory: 'Calibration',
        bookReferenceCode: 'NSR.15',
        workbookSheet: 'GSR',
        sortOrder: 15,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-16',
        standardCode: 'GSR.16',
        standardTitle: 'Infection Prevention and Control Program Structure',
        category: 'Infection Prevention',
        subcategory: 'Program Organization',
        bookReferenceCode: 'NSR.16',
        workbookSheet: 'GSR',
        sortOrder: 16,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-17',
        standardCode: 'GSR.17',
        standardTitle: 'Sterilization and Disinfection Central Service (CSSD)',
        category: 'Infection Prevention',
        subcategory: 'Sterilization',
        bookReferenceCode: 'NSR.17',
        workbookSheet: 'GSR',
        sortOrder: 17,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-18',
        standardCode: 'GSR.18',
        standardTitle: 'Hand Hygiene Infrastructure and Compliance Monitoring',
        category: 'Infection Prevention',
        subcategory: 'Hygiene',
        bookReferenceCode: 'NSR.18',
        workbookSheet: 'GSR',
        sortOrder: 18,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-19',
        standardCode: 'GSR.19',
        standardTitle: 'Isolation Rooms and Airborne Infection Controls',
        category: 'Infection Prevention',
        subcategory: 'Isolation',
        bookReferenceCode: 'NSR.19',
        workbookSheet: 'GSR',
        sortOrder: 19,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-20',
        standardCode: 'GSR.20',
        standardTitle: 'Emergency Management and Disaster Preparedness Plan',
        category: 'Emergency Preparedness',
        subcategory: 'Disaster Planning',
        bookReferenceCode: 'NSR.20',
        workbookSheet: 'GSR',
        sortOrder: 20,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-21',
        standardCode: 'GSR.21',
        standardTitle: 'Emergency Drills and Regular Staff Training',
        category: 'Emergency Preparedness',
        subcategory: 'Drills',
        bookReferenceCode: 'NSR.21',
        workbookSheet: 'GSR',
        sortOrder: 21,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-22',
        standardCode: 'GSR.22',
        standardTitle: 'Staff Occupational Health and Vaccination Safety',
        category: 'Occupational Health',
        subcategory: 'Staff Health',
        bookReferenceCode: 'NSR.22',
        workbookSheet: 'GSR',
        sortOrder: 22,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-23',
        standardCode: 'GSR.23',
        standardTitle: 'Personal Protective Equipment (PPE) Availability',
        category: 'Occupational Health',
        subcategory: 'PPE',
        bookReferenceCode: 'NSR.23',
        workbookSheet: 'GSR',
        sortOrder: 23,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-24',
        standardCode: 'GSR.24',
        standardTitle: 'Security Management and Facility Access Control',
        category: 'Security Management',
        subcategory: 'Access Control',
        bookReferenceCode: 'NSR.24',
        workbookSheet: 'GSR',
        sortOrder: 24,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-25',
        standardCode: 'GSR.25',
        standardTitle: 'Surveillance CCTV and Security Incident Reporting',
        category: 'Security Management',
        subcategory: 'Surveillance',
        bookReferenceCode: 'NSR.25',
        workbookSheet: 'GSR',
        sortOrder: 25,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-26',
        standardCode: 'GSR.26',
        standardTitle: 'Food Safety and Kitchen Sanitation Standards',
        category: 'Support Services',
        subcategory: 'Food Services',
        bookReferenceCode: 'NSR.26',
        workbookSheet: 'GSR',
        sortOrder: 26,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: false,
      ),
      const SATStandard(
        id: 'gsr-27',
        standardCode: 'GSR.27',
        standardTitle: 'Laundry and Linen Safety and Segregation',
        category: 'Support Services',
        subcategory: 'Laundry',
        bookReferenceCode: 'NSR.27',
        workbookSheet: 'GSR',
        sortOrder: 27,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: false,
      ),
      const SATStandard(
        id: 'gsr-28',
        standardCode: 'GSR.28',
        standardTitle: 'Elevator and Lift Safety Certifications',
        category: 'Facility Operations',
        subcategory: 'Vertical Transport',
        bookReferenceCode: 'NSR.28',
        workbookSheet: 'GSR',
        sortOrder: 28,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
      const SATStandard(
        id: 'gsr-29',
        standardCode: 'GSR.29',
        standardTitle: 'Emergency Communication and Disaster Call Trees',
        category: 'Facility Operations',
        subcategory: 'Communications',
        bookReferenceCode: 'NSR.29',
        workbookSheet: 'GSR',
        sortOrder: 29,
        chapterCode: 'GSR',
        chapterTitle: 'General Safety Requirements',
        isEssential: true,
      ),
    ];
  }
}
