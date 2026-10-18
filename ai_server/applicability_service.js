// =============================================================================
// GAHAR Healthcare Accreditation Platform - Applicability Engine
// Grounded in GAHAR Hospital Accreditation Standards & Scope of Service Rules
// =============================================================================

const { query, memoryDb, isDbConnected, isProduction } = require('./db');

const APPLICABILITY_QUESTIONS = [
  {
    id: 'q_radiology',
    category: 'Diagnostic & Imaging / الخدمات التشخيصية والتصويرية',
    titleEn: 'Diagnostic Radiology & Imaging Services (MRI / CT / X-Ray)',
    titleAr: 'خدمات الأشعة التشخيصية والتصوير الطبي (رنين / مقطعية / عادية)',
    descriptionEn: 'Does your facility possess and operate in-house diagnostic radiation, CT, fluoroscopy, or MRI equipment?',
    descriptionAr: 'هل تحتوي المنشأة وتدير أجهزة أشعة تشخيصية أو مقطعية أو رنين مغناطيسي داخلياً؟',
    impactedStandards: ['GSR.12', 'DAS.09', 'DAS.10', 'DAS.11', 'DAS.12', 'DAS.13', 'DAS.14'],
    defaultAnswer: true,
  },
  {
    id: 'q_laboratory',
    category: 'Diagnostic & Imaging / الخدمات التشخيصية والتصويرية',
    titleEn: 'In-House Clinical Laboratory',
    titleAr: 'معمل تحاليل طبية سريري داخلي',
    descriptionEn: 'Does your facility operate an in-house clinical pathology and medical diagnostic laboratory?',
    descriptionAr: 'هل تمتلك المنشأة وتدير معملاً طبياً تشخيصياً وسريرياً داخلياً؟',
    impactedStandards: ['GSR.13', 'DAS.23', 'DAS.24', 'DAS.25', 'DAS.26', 'DAS.27', 'DAS.28'],
    defaultAnswer: true,
  },
  {
    id: 'q_surgical',
    category: 'Surgical & Procedures / الجراحة والإجراءات الباضعة',
    titleEn: 'Operating Theaters & Invasive Procedural Units',
    titleAr: 'غرف العمليات الجراحية والإجراءات التداخلية الباضعة',
    descriptionEn: 'Does your facility perform surgical operations, invasive anesthesia, or day-case procedures?',
    descriptionAr: 'هل تجري المنشأة عمليات جراحية أو تخدير عام أو إجراءات باضعة داخل غرف عمليات؟',
    impactedStandards: ['GSR.14', 'GSR.15', 'GSR.16', 'GSR.17', 'SAS.01', 'SAS.02', 'SAS.03', 'SAS.04', 'SAS.05', 'SAS.06', 'SAS.07', 'SAS.08', 'SAS.09', 'SAS.10'],
    defaultAnswer: true,
  },
  {
    id: 'q_teaching',
    category: 'Academic & Scope / النطاق الأكاديمي والتعليمي',
    titleEn: 'Teaching / University Affiliated Hospital',
    titleAr: 'مستشفى جامعي أو تعليمي معتمد لتدريب الزمالة والامتياز',
    descriptionEn: 'Is your facility designated as a teaching, academic, or residency training hospital?',
    descriptionAr: 'هل المنشأة مصنفة كمستشفى تعليمي أو جامعي بها برامج تدريب أطباء امتياز وزمالة؟',
    impactedStandards: ['ACT.15', 'ACT.16', 'ACT.17'],
    defaultAnswer: false,
  },
  {
    id: 'q_psychiatric',
    category: 'Specialized Care / الرعاية التخصصية',
    titleEn: 'Psychiatric & Mental Health Inpatient Services',
    titleAr: 'خدمات الصحة النفسية والعلاج النفسي الداخلي',
    descriptionEn: 'Does your facility provide inpatient psychiatric, addiction, or dedicated mental health wards?',
    descriptionAr: 'هل تقدم المنشأة خدمات إقامة داخلية للصحة النفسية أو علاج الإدمان؟',
    impactedStandards: ['PCC.20', 'PCC.21', 'PCC.22'],
    defaultAnswer: false,
  },
  {
    id: 'q_emergency',
    category: 'Clinical Units / الأقسام الإكلينيكية',
    titleEn: '24/7 Emergency & Trauma Department',
    titleAr: 'قسم الطوارئ والاستقبال والحوادث (24/7)',
    descriptionEn: 'Does your facility operate an urgent/emergency department receiving acute cases around the clock?',
    descriptionAr: 'هل تدير المنشأة قسم استقبال وطوارئ يستقبل الحالات الحادة على مدار الساعة؟',
    impactedStandards: ['CSS.01', 'CSS.02', 'CSS.03', 'CSS.04'],
    defaultAnswer: true,
  },
  {
    id: 'q_icu',
    category: 'Critical Care / الرعاية المركزة',
    titleEn: 'Intensive Care Units (Adult ICU / PICU / NICU)',
    titleAr: 'وحدات الرعاية المركزة (كبار / أطفال / مبتسرين)',
    descriptionEn: 'Does your facility operate intensive care units with mechanical ventilation capabilities?',
    descriptionAr: 'هل تحتوي المنشأة على وحدات رعاية مركزة مجهزة بأجهزة تنفس صناعي؟',
    impactedStandards: ['CSS.07', 'CSS.08', 'CSS.09'],
    defaultAnswer: true,
  },
  {
    id: 'q_inpatient',
    category: 'Inpatient Facilities / الإقامة الداخلية',
    titleEn: 'Inpatient Hospitalization Wards (Overnight Admissions)',
    titleAr: 'أقسام التنويم والإقامة الداخلية للمرضى',
    descriptionEn: 'Does your facility maintain inpatient beds where patients are hospitalized overnight?',
    descriptionAr: 'هل تحتوي المنشأة على أسرة إقامة وتنويم داخلي يبيت فيها المرضى؟',
    impactedStandards: ['ICD.10', 'ICD.11', 'ICD.12', 'ICD.13'],
    defaultAnswer: true,
  },
  {
    id: 'q_dialysis',
    category: 'Specialized Units / الوحدات التخصصية',
    titleEn: 'Hemodialysis / Renal Care Unit',
    titleAr: 'وحدة الغسيل الكلوي الدموي',
    descriptionEn: 'Does your facility provide hemodialysis services for acute or chronic renal failure patients?',
    descriptionAr: 'هل تقدم المنشأة خدمات الغسيل الكلوي الدموي لمرضى الفشل الكلوي؟',
    impactedStandards: ['CSS.12', 'CSS.13'],
    defaultAnswer: false,
  },
  {
    id: 'q_blood_bank',
    category: 'Ancillary Services / الخدمات المساندة',
    titleEn: 'In-House Blood Bank & Transfusion Service',
    titleAr: 'بنك دم تجميعي أو تخزيني داخلي وخدمات نقل الدم',
    descriptionEn: 'Does your facility store, cross-match, or collect blood and blood components on site?',
    descriptionAr: 'هل تقوم المنشأة بتخزين أو فحص التوافق أو جمع الدم ومشتقاته داخل المنشأة؟',
    impactedStandards: ['DAS.29', 'DAS.30', 'DAS.31'],
    defaultAnswer: true,
  },
  {
    id: 'q_chemotherapy',
    category: 'Oncology / علاج الأورام',
    titleEn: 'Oncology & Chemotherapy Infusion Unit',
    titleAr: 'وحدة إعطاء وتحضير العلاج الكيماوي للأورام',
    descriptionEn: 'Does your facility formulate, handle, or administer hazardous cytotoxic chemotherapy agents?',
    descriptionAr: 'هل تقوم المنشأة بتحضير أو إعطاء العلاج الكيماوي والأدوية عالية السمية الخلوية؟',
    impactedStandards: ['MMS.14', 'MMS.15'],
    defaultAnswer: false,
  },
  {
    id: 'q_radiotherapy',
    category: 'Oncology / علاج الأورام',
    titleEn: 'Radiation Oncology / Linear Accelerator',
    titleAr: 'وحدة العلاج الإشعاعي للأورام (المعجل الخطي)',
    descriptionEn: 'Does your facility have radiotherapy facilities such as linear accelerators or brachytherapy?',
    descriptionAr: 'هل يتوفر بالمنشأة أجهزة علاج إشعاعي خارجي أو داخلي للأورام؟',
    impactedStandards: ['DAS.15', 'DAS.16'],
    defaultAnswer: false,
  }
];

