import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';


import 'models/saved_document.dart';
import 'models/platform_models.dart';
import 'screens/compliance_dashboard_screen.dart';
import 'screens/evidence_tracker_screen.dart';
import 'screens/library_screen.dart';
import 'screens/applicability_screen.dart';
import 'screens/gap_analysis_screen.dart';
import 'screens/action_plans_screen.dart';
import 'screens/licenses_screen.dart';
import 'screens/survey_prep_screen.dart';
import 'screens/experts_hub_screen.dart';
import 'screens/facility_settings_screen.dart';
import 'screens/admin/super_admin_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/export_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

// ─── App Settings & Persistence ──────────────────────────────────────────────
class AppSettings {
  static const String _groqKeyPref = "groq_api_key";
  static const String _groqModel = "llama-3.3-70b-versatile";
  static const String groqEndpoint =
      "https://api.groq.com/openai/v1/chat/completions";

  static Future<String> getGroqKey() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString(_groqKeyPref) ?? '';
    if (savedKey.isEmpty) {
      return '';
    }
    return savedKey;
  }

  static Future<void> setGroqKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groqKeyPref, key.trim());
  }

  static String get model => _groqModel;
}

// ─── Search Engine ────────────────────────────────────────────────────────────
class BylawsSearchEngine {
  final List<String> _sections = [];
  bool isLoaded = false;

  // BM25 parameters
  static const double _k1 = 1.2;
  static const double _b = 0.75;

  // BM25 statistics
  final List<double> _docLengths = [];
  double _avgDocLength = 0;
  final List<Map<String, int>> _docTermFrequencies = [];
  final Map<String, List<int>> _invertedIndex = {}; // term -> doc indices

  // English stop words to ignore during search
  static const Set<String> _stopWords = {
    'a', 'an', 'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should',
    'may', 'might', 'shall', 'must', 'can', 'need', 'dare', 'ought', 'used',
    'to', 'of', 'in', 'for', 'on', 'with', 'at', 'by', 'from', 'as', 'into',
    'through', 'during', 'before', 'after', 'above', 'below', 'up', 'down', 'out',
    'off', 'over', 'under', 'again', 'then', 'once', 'and', 'but', 'or', 'nor',
    'not', 'so', 'yet', 'both', 'either', 'neither', 'whether', 'if', 'that',
    'this', 'these', 'those', 'what', 'which', 'who', 'how', 'when', 'where',
    'why', 'all', 'each', 'every', 'more', 'most', 'other', 'some', 'such',
    'no', 'only', 'same', 'than', 'too', 'very', 'just', 'i', 'you', 'he',
    'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'them', 'my', 'your',
    'his', 'its', 'our', 'their', 'any', 'few', 'much', 'many', 'also', 'while',
  };

  // Regex to check if a string contains Arabic characters
  static final RegExp _arabicRegex = RegExp(r'[\u0600-\u06FF]');

  // Arabic Normalization
  static String _normalizeArabic(String text) {
    text = text.replaceAll(RegExp(r'[\u064B-\u0652\u0670]'), ''); // Remove diacritics
    text = text.replaceAll(RegExp(r'\u0640'), ''); // Remove Tatweel
    text = text.replaceAll(RegExp(r'[أإآ]'), 'ا'); // Normalize Alef
    text = text.replaceAll(RegExp(r'ة'), 'ه'); // Normalize Teh Marbuta
    text = text.replaceAll(RegExp(r'ى'), 'ي'); // Normalize Alef Maksura
    return text.trim();
  }

  // Arabic Prefix/Stemming
  static String _stemArabic(String word) {
    if (word.length <= 3) return word;
    if (word.startsWith('وال') || word.startsWith('فال') || word.startsWith('بال')) {
      word = word.substring(3);
    } else if (word.startsWith('ال') || word.startsWith('لل')) {
      word = word.substring(2);
    } else if (word.startsWith('و') && word.length > 3) {
      word = word.substring(1);
    }
    return word;
  }

  // Predefined Arabic to English mapping
  static const Map<String, List<String>> _arabicToEnglishDict = {
    'تخرج': ['graduat', 'graduating', 'graduation', 'degree', 'award'],
    'معدل': ['gpa', 'cgpa', 'grade', 'points', 'average'],
    'رسوب': ['fail', 'failure', 'probation', 'dismissal', 'observation'],
    'راسب': ['fail', 'failure', 'repeat', 'probation'],
    'نجاح': ['pass', 'passed', 'passing', 'grade', 'marks'],
    'ناجح': ['pass', 'passed'],
    'غياب': ['absent', 'absence', 'attendance', 'attend'],
    'حضور': ['attend', 'attendance'],
    'انذار': ['probation', 'dismissal', 'warning', 'observation'],
    'فصل': ['dismiss', 'dismissal', 'suspend', 'suspension', 'semester', 'term'],
    'سحب': ['withdraw', 'withdrawal', 'drop'],
    'انسحاب': ['withdraw', 'withdrawal', 'drop'],
    'اضافه': ['add', 'adding'],
    'حذف': ['drop', 'dropping'],
    'ساعه': ['hour', 'hours', 'credit'],
    'ساعات': ['hour', 'hours', 'credit'],
    'معتمده': ['credit'],
    'تدريب': ['train', 'training', 'field'],
    'ميداني': ['field'],
    'تسجيل': ['regist', 'register', 'registration', 'enroll', 'enrollment'],
    'رسوم': ['fee', 'fees', 'tuition', 'pay', 'payment'],
    'مصاريف': ['fee', 'fees', 'tuition', 'pay', 'payment'],
    'مشروع': ['project'],
    'اختبار': ['exam', 'exams', 'examination', 'test', 'placement'],
    'امتحان': ['exam', 'exams', 'examination', 'test'],
    'مستوى': ['level', 'levels'],
    'مستويات': ['level', 'levels'],
    'سمستر': ['semester', 'semesters', 'term'],
    'صيفي': ['summer'],
    'قبول': ['admission', 'admitted', 'enrollment'],
    'شروط': ['requirement', 'requirements', 'rules', 'terms'],
    'متطلبات': ['requirement', 'requirements', 'rules'],
    'قوانين': ['rules', 'regulations', 'bylaw'],
    'لائحه': ['bylaw', 'regulation', 'regulations', 'rules'],
    'ماده': ['course', 'courses', 'module', 'modules'],
    'مواد': ['course', 'courses', 'module', 'modules'],
    'منهج': ['curriculum', 'curricula'],
    'دراسه': ['study', 'academic'],
  };

  // English synonyms
  static const Map<String, List<String>> _englishSynonyms = {
    'gpa': ['cgpa', 'grade', 'average', 'points'],
    'cgpa': ['gpa', 'grade', 'average', 'points'],
    'graduation': ['graduate', 'degree', 'award', 'requirements'],
    'graduate': ['graduation', 'degree', 'requirements'],
    'probation': ['dismissal', 'dismissed', 'warning', 'gpa', 'observation'],
    'withdraw': ['withdrawal', 'drop'],
    'withdrawal': ['withdraw', 'drop'],
    'fees': ['fee', 'tuition', 'pay', 'payment'],
    'tuition': ['fees', 'fee', 'pay', 'payment'],
    'training': ['train', 'field'],
    'project': ['graduation', 'project'],
    'exam': ['exams', 'examination', 'test'],
    'exams': ['exam', 'examination', 'test'],
    'test': ['placement', 'exam', 'exams'],
    'level': ['levels'],
    'semester': ['semesters', 'term', 'terms'],
    'summer': ['semester', 'semesters'],
  };

  Future<void> load() async {
    final raw = await rootBundle.loadString("assets/bylaws.txt");
    // Split into paragraphs by newlines (filter empty ones)
    final paragraphs = raw
        .split(RegExp(r'\n{1,}'))
        .map((p) => p.trim())
        .where((p) => p.length > 80) // Only meaningful paragraphs
        .toList();

    _sections.clear();
    _sections.addAll(paragraphs);

    _docLengths.clear();
    _docTermFrequencies.clear();
    _invertedIndex.clear();

    double totalLength = 0;
    for (int i = 0; i < _sections.length; i++) {
      final tokens = _tokenize(_sections[i]);
      final docLen = tokens.length.toDouble();
      _docLengths.add(docLen);
      totalLength += docLen;

      final Map<String, int> termFreqs = {};
      for (final token in tokens) {
        termFreqs[token] = (termFreqs[token] ?? 0) + 1;
      }
      _docTermFrequencies.add(termFreqs);

      for (final term in termFreqs.keys) {
        if (!_invertedIndex.containsKey(term)) {
          _invertedIndex[term] = [];
        }
        _invertedIndex[term]!.add(i);
      }
    }

    _avgDocLength = _sections.isEmpty ? 0 : totalLength / _sections.length;
    isLoaded = true;
  }

  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        // Keep alphanumeric English words and Arabic characters
        .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1 && !_stopWords.contains(w))
        .toList();
  }

  static List<String> expandQuery(String query) {
    final originalTokens = _tokenize(query);
    final Set<String> expandedTokens = {};

    for (final token in originalTokens) {
      expandedTokens.add(token);

      if (_arabicRegex.hasMatch(token)) {
        final normalized = _normalizeArabic(token);
        final stemmed = _stemArabic(normalized);

        final englishTerms = _arabicToEnglishDict[stemmed];
        if (englishTerms != null) {
          expandedTokens.addAll(englishTerms.map((t) => t.toLowerCase()));
        }
        expandedTokens.add(normalized);
        expandedTokens.add(stemmed);
      } else {
        final synonyms = _englishSynonyms[token];
        if (synonyms != null) {
          expandedTokens.addAll(synonyms);
        }
      }
    }
    return expandedTokens.toList();
  }

  double _idf(String term) {
    final n = _invertedIndex[term]?.length ?? 0;
    final N = _sections.length;
    return log(1.0 + (N - n + 0.5) / (n + 0.5));
  }

  double _bm25Score(int i, List<String> queryTokens) {
    double score = 0;
    final docLen = _docLengths[i];
    final termFreqs = _docTermFrequencies[i];

    for (final qt in queryTokens) {
      final tf = termFreqs[qt]?.toDouble() ?? 0.0;
      if (tf > 0) {
        final idf = _idf(qt);
        final numerator = tf * (_k1 + 1);
        final denominator = tf + _k1 * (1.0 - _b + _b * (docLen / _avgDocLength));
        score += idf * (numerator / denominator);
      }
    }
    return score;
  }

  List<SearchResult> search(String query, {int topK = 5}) {
    if (!isLoaded || query.trim().isEmpty) return [];
    final queryTokens = expandQuery(query);
    if (queryTokens.isEmpty) return [];

    final scored = <SearchResult>[];
    for (int i = 0; i < _sections.length; i++) {
      final s = _bm25Score(i, queryTokens);
      if (s > 0) {
        scored.add(SearchResult(text: _sections[i], score: s, index: i));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    // Deduplicate very similar results
    final results = <SearchResult>[];
    for (final r in scored) {
      bool tooSimilar = false;
      for (final existing in results) {
        if (_similarity(r.text, existing.text) > 0.7) {
          tooSimilar = true;
          break;
        }
      }
      if (!tooSimilar) results.add(r);
      if (results.length >= topK) break;
    }
    return results;
  }

  double _similarity(String a, String b) {
    final aWords = _tokenize(a).toSet();
    final bWords = _tokenize(b).toSet();
    final intersection = aWords.intersection(bWords).length;
    final union = aWords.union(bWords).length;
    return union == 0 ? 0 : intersection / union;
  }
}

class SearchResult {
  final String text;
  final double score;
  final int index;
  SearchResult({required this.text, required this.score, required this.index});
}

enum ChatMode {
  offlineSearch,
  aiAssistant,
}

enum AssistantMode {
  aiConsultant,
  standardsReference,
  implementationRoadmap,
  documentGenerator,
  documentReview,
  evidenceGenerator,
  taskPlanner,
  trainingAssistant,
  gapAnalysis,
}

enum AccreditationDocType {
  policy,
  procedure,
  plan,
  program,
  guideline,
  sop,
  checklist,
  form,
  riskAssessment,
  jobDescription,
  emergencyPlan,
  trainingPlan,
  auditPlan,
  qualityPlan,
}

extension AccreditationDocTypeExt on AccreditationDocType {
  String get label {
    switch (this) {
      case AccreditationDocType.policy:
        return 'Policy / سياسة';
      case AccreditationDocType.procedure:
        return 'Procedure / إجراء';
      case AccreditationDocType.plan:
        return 'Plan / خطة';
      case AccreditationDocType.program:
        return 'Program / برنامج';
      case AccreditationDocType.guideline:
        return 'Guideline / دليل إرشادي';
      case AccreditationDocType.sop:
        return 'SOP / خطوات عمل معيارية';
      case AccreditationDocType.checklist:
        return 'Checklist / قائمة تحقق';
      case AccreditationDocType.form:
        return 'Form / نموذج';
      case AccreditationDocType.riskAssessment:
        return 'Risk Assessment / تقييم مخاطر';
      case AccreditationDocType.jobDescription:
        return 'Job Description / وصف وظيفي';
      case AccreditationDocType.emergencyPlan:
        return 'Emergency Plan / خطة طوارئ';
      case AccreditationDocType.trainingPlan:
        return 'Training Plan / خطة تدريب';
      case AccreditationDocType.auditPlan:
        return 'Audit Plan / خطة تدقيق';
      case AccreditationDocType.qualityPlan:
        return 'Quality Plan / خطة جودة';
    }
  }
}

class AssistantToolInfo {
  final AssistantMode mode;
  final String title;
  final String arabicTitle;
  final String description;
  final IconData icon;
  final Color accentColor;

  const AssistantToolInfo({
    required this.mode,
    required this.title,
    required this.arabicTitle,
    required this.description,
    required this.icon,
    required this.accentColor,
  });
}

const List<AssistantToolInfo> kAssistantTools = [
  AssistantToolInfo(
    mode: AssistantMode.aiConsultant,
    title: 'AI Consultant',
    arabicTitle: 'مستشار الاعتماد',
    description: 'Ask any question on GAHAR standards and get expert accreditation advice.',
    icon: Icons.psychology_rounded,
    accentColor: Color(0xFF7C6FF7),
  ),
  AssistantToolInfo(
    mode: AssistantMode.standardsReference,
    title: 'Standard Explainer',
    arabicTitle: 'شرح المعايير',
    description: 'Deep 6-part explanation of standard purpose, why required, and surveyor findings.',
    icon: Icons.menu_book_rounded,
    accentColor: Color(0xFF03DAC6),
  ),
  AssistantToolInfo(
    mode: AssistantMode.implementationRoadmap,
    title: '10-Step Roadmap',
    arabicTitle: 'خطة التطبيق العملي',
    description: 'Actionable 10-step implementation roadmap from committee to monitoring.',
    icon: Icons.alt_route_rounded,
    accentColor: Color(0xFFFFB74D),
  ),
  AssistantToolInfo(
    mode: AssistantMode.documentGenerator,
    title: 'Document Generator',
    arabicTitle: 'منشئ الوثائق والمعايير',
    description: 'Generates 14+ GAHAR compliant policies, SOPs, plans, & risk assessments.',
    icon: Icons.description_rounded,
    accentColor: Color(0xFF4FC3F7),
  ),
  AssistantToolInfo(
    mode: AssistantMode.documentReview,
    title: 'Document Auditor',
    arabicTitle: 'مراجعة وتدقيق الوثائق',
    description: 'Audit any document text against GAHAR, get a Compliance Score % & gaps.',
    icon: Icons.fact_check_rounded,
    accentColor: Color(0xFFE57373),
  ),
  AssistantToolInfo(
    mode: AssistantMode.evidenceGenerator,
    title: 'Evidence Checklist',
    arabicTitle: 'أدلة الإثبات',
    description: 'Required accreditation evidence checklist (minutes, logs, competency).',
    icon: Icons.inventory_2_rounded,
    accentColor: Color(0xFF81C784),
  ),
  AssistantToolInfo(
    mode: AssistantMode.taskPlanner,
    title: 'Task & Action Planner',
    arabicTitle: 'مخطط المهام والمسؤوليات',
    description: 'Converts standards into department-level tasks, priorities, & due dates.',
    icon: Icons.task_alt_rounded,
    accentColor: Color(0xFFBA68C8),
  ),
  AssistantToolInfo(
    mode: AssistantMode.trainingAssistant,
    title: 'Training Assistant',
    arabicTitle: 'حزمة التدريب والتقييم',
    description: 'Generates staff training plan, slide outline, 5-question quiz, & competency checklist.',
    icon: Icons.model_training_rounded,
    accentColor: Color(0xFFFF8A65),
  ),
  AssistantToolInfo(
    mode: AssistantMode.gapAnalysis,
    title: 'Gap & Risk Analysis',
    arabicTitle: 'تحليل الفجوات والمخاطر',
    description: 'Evaluates status vs. GAHAR, risk levels (High/Med/Low), & CAPA action plan.',
    icon: Icons.analytics_rounded,
    accentColor: Color(0xFF4DB6AC),
  ),
];

// ─── Chat Message Model ───────────────────────────────────────────────────────
class ChatMessage {
  final String text;
  final bool isUser;
  final List<SearchResult> results;
  final bool isAi;
  final AssistantMode? assistantMode;

  const ChatMessage({
    required this.text,
    required this.isUser,
    this.results = const [],
    this.isAi = false,
    this.assistantMode,
  });
}

// ─── Highlight Text Widget ───────────────────────────────────────────────────
class HighlightText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  final Color highlightColor;

  const HighlightText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    if (query.trim().isEmpty) {
      return Text(text, style: style);
    }

    final tokens = BylawsSearchEngine.expandQuery(query);
    if (tokens.isEmpty) {
      return Text(text, style: style);
    }

    // Sort tokens by length descending to match glowing keywords
    tokens.sort((a, b) => b.length.compareTo(a.length));

    // Escape tokens for Regex
    final pattern = tokens
        .map((t) => RegExp.escape(t))
        .where((t) => t.isNotEmpty)
        .join('|');

    if (pattern.isEmpty) {
      return Text(text, style: style);
    }

    final regex = RegExp('\\b($pattern)', caseSensitive: false);

    final List<TextSpan> spans = [];
    int start = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: TextStyle(
          backgroundColor: highlightColor,
          fontWeight: FontWeight.bold,
          color: style.color,
        ),
      ));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(
        style: style,
        children: spans,
      ),
    );
  }
}