// In-memory store for dev/fallback
const memoryApplicability = new Map();

/**
 * Get all applicability questions
 */
function getApplicabilityQuestions() {
  return APPLICABILITY_QUESTIONS;
}

/**
 * Get answers and calculated excluded standards for a specific facility
 */
async function getFacilityApplicability(facilityId) {
  let answersMap = {};

  if (isDbConnected()) {
    try {
      const res = await query(
        'SELECT question_id, answer, notes FROM facility_applicability WHERE facility_id = $1',
        [facilityId]
      );
      if (res && res.rows) {
        res.rows.forEach(r => {
          answersMap[r.question_id] = r.answer;
        });
      }
    } catch (e) {
      console.warn('Could not read applicability from DB:', e.message);
      if (isProduction) {
        throw new Error('Database query error while loading applicability in production.');
      }
    }
  }

  // Fallback to memory if empty (non-production only)
  if (!isProduction && Object.keys(answersMap).length === 0 && memoryApplicability.has(facilityId)) {
    answersMap = memoryApplicability.get(facilityId);
  }

  // If still empty, populate defaults
  const answers = [];
  const excludedStandardsSet = new Set();

  for (const q of APPLICABILITY_QUESTIONS) {
    const isAnswered = answersMap[q.id] !== undefined;
    const answer = isAnswered ? answersMap[q.id] : q.defaultAnswer;
    answers.push({
      questionId: q.id,
      category: q.category,
      titleEn: q.titleEn,
      titleAr: q.titleAr,
      descriptionEn: q.descriptionEn,
      descriptionAr: q.descriptionAr,
      answer: answer,
      impactedStandards: q.impactedStandards,
    });

    if (answer === false) {
      q.impactedStandards.forEach(std => excludedStandardsSet.add(std));
    }
  }

  const excludedStandards = Array.from(excludedStandardsSet);
  const isCompleted = Object.keys(answersMap).length >= APPLICABILITY_QUESTIONS.length;

  return {
    facilityId,
    isCompleted,
    totalQuestions: APPLICABILITY_QUESTIONS.length,
    answeredCount: Object.keys(answersMap).length,
    answers,
    answersMap,
    excludedStandards,
    excludedCount: excludedStandards.length,
  };
}

/**
 * Save applicability answers for a facility
 * Supports either an Array of { questionId, answer } or a Map of { [questionId]: boolean }
 */
async function saveFacilityApplicability(facilityId, answersInput) {
  let normalizedList = [];
  const answersMap = {};

  if (Array.isArray(answersInput)) {
    for (const item of answersInput) {
      if (item && item.questionId) {
        const val = Boolean(item.answer);
        answersMap[item.questionId] = val;
        normalizedList.push({
          questionId: item.questionId,
          answer: val,
          notes: item.notes || null,
        });
      }
    }
  } else if (answersInput && typeof answersInput === 'object') {
    for (const [qId, val] of Object.entries(answersInput)) {
      const boolVal = Boolean(val);
      answersMap[qId] = boolVal;
      normalizedList.push({
        questionId: qId,
        answer: boolVal,
        notes: null,
      });
    }
  }

  if (normalizedList.length < APPLICABILITY_QUESTIONS.length) {
    // Fill in defaults for any missing questions so it is a complete set
    for (const q of APPLICABILITY_QUESTIONS) {
      if (answersMap[q.id] === undefined) {
        answersMap[q.id] = q.defaultAnswer;
        normalizedList.push({
          questionId: q.id,
          answer: q.defaultAnswer,
          notes: null,
        });
      }
    }
  }

  if (isProduction && !isDbConnected()) {
    throw new Error('Database service unavailable in production.');
  }

  if (isDbConnected()) {
    for (const item of normalizedList) {
      await query(`
        INSERT INTO facility_applicability (facility_id, question_id, answer, notes, updated_at)
        VALUES ($1, $2, $3, $4, NOW())
        ON CONFLICT (facility_id, question_id) DO UPDATE SET
          answer = EXCLUDED.answer,
          notes = EXCLUDED.notes,
          updated_at = NOW()
      `, [facilityId, item.questionId, Boolean(item.answer), item.notes || null]);
    }
  }

  if (!isProduction) {
    memoryApplicability.set(facilityId, answersMap);
  }

  return await getFacilityApplicability(facilityId);
}

/**
 * Returns Set of excluded standards for tenant
 */
async function getExcludedStandardsSet(facilityId) {
  const result = await getFacilityApplicability(facilityId);
  return new Set(result.excludedStandards);
}

module.exports = {
  APPLICABILITY_QUESTIONS,
  getApplicabilityQuestions,
  getFacilityApplicability,
  saveFacilityApplicability,
  getExcludedStandardsSet,
};