// ─── App Entry Point ──────────────────────────────────────────────────────────
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<MyAppState>();

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  bool get isDark => _themeMode == ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "GAHAR AI Accreditation Platform",
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const SplashView(),
    );
  }
}

// ─── Splash Screen View ───────────────────────────────────────────────────────
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.7, curve: Curves.easeIn)),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack)),
    );

    _controller.forward();

    // Navigate after 2 seconds
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      final token = await StorageService.getAuthToken();
      final user = await StorageService.getUserProfile();
      if (!mounted) return;

      Widget initialScreen;
      if (token == null || token.isEmpty) {
        initialScreen = LoginScreen(
          onLoginSuccess: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (ctx) => MainNavigationShell(
                  onThemeToggle: () => MyApp.of(ctx)?.toggleTheme(),
                  isDark: MyApp.of(ctx)?.isDark ?? true,
                ),
              ),
            );
          },
        );
      } else if (user?.role == UserRole.superAdmin) {
        initialScreen = SuperAdminScreen(
          onLogout: () {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (ctx) => const SplashView(),
              ),
            );
          },
        );
      } else {
        initialScreen = MainNavigationShell(
          onThemeToggle: () => MyApp.of(context)?.toggleTheme(),
          isDark: MyApp.of(context)?.isDark ?? true,
        );
      }

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              initialScreen,
          transitionsBuilder:
              (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07070E),
      body: Stack(
        children: [
          Positioned(
            top: -120,
            left: -120,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.2),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.primaryLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.4),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.health_and_safety_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          "GAHAR PLATFORM",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Healthcare Accreditation Enterprise AI",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.6),
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Main Navigation Shell ───────────────────────────────────────────────────
class MainNavigationShell extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDark;

  const MainNavigationShell({
    super.key,
    required this.onThemeToggle,
    required this.isDark,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      const ComplianceDashboardScreen(),
      ChatScreen(
        onThemeToggle: widget.onThemeToggle,
        isDark: widget.isDark,
      ),
      const ApplicabilityScreen(),
      const GapAnalysisScreen(),
      const ActionPlansScreen(),
      const DocumentLibraryScreen(),
      const EvidenceTrackerScreen(),
      const LicensesScreen(),
      const SurveyPrepScreen(),
      const ExpertsHubScreen(),
      FacilitySettingsScreen(
        onLogout: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (ctx) => const SplashView(),
            ),
          );
        },
      ),
    ];

    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: AppColors.primary),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.health_and_safety_rounded, size: 48, color: Colors.white),
                  SizedBox(height: 10),
                  Text(
                    'GAHAR Platform',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Accreditation Modules',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            _buildDrawerTile(0, 'Dashboard', Icons.dashboard_rounded),
            _buildDrawerTile(1, 'AI Assistant / Chat', Icons.smart_toy_rounded),
            _buildDrawerTile(2, 'Requirements Applicability', Icons.rule_rounded),
            _buildDrawerTile(3, 'Gap Analysis Engine', Icons.analytics_rounded),
            _buildDrawerTile(4, 'Action Plan Manager', Icons.task_alt_rounded),
            _buildDrawerTile(5, 'Document Library (v1.0)', Icons.folder_rounded),
            _buildDrawerTile(6, 'Evidence Tracker', Icons.fact_check_rounded),
            _buildDrawerTile(7, 'Licenses Tracker', Icons.badge_rounded),
            _buildDrawerTile(8, 'Survey Preparation', Icons.verified_user_rounded),
            _buildDrawerTile(9, 'Accreditation Experts Hub', Icons.people_alt_rounded),
            const Divider(),
            _buildDrawerTile(10, 'Facility Settings & Team', Icons.settings_rounded),
          ],
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex > 4 ? 0 : _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy_rounded),
            label: 'AI Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.rule_outlined),
            selectedIcon: Icon(Icons.rule_rounded),
            label: 'Requirements',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics_rounded),
            label: 'Gaps',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: 'Library',
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerTile(int index, String title, IconData icon) {
    final isSelected = _currentIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppColors.primary : Colors.grey),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.primary : null,
        ),
      ),
      selected: isSelected,
      onTap: () {
        Navigator.pop(context);
        setState(() => _currentIndex = index);
      },
    );
  }
}

// ─── Chat Screen ──────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDark;

  const ChatScreen({
    super.key, 
    required this.onThemeToggle, 
    required this.isDark,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final BylawsSearchEngine _engine = BylawsSearchEngine();
  final List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterTts _tts = FlutterTts();
  bool _loading = true;
  ChatMode _chatMode = ChatMode.aiAssistant;
  AssistantMode _activeAssistantMode = AssistantMode.aiConsultant;
  AccreditationDocType _selectedDocType = AccreditationDocType.policy;
  bool _aiLoading = false;

  static const List<String> _suggestions = [
    "What are patient and family rights in GAHAR standards?",
    "What is the informed consent process (PCC.06)?",
    "How does GAHAR define patient-centered care?",
    "What evidence is required for Infection Control (IPC.01)?",
  ];

  @override
  void initState() {
    super.initState();
    _engine.load().then((_) => setState(() => _loading = false));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _tts.stop();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _buildPromptForMode({
    required AssistantMode mode,
    required String query,
    required String context,
    String? docType,
    String? pastedDocument,
  }) {
    switch (mode) {
      case AssistantMode.aiConsultant:
        return '''
You are a Senior Healthcare Accreditation Consultant specializing in GAHAR (General Authority for Healthcare Accreditation and Regulation) 2025 Standards.
Your role is to guide healthcare organizations through accreditation compliance, offering expert, authoritative, and practical advice.

Use the provided GAHAR Standards Context to answer the user's question accurately.
If the context contains relevant GAHAR Safety Requirements (GSRs), Evidence of Compliance (EOCs), or standards, cite them explicitly (e.g., GSR.01, PCC.06, SAS.03).
Structure your response professionally using headers, bullet points, and clear explanations.
Answer in the same language as the user's inquiry (Arabic or English).

[GAHAR STANDARDS CONTEXT]:
$context

[USER QUESTION]:
$query
''';

      case AssistantMode.standardsReference:
        return '''
You are a GAHAR Accreditation Standards Expert.
The user wants a deep, structured explanation of a GAHAR standard or requirement related to: "$query".

Using the provided GAHAR Standards Context, generate a comprehensive 6-part reference guide:

1. 📌 **Simple Explanation (الشرح المبسط)**: Explain the standard in clear, accessible language.
2. 🎯 **Purpose & Rationale (الهدف والأهمية)**: Why does GAHAR mandate this standard? What patient safety / quality dimension does it address?
3. ⚖️ **Why Required (سبب الوجوب والالزام)**: Statutory, ethical, or safety justification.
4. 🛠️ **How to Implement (خطوات التطبيق)**: Practical step-by-step guidance for hospital staff.
5. ⚠️ **Common Implementation Mistakes (أخطاء شائعة)**: Frequent pitfalls observed during hospital surveys.
6. 🔍 **Surveyor Observations & Scoring (ما يفحصه المقيم)**: What evidence, documents, and staff interviews GAHAR surveyors check to award a "Met (2/2)" score.

[GAHAR STANDARDS CONTEXT]:
$context
''';

      case AssistantMode.implementationRoadmap:
        return '''
You are an Accreditation Implementation Manager.
Generate an actionable **10-Step Implementation Roadmap** for complying with GAHAR standards related to: "$query".

Structure the output as a practical project plan with 10 clear phases:
1. 👥 **Phase 1: Responsible Committee Formation (تشكيل اللجنة/الفريق المسؤول)**
2. 👤 **Phase 2: Staff & Role Assignments (تحديد المسؤوليات والوظائف)**
3. 🤝 **Phase 3: Initial Alignment & Meetings (الاجتماعات الأولية)**
4. 📄 **Phase 4: Document Preparation (إعداد السياسات ودلائل العمل)**
5. ✍️ **Phase 5: Governance & Leadership Approval (الاعتماد الإداري)**
6. 🎓 **Phase 6: Staff Education & Training (تدريب العاملين)**
7. 🚀 **Phase 7: Process Rollout & Operationalization (التطبيق والتنفيذ)**
8. 📊 **Phase 8: Monitoring & Indicator Tracking (المتابعة ومؤشرات الأداء)**
9. 📁 **Phase 9: Accreditation Evidence Collection (جمع أدلة الإثبات)**
10. 🔄 **Phase 10: Evaluation & Continuous Improvement (المراجعة والتحسين)**

Base every phase on the retrieved GAHAR Standards Context:
$context
''';

      case AssistantMode.documentGenerator:
        final documentName = docType ?? "Policy & Procedure";
        return '''
You are a Healthcare Quality Document Author specialized in GAHAR Accreditation.
Generate a complete, publication-ready **$documentName** compliant with GAHAR Accreditation Standards for: "$query".

Format the document using standard professional healthcare governance layout:

---
# 🏥 [HEALTHCARE FACILITY NAME]
## DOCUMENT TYPE: ${documentName.toUpperCase()}
**Title**: [Professional Document Title]
**Document Code**: GAHAR-DOC-001
**Effective Date**: March 2025 | **Review Cycle**: Annual | **Version**: 1.0
**Target Departments**: All Applicable Hospital Departments

---
### 1. 📌 SCOPE & APPLICABILITY (النطاق والتطبيق)
### 2. 🎯 PURPOSE & INTENT (الهدف والغرض)
### 3. 📖 DEFINITIONS & ACRONYMS (التعاريف والمصطلحات)
### 4. ⚖️ POLICY STATEMENT & CORE PRINCIPLES (السياسة والترخيص)
### 5. 🛠️ OPERATIONAL PROCEDURES & WORKFLOW (إجراءات العمل الفعالة)
### 6. 👥 RESPONSIBILITIES & ROLES (المسؤوليات والأدوار)
### 7. 📊 MONITORING, KPI & COMPLIANCE (المتابعة ومؤشرات الأداء)
### 8. 📁 RELATED FORMS & RECORDS (النماذج والأدلة ذات الصلة)
### 9. 📚 GAHAR REFERENCES & CODES (المراجع ومعايير جهار)

Ensure all content directly reflects official GAHAR principles from this context:
$context
''';

      case AssistantMode.documentReview:
        final docToReview = pastedDocument ?? query;
        return '''
You are a Chief GAHAR Accreditation Surveyor and Auditor.
Conduct a rigorous **Document Compliance Audit** on the following hospital document against GAHAR Standards:

---
[DOCUMENT TO AUDIT]:
$docToReview
---

[GAHAR REFERENCE STANDARDS CONTEXT]:
$context

Provide a comprehensive Audit Report containing:

1. 📊 **COMPLIANCE SCORE (درجة التوافق)**: `[Score 0-100%]` (Met / Partially Met / Unmet)
2. ✅ **COMPLIANT ELEMENTS FOUND (نقاط القوة والتوافق)**
3. ❌ **MISSING REQUIREMENTS & GAPS (الثغرات والمتطلبات الناقصة)**
4. ⚠️ **SURVEYOR FINDINGS & RISK LEVEL (ملاحظات المقيم ومستوى الخطورة)**
5. 💡 **ACTIONABLE REVISION RECOMMENDATIONS (التوصيات والتعديلات المطلوبة)**
''';

      case AssistantMode.evidenceGenerator:
        return '''
You are a GAHAR Accreditation Evidence Coordinator.
Generate a complete **Accreditation Evidence Checklist (قائمة أدلة الإثبات للجمهور والمقيم)** for: "$query".

Categorize the required evidence items into:
1. 📝 **Governance & Authorization Evidence (أدلة التراخيص والاعتمادات)**
2. 🤝 **Meeting Minutes & Records (محاضر الاجتماعات اللجان)**
3. 🎓 **Staff Competency & Training Evidence (أدلة تدريب وتقييم الكوادر)**
4. 📋 **Operational Logs & Checklists (سجلات التنفيذ وسجلات الفحص)**
5. 📊 **Monitoring & KPI Reports (تقارير المؤشرات والتحسين)**

Ground all items in retrieved GAHAR context:
$context
''';

      case AssistantMode.taskPlanner:
        return '''
You are a Quality & Accreditation Project Planner.
Convert GAHAR requirements for "$query" into an **Actionable Task Breakdown & Committee Assignment Matrix**.

Generate a structured task table and breakdown:

| Task ID | Actionable Task | Responsible Department | Assigned Role | Priority | Due Window | Required Evidence | Committee Approval |
|---------|-----------------|------------------------|---------------|----------|------------|-------------------|--------------------|

Followed by detailed implementation notes for each task.

Reference GAHAR Context:
$context
''';

      case AssistantMode.trainingAssistant:
        return '''
You are a Healthcare Staff Training Coordinator for GAHAR Standards.
Generate a complete **Staff Education & Competency Pack** for: "$query".

Include 5 complete modules:
1. 📅 **Training Plan & Target Audience (خطة التدريب والفئات المستهدفة)**
2. 🖥️ **Presentation Slides Outline (محتوى شرائح العرض - 5 شرائح)**
3. ✍️ **Attendance Log Format (نموذج كشف الحضور)**
4. 📝 **5-Question Staff Evaluation Quiz with Answer Key (اختبار تقييم استيعاب من 5 أسئلة مع الإجابات النموذجية)**
5. 📋 **Staff Competency Assessment Checklist (قائمة تقييم الجدارة الفردية الميدانية)**

Alignment with GAHAR Standards Context:
$context
''';

      case AssistantMode.gapAnalysis:
        return '''
You are an Accreditation Risk & Gap Analysis Specialist.
Perform a **Gap Analysis & Risk Matrix Evaluation** for an organization implementing GAHAR standards for: "$query".

Provide a structured report:
1. 🔍 **Current State vs GAHAR Requirement Assessment (تقييم الوضع الحالي مقارنة بالمعيار)**
2. ⚠️ **Gap Identification & Missing Controls (تحديد الفجوات والقصور)**
3. 🎯 **Risk Matrix (مصفوفة المخاطر - Impact vs Likelihood)**
4. 📌 **Priority Matrix (أولويات المعالجة)**
5. 🚀 **Corrective & Preventive Action Plan - CAPA (خطة الإجراءات التصحيحية)**

Reference GAHAR Context:
$context
''';
    }
  }

  Future<void> _sendAiQuery(String query, {String? pastedDocument}) async {
    final mode = _activeAssistantMode;
    final docType = _selectedDocType.label;

    setState(() {
      _messages.add(ChatMessage(
        text: pastedDocument != null
            ? '🔍 Auditing Document: "${query.isEmpty ? "Submitted Document" : query}"'
            : query,
        isUser: true,
      ));
      _aiLoading = true;
    });
    _scrollToBottom();

    try {
      final groqKey = await AppSettings.getGroqKey();

      if (groqKey.isEmpty) {
        throw Exception(
          'Groq API key is not set.\n'
          'Please open Settings (⚙️) and enter your Groq API key.\n\n'
          'Get a free key from: console.groq.com',
        );
      }

      // RAG Retrieval from GAHAR Handbook
      final searchResults = _engine.search(
          query.isEmpty ? "GAHAR Hospital Accreditation Standards 2025" : query,
          topK: 5);
      final context = searchResults.isNotEmpty
          ? searchResults.map((r) => r.text).join('\n\n')
          : 'GAHAR Hospital Accreditation Standards 2025 General Requirements.';

      final userPromptContent = _buildPromptForMode(
        mode: mode,
        query: query,
        context: context,
        docType: docType,
        pastedDocument: pastedDocument,
      );

      final httpResponse = await http
          .post(
            Uri.parse(AppSettings.groqEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $groqKey',
            },
            body: jsonEncode({
              'model': AppSettings.model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You are an expert Healthcare Accreditation Assistant for GAHAR 2025 Standards. Provide structured, authoritative, and practical guidance.',
                },
                {
                  'role': 'user',
                  'content': userPromptContent,
                },
              ],
              'max_tokens': 2048,
              'temperature': 0.3,
            }),
          )
          .timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw Exception(
              'Request timed out. Please check your internet connection.',
            ),
          );

      if (httpResponse.statusCode != 200) {
        final errorBody = jsonDecode(httpResponse.body);
        final errorMsg = errorBody['error']?['message'] ?? httpResponse.body;
        throw Exception('Groq API error: $errorMsg');
      }

      final data = jsonDecode(httpResponse.body) as Map<String, dynamic>;
      final reply = data['choices']?[0]?['message']?['content'] as String? ??
          'No response generated.';

      setState(() {
        _messages.add(ChatMessage(
          text: reply,
          isUser: false,
          isAi: true,
          assistantMode: mode,
        ));
        _aiLoading = false;
      });
    } catch (e) {
      String errMsg = e.toString();
      if (errMsg.startsWith('Exception: ')) errMsg = errMsg.substring(11);
      setState(() {
        _messages.add(ChatMessage(
          text: '❌ Error: $errMsg',
          isUser: false,
          isAi: true,
          assistantMode: mode,
        ));
        _aiLoading = false;
      });
    }
    _scrollToBottom();
  }

  void _sendMessage([String? prefilledText]) {
    final query = (prefilledText ?? _controller.text).trim();
    if (query.isEmpty || _loading || _aiLoading) return;
    _controller.clear();

    if (_chatMode == ChatMode.aiAssistant) {
      if (_activeAssistantMode == AssistantMode.documentReview) {
        _showDocumentReviewSheet(initialTopic: query);
      } else {
        _sendAiQuery(query);
      }
    } else {
      final results = _engine.search(query, topK: 4);

      setState(() {
        _messages.add(ChatMessage(text: query, isUser: true));
        _messages.add(ChatMessage(
          text: query,
          isUser: false,
          results: results,
          isAi: false,
        ));
      });
      _scrollToBottom();
    }
  }

  void _showDocumentReviewSheet({String? initialTopic}) {
    final docController = TextEditingController();
    final topicController = TextEditingController(text: initialTopic ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16162A) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF7C6FF7).withValues(alpha: 0.2)
                    : const Color(0xFF5B4FCF).withValues(alpha: 0.15),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Icon(Icons.fact_check_rounded,
                          color: cs.primary, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        'Audit Existing Document',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Paste your hospital policy or procedure text below. The AI will audit it against official GAHAR 2025 standards and provide a Compliance Score (0-100%) and gap recommendations.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: topicController,
                    decoration: InputDecoration(
                      labelText: 'Standard / Topic Title (Optional)',
                      hintText:
                          'e.g. Infection Control Policy, Patient Consent',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF0B0B16)
                          : const Color(0xFFF3F3FA),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: docController,
                    maxLines: 7,
                    decoration: InputDecoration(
                      labelText: 'Paste Document Content Here',
                      hintText:
                          'Paste policy text, SOP steps, or procedure details...',
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF0B0B16)
                          : const Color(0xFFF3F3FA),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () {
                      final docText = docController.text.trim();
                      if (docText.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Please paste document content to audit.')),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      setState(() {
                        _chatMode = ChatMode.aiAssistant;
                        _activeAssistantMode = AssistantMode.documentReview;
                      });
                      _sendAiQuery(
                        topicController.text.trim().isEmpty
                            ? 'Document Audit'
                            : topicController.text.trim(),
                        pastedDocument: docText,
                      );
                    },
                    icon: const Icon(Icons.analytics_rounded),
                    label: const Text('Audit Document Compliance'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showSaveDocumentDialog(ChatMessage msg) {
    final titleController = TextEditingController(
      text: '${_selectedDocType.label} - GAHAR Compliance',
    );

    showDialog(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return AlertDialog(
          title: const Text('Save to Document Library'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Document Title',
                  filled: true,
                  fillColor:
                      isDark ? const Color(0xFF16162A) : const Color(0xFFF3F3FA),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Type: ${_selectedDocType.label}',
                style: TextStyle(
                    fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final doc = SavedDocument(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  title: titleController.text.trim().isEmpty
                      ? 'Saved GAHAR Document'
                      : titleController.text.trim(),
                  content: msg.text,
                  docType: _selectedDocType.label,
                  standard: 'GAHAR 2025',
                  department: 'General Hospital',
                  createdAt: DateTime.now(),
                );
                await StorageService.saveDocument(doc);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Document saved to Library! 📁'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.bookmark_added_rounded, size: 16),
              label: const Text('Save Document'),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.setLanguage("en-US");
    await _tts.speak(text);
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AppSettingsSheet(),
    );
  }

  // Beautiful background with slow-bleeding color gradients and radial blobs
  Widget _buildGlowingBackground(BuildContext context, bool isDark) {
    if (!isDark) {
      return Container(
        color: const Color(0xFFF4F4FA),
      );
    }
    return Container(
      color: const Color(0xFF07070E),
      child: Stack(
        children: [
          // Glowing Indigo orb top right
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7C6FF7).withValues(alpha: 0.14),
              ),
            ),
          ),
          // Glowing Cyan orb bottom left
          Positioned(
            bottom: -120,
            left: -120,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF03DAC6).withValues(alpha: 0.09),
              ),
            ),
          ),
          // Blur backdrop
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeTool = kAssistantTools.firstWhere(
      (t) => t.mode == _activeAssistantMode,
      orElse: () => kAssistantTools.first,
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [activeTool.accentColor, cs.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: activeTool.accentColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(activeTool.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("GAHAR Assistant",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  _loading
                      ? "Loading GAHAR Standards..."
                      : (_chatMode == ChatMode.offlineSearch
                          ? "✓ Offline BM25 Search"
                          : "⚡ ${activeTool.title} Mode"),
                  style: TextStyle(
                      fontSize: 10.5,
                      color: _loading
                          ? cs.onSurface.withValues(alpha: 0.4)
                          : cs.secondary,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_chatMode == ChatMode.offlineSearch
                ? Icons.smart_toy_outlined
                : Icons.manage_search_rounded),
            onPressed: () {
              setState(() {
                _chatMode = _chatMode == ChatMode.offlineSearch
                    ? ChatMode.aiAssistant
                    : ChatMode.offlineSearch;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_chatMode == ChatMode.offlineSearch
                      ? "Switched to Offline BM25 Search"
                      : "Switched to AI Accreditation Assistant"),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: _chatMode == ChatMode.offlineSearch
                ? "Switch to AI Assistant"
                : "Switch to Offline Search",
          ),
          IconButton(
            icon: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => MyApp.of(context)?.toggleTheme(),
            tooltip: "Toggle Theme",
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showSettingsSheet,
            tooltip: "Settings",
          ),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => setState(() => _messages.clear()),
              tooltip: "Clear History",
            ),
        ],
      ),
      body: Stack(
        children: [
          _buildGlowingBackground(context, isDark),
          SafeArea(
            child: Column(
              children: [
                if (_chatMode == ChatMode.aiAssistant) _buildToolSelectorBar(cs),
                if (_chatMode == ChatMode.aiAssistant &&
                    _activeAssistantMode == AssistantMode.documentGenerator)
                  _buildDocTypeSubBar(cs),
                Expanded(
                  child: _loading
                      ? _buildLoadingView(cs)
                      : _messages.isEmpty
                          ? _buildWelcomeView(cs)
                          : _buildChatList(cs),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildInputBar(cs),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolSelectorBar(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: kAssistantTools.length,
        itemBuilder: (context, index) {
          final tool = kAssistantTools[index];
          final isSelected = tool.mode == _activeAssistantMode;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: Icon(
                tool.icon,
                size: 16,
                color: isSelected ? Colors.white : tool.accentColor,
              ),
              label: Text(tool.title),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
              selected: isSelected,
              selectedColor: tool.accentColor,
              backgroundColor: isDark
                  ? const Color(0xFF16162A).withValues(alpha: 0.7)
                  : Colors.white,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _activeAssistantMode = tool.mode;
                  });
                  if (tool.mode == AssistantMode.documentReview) {
                    _showDocumentReviewSheet();
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildDocTypeSubBar(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: AccreditationDocType.values.length,
        itemBuilder: (context, index) {
          final docType = AccreditationDocType.values[index];
          final isSelected = docType == _selectedDocType;

          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(docType.label, style: const TextStyle(fontSize: 11)),
              selected: isSelected,
              selectedColor: cs.primary.withValues(alpha: 0.3),
              backgroundColor: isDark
                  ? const Color(0xFF121224)
                  : const Color(0xFFEFEFF8),
              onSelected: (selected) {
                if (selected) {
                  setState(() => _selectedDocType = docType);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingView(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
          ),
          const SizedBox(height: 20),
          Text(
            "Loading GAHAR Accreditation Handbook...",
            style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeView(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primary, cs.secondary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.health_and_safety_rounded,
                    size: 42, color: Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                "GAHAR AI Accreditation Assistant",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Complete AI suite for GAHAR 2025 Hospital Accreditation compliance.\nSearch, explain standards, generate policies, audit docs & plan tasks.",
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    height: 1.4,
                    fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _featureChip(cs, Icons.menu_book, "GAHAR 2025 RAG"),
            const SizedBox(width: 8),
            _featureChip(cs, Icons.auto_awesome, "Groq AI Engine"),
            const SizedBox(width: 8),
            _featureChip(cs, Icons.description, "14+ Doc Generators"),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Accreditation AI Assistant Suite:",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black87,
                  fontSize: 13.5),
            ),
            Text(
              "Tap to launch",
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black45),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Responsive Grid of 9 Assistant Tools
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth > 650;
            final crossCount = isDesktop ? 3 : 2;
            final ratio = isDesktop ? 1.6 : 1.15;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: ratio,
              ),
              itemCount: kAssistantTools.length,
              itemBuilder: (context, index) {
                final tool = kAssistantTools[index];
                return _buildToolCard(tool, cs);
              },
            );
          },
        ),
        const SizedBox(height: 20),
        // Audit Banner Shortcut
        InkWell(
          onTap: () => _showDocumentReviewSheet(),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFE57373).withValues(alpha: 0.15),
                  cs.primary.withValues(alpha: 0.15)
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFE57373).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.fact_check_rounded,
                    color: Color(0xFFE57373), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Audit Existing Hospital Document",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Paste any policy text to analyze compliance against GAHAR & get a score %",
                        style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "Quick Questions:",
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 13),
        ),
        const SizedBox(height: 8),
        ..._suggestions.map((s) => _buildSuggestionTile(s, cs)),
      ],
    );
  }

  Widget _buildToolCard(AssistantToolInfo tool, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = tool.mode == _activeAssistantMode;

    return InkWell(
      onTap: () {
        setState(() {
          _chatMode = ChatMode.aiAssistant;
          _activeAssistantMode = tool.mode;
        });
        if (tool.mode == AssistantMode.documentReview) {
          _showDocumentReviewSheet();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Activated ${tool.title} Mode. Type a topic below!"),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? tool.accentColor.withValues(alpha: 0.25)
              : (isDark
                  ? const Color(0xFF16162A).withValues(alpha: 0.6)
                  : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? tool.accentColor
                : (isDark
                    ? const Color(0xFF7C6FF7).withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08)),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tool.accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(tool.icon, color: tool.accentColor, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              tool.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tool.arabicTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featureChip(ColorScheme cs, IconData icon, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E38).withValues(alpha: 0.5)
            : cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? const Color(0xFF7C6FF7).withValues(alpha: 0.15)
              : cs.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: cs.primary),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  color: isDark ? Colors.white70 : cs.primary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildSuggestionTile(String text, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _sendMessage(text),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark
                  ? const Color(0xFF7C6FF7).withValues(alpha: 0.15)
                  : cs.outline.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(16),
            color: isDark
                ? const Color(0xFF16162A).withValues(alpha: 0.5)
                : cs.surface.withValues(alpha: 0.6),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.8)
                        : Colors.black87,
                  ),
                ),
              ),
              Icon(Icons.north_west_rounded,
                  size: 13,
                  color: isDark ? Colors.white30 : Colors.black26),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatList(ColorScheme cs) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: _messages.length + (_aiLoading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) {
          return _buildThinkingBubble(cs);
        }
        final msg = _messages[i];
        if (msg.isUser) {
          return _buildUserBubble(msg, cs);
        } else if (msg.isAi) {
          return _buildAiResponseBubble(msg, cs);
        } else {
          return _buildResultCard(msg, cs);
        }
      },
    );
  }

  Widget _buildThinkingBubble(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF16162A).withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.9),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(
            color: isDark
                ? const Color(0xFF7C6FF7).withValues(alpha: 0.15)
                : const Color(0xFF5B4FCF).withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            WidgetToAnimateGlow(
              child: SizedBox(
                width: 14,
                height: 14,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "Generating Accreditation Response...",
              style: TextStyle(
                  fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiResponseBubble(ChatMessage msg, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modeInfo = kAssistantTools.firstWhere(
      (t) => t.mode == msg.assistantMode,
      orElse: () => kAssistantTools.first,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF16162A).withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(
            color: modeInfo.accentColor.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(modeInfo.icon, size: 16, color: modeInfo.accentColor),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: modeInfo.accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    modeInfo.title,
                    style: TextStyle(
                      fontSize: 11,
                      color: modeInfo.accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                  onPressed: () => _showSaveDocumentDialog(msg),
                  tooltip: "Save to Library",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.share_outlined, size: 17),
                  onPressed: () =>
                      ExportService.sharePdf(modeInfo.title, msg.text),
                  tooltip: "Export / Share PDF",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: msg.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Copied response to clipboard!"),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  tooltip: "Copy Text",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _speak(msg.text),
                  child: Icon(Icons.volume_up_outlined,
                      size: 16, color: cs.primary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              msg.text,
              style: TextStyle(
                  fontSize: 13.5,
                  color: isDark ? const Color(0xFFE0E0E0) : Colors.black87,
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBubble(ChatMessage msg, ColorScheme cs) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C6FF7), Color(0xFF5A4FCF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C6FF7).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
    );
  }

  Widget _buildResultCard(ChatMessage msg, ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (msg.results.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF381C1C).withValues(alpha: 0.5) : const Color(0xFFFFDADA),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(
              color: isDark ? const Color(0xFFE57373).withValues(alpha: 0.2) : const Color(0xFFFF8A80),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.search_off_rounded, color: isDark ? const Color(0xFFE57373) : const Color(0xFFC62828), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "No results found in the bylaws for: \"${msg.text}\"\n\nTry different keywords.",
                  style: TextStyle(color: isDark ? const Color(0xFFE57373) : const Color(0xFFC62828), fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.95),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 14, color: cs.secondary),
                  const SizedBox(width: 6),
                  Text(
                    "Found ${msg.results.length} relevant section${msg.results.length > 1 ? 's' : ''}",
                    style: TextStyle(fontSize: 12, color: cs.secondary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ...msg.results.asMap().entries.map((entry) {
              final i = entry.key;
              final r = entry.value;
              return _buildSectionCard(r, i, cs, msg.text);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(SearchResult result, int index, ColorScheme cs, String query) {
    final relevance = min(result.score / 10.0, 1.0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16162A).withValues(alpha: 0.6) : const Color(0xFFFFFFFF).withValues(alpha: 0.8),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(index == 0 ? 4 : 16),
          topRight: const Radius.circular(18),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(18),
        ),
        border: Border.all(
          color: isDark ? const Color(0xFF7C6FF7).withValues(alpha: 0.15) : const Color(0xFF5B4FCF).withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: HighlightText(
              text: result.text,
              query: query,
              style: TextStyle(fontSize: 13.5, color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87, height: 1.55),
              highlightColor: cs.primary.withValues(alpha: 0.2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: relevance.clamp(0.1, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: cs.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "${(relevance * 100).round()}% match",
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black45),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _speak(result.text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.volume_up_rounded, size: 13, color: cs.primary),
                        const SizedBox(width: 4),
                        Text("Read", style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(ColorScheme cs) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Context-aware placeholder text based on active mode
    String hintText;
    IconData prefixIcon;
    if (_loading) {
      hintText = "Loading GAHAR Accreditation Handbook...";
      prefixIcon = Icons.hourglass_empty_rounded;
    } else if (_chatMode == ChatMode.offlineSearch) {
      hintText = "Search GAHAR standards (IPC, PCC, GSR...)";
      prefixIcon = Icons.search_rounded;
    } else {
      switch (_activeAssistantMode) {
        case AssistantMode.aiConsultant:
          hintText = "Ask any accreditation question...";
          prefixIcon = Icons.psychology_rounded;
        case AssistantMode.standardsReference:
          hintText = "Enter standard code or topic (e.g. PCC.06)...";
          prefixIcon = Icons.menu_book_rounded;
        case AssistantMode.implementationRoadmap:
          hintText = "Enter standard to generate 10-step roadmap...";
          prefixIcon = Icons.alt_route_rounded;
        case AssistantMode.documentGenerator:
          hintText = "Enter topic to generate ${_selectedDocType.label}...";
          prefixIcon = Icons.description_rounded;
        case AssistantMode.documentReview:
          hintText = "Tap to open document audit panel...";
          prefixIcon = Icons.fact_check_rounded;
        case AssistantMode.evidenceGenerator:
          hintText = "Enter standard to generate evidence checklist...";
          prefixIcon = Icons.inventory_2_rounded;
        case AssistantMode.taskPlanner:
          hintText = "Enter standard to generate task & responsibility plan...";
          prefixIcon = Icons.task_alt_rounded;
        case AssistantMode.trainingAssistant:
          hintText = "Enter topic to generate training & competency pack...";
          prefixIcon = Icons.model_training_rounded;
        case AssistantMode.gapAnalysis:
          hintText = "Enter standard for gap analysis & risk matrix...";
          prefixIcon = Icons.analytics_rounded;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF16162A).withValues(alpha: 0.85)
            : const Color(0xFFFFFFFF).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? const Color(0xFF7C6FF7).withValues(alpha: 0.2)
              : const Color(0xFF5B4FCF).withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _sendMessage(),
              enabled: !_loading,
              style: TextStyle(
                  fontSize: 14, color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white30 : Colors.black38),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: false,
                prefixIcon: Icon(prefixIcon,
                    color: isDark ? Colors.white30 : Colors.black38, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [cs.primary, cs.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _loading ? null : () => _sendMessage(),
              icon: Icon(
                _chatMode == ChatMode.offlineSearch ? Icons.search_rounded : Icons.send_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// A simple widget to bypass indicator warnings
class WidgetToAnimateGlow extends StatelessWidget {
  final Widget child;
  const WidgetToAnimateGlow({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

// ─── Settings Modal Sheet Widget ──────────────────────────────────────────────
class AppSettingsSheet extends StatefulWidget {
  const AppSettingsSheet({super.key});

  @override
  State<AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<AppSettingsSheet> {
  final _urlController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final key = await AppSettings.getGroqKey();
    setState(() {
      _urlController.text = key;
    });
  }

  Future<void> _saveSettings() async {
    final key = _urlController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Groq API key.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (!key.startsWith('gsk_')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid key. Groq keys start with "gsk_"'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _saving = true);
    await AppSettings.setGroqKey(key);
    setState(() => _saving = false);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Groq API key saved! AI Assistant is ready ✅'),
          backgroundColor: Color(0xFF5B4FCF),
        ),
      );
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16162A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark
                ? const Color(0xFF7C6FF7).withValues(alpha: 0.15)
                : const Color(0xFF5B4FCF).withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Title row
            Row(
              children: [
                Icon(Icons.vpn_key_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Text(
                  'AI Settings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Info card
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AccrediGo AI Copilot operates securely through your enterprise backend server. API keys and credentials remain server-side.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Groq API Key field
            Text(
              'Groq API Key',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.visiblePassword,
              obscureText: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? const Color(0xFF0B0B16) : const Color(0xFFF3F3FA),
                hintText: 'gsk_xxxxxxxxxxxxxxxxxxxxxxxx',
                hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                prefixIcon: Icon(Icons.key_rounded, color: cs.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveSettings,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save API Key'),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: () {},
                child: Text(
                  'Get a FREE Groq key → console.groq.com',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    decoration: TextDecoration.underline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
