// =============================================================================
// GAHAR Healthcare Accreditation Platform - Document Generation & Library Service
// Enterprise Document Lifecycle, Version Control & Approval Workflow
// =============================================================================

const { query, isDbConnected, isProduction } = require('./db');
const { getExcludedStandardsSet } = require('./applicability_service');
const { v4: uuidv4 } = require('uuid');

// Master GAHAR Document Definitions Catalog
const GAHAR_DOC_CATALOG = [
  {
    docCode: 'GAHAR-POL-GSR-01',
    standardCode: 'GSR.01',
    docType: 'Policy',
    category: 'Patient Safety / سلامة المرضى',
    titleEn: 'Patient Identification Policy & Procedure',
    titleAr: 'سياسة وإجراءات التحقق من هوية المرضى بدقة',
    descriptionEn: 'Defines two distinct patient identifiers (Full Name & Medical Record Number) across all diagnostic and clinical touchpoints.',
    descriptionAr: 'تحدد وسيلتي تعريف للمريض (الاسم الرباعي والرقم الطبي) في جميع الإجراءات التشخيصية والعلاجية لمنع أخطاء الهوية.',
    reviewCycleMonths: 12,
    mandatorySections: ['Purpose', 'Scope', 'Policy Statement', 'Two Identifiers Rule', 'Special Circumstances (Comatose/Neonates)', 'Responsibilities', 'KPI Monitoring'],
  },
  {
    docCode: 'GAHAR-SOP-GSR-02',
    standardCode: 'GSR.02',
    docType: 'Procedure',
    category: 'Clinical Communication / التواصل السريري',
    titleEn: 'Verbal and Telephone Orders Verification (Read-Back) SOP',
    titleAr: 'إجراءات قبول وتنفيذ الأوامر الشفهية والهاتفية مع إعادة القراءة والتحقق',
    descriptionEn: 'Rigorous standard operating procedure restricting verbal orders to emergencies and enforcing Write-down, Read-back, and Counter-signing within 24 hours.',
    descriptionAr: 'إجراءات تشغيلية معيارية تقيد الأوامر الشفهية بحالات الطوارئ مع الإلزام بالتدوين، وإعادة القراءة والتأكيد، والتوقيع خلال 24 ساعة.',
    reviewCycleMonths: 12,
    mandatorySections: ['Purpose', 'Scope', 'Emergency Indications', 'Write-Down & Read-Back Workflow', 'Counter-Signature Timeframe', 'Prohibited Verbal Orders'],
  },
  {
    docCode: 'GAHAR-SOP-GSR-03',
    standardCode: 'GSR.03',
    docType: 'Procedure',
    category: 'Diagnostic Safety / السلامة التشخيصية',
    titleEn: 'Critical Diagnostic Results Escalation & Reporting SOP',
    titleAr: 'إجراءات الإبلاغ الفوري والتصعيد للنتائج الحرجة للمختبر والأشعة',
    descriptionEn: 'Standard procedure defining critical laboratory and imaging thresholds with mandatory notification within 30 minutes and closed-loop confirmation.',
    descriptionAr: 'تحديد القيم والنتائج الحرجة لفحوصات المختبر والأشعة مع الإلزام بالإبلاغ خلال 30 دقيقة والتأكيد المزدوج.',
    reviewCycleMonths: 12,
    mandatorySections: ['Definitions of Critical Limits', 'Notification Window (≤30 min)', 'Responsible Informant & Recipient', 'Documentation Log', 'Escalation Protocol'],
  },
  {
    docCode: 'GAHAR-POL-GSR-05',
    standardCode: 'GSR.05',
    docType: 'Policy',
    category: 'Patient Safety / سلامة المرضى',
    titleEn: 'Inpatient Fall Screening, Assessment & Prevention Policy',
    titleAr: 'سياسة تقييم مخاطر السقوط والوقاية منه للمرضى الداخليين',
    descriptionEn: 'Comprehensive fall risk screening at admission and transfer using validated scales (Morse / Hendrich II) with individualized care plans.',
    descriptionAr: 'تقييم شامل لمخاطر السقوط عند الدخول والنقل باستخدام مقياس مورس أو هندريش، مع خطط رعاية فردية وشارات التحذير.',
    reviewCycleMonths: 12,
    mandatorySections: ['Screening Schedule', 'Risk Assessment Scales', 'Universal Precautions', 'High Risk Interventions', 'Post-Fall Management Protocol'],
  },
  {
    docCode: 'GAHAR-POL-GSR-06',
    standardCode: 'GSR.06',
    docType: 'Policy',
    category: 'Clinical Care / الرعاية السريرية',
    titleEn: 'Pressure Injury Prevention & Staging Protocol',
    titleAr: 'سياسة الوقاية من قرح الفراش والضغط وإعادة التقييم الدوري',
    descriptionEn: 'Braden scale risk evaluation upon admission, mandatory repositioning schedule every 2 hours, and dynamic pressure-relieving surfaces.',
    descriptionAr: 'تقييم المخاطر بمقياس برادين، وتغيير وضعية المريض كل ساعتين، واستخدام المراتب الهوائية الديناميكية لتخفيف الضغط.',
    reviewCycleMonths: 12,
    mandatorySections: ['Braden Assessment Timing', 'Repositioning Guidelines', 'Skin Inspection & Nutrition Support', 'Wound Staging Classification'],
  },
  {
    docCode: 'GAHAR-POL-GSR-07',
    standardCode: 'GSR.07',
    docType: 'Policy',
    category: 'Clinical Care / الرعاية السريرية',
    titleEn: 'Venous Thromboembolism (VTE) Risk Assessment & Prophylaxis Policy',
    titleAr: 'سياسة تقييم مخاطر التجلط الوريدي والوقاية منه للمرضى البالغين',
    descriptionEn: 'Caprini / Padua scoring for all hospitalized adult patients with pharmacological and mechanical thromboprophylaxis protocols.',
    descriptionAr: 'تقييم كابريني أو بادوا لجميع المرضى البالغين مع بروتوكولات الوقاية الدوائية والميكانيكية والمتابعة المستمرة.',
    reviewCycleMonths: 12,
    mandatorySections: ['Mandatory Assessment Triggers', 'Scoring Stratification', 'Contraindications to Anticoagulation', 'Mechanical Prophylaxis Protocols'],
  },
  {
    docCode: 'GAHAR-POL-GSR-14',
    standardCode: 'GSR.14',
    docType: 'Policy',
    category: 'Surgical Safety / السلامة الجراحية',
    titleEn: 'Surgical Site Marking & Verification Policy',
    titleAr: 'سياسة التحديد الدقيق لموقع الإجراء الجراحي والتداخلي',
    descriptionEn: 'Enforces unambiguous surgical site marking by the operating surgeon before patient sedation, involving the patient/guardian.',
    descriptionAr: 'إلزام الجراح المسؤول بتحديد موقع العملية الجراحية بعلامة واضحة قبل التخدير، وبمشاركة المريض أو وليه.',
    reviewCycleMonths: 12,
    mandatorySections: ['Who Marks the Site', 'Approved Marker Type & Symbol', 'Exemptions (Single Organ/Teeth)', 'Patient Participation Rule'],
  },
  {
    docCode: 'GAHAR-FRM-GSR-15',
    standardCode: 'GSR.15',
    docType: 'Form',
    category: 'Surgical Safety / السلامة الجراحية',
    titleEn: 'WHO Surgical Safety Checklist (Sign-In, Time-Out, Sign-Out)',
    titleAr: 'قائمة التحقق من أمان الجراحة (ما قبل التخدير، مهلة التوقف، ما قبل الخروج)',
    descriptionEn: 'Three-phase surgical safety verification checklist conducted verbally by the circulating nurse and multidisciplinary surgical team.',
    descriptionAr: 'استمارة التحقق من أمان الجراحة ذات الثلاث مراحل للتأكد من هوية المريض، الموقع، الأدوية، وحصر الشاش والأدوات.',
    reviewCycleMonths: 12,
    mandatorySections: ['Sign-In Checks (Before Anesthesia)', 'Time-Out Protocol (Before Incision)', 'Sign-Out Checks (Before Leaving OR)', 'Team Signatures'],
  },
  {
    docCode: 'GAHAR-POL-GSR-18',
    standardCode: 'GSR.18',
    docType: 'Policy',
    category: 'Medication Safety / سلامة الأدوية',
    titleEn: 'Medication Reconciliation & Best Possible Medication History (BPMH)',
    titleAr: 'سياسة مطابقة الأدوية وتوثيق أفضل تاريخ دوائي ممكن للمريض',
    descriptionEn: 'Standard procedure for recording pre-admission medications within 24 hours and reconciling discrepancies at admission, transfer, and discharge.',
    descriptionAr: 'حصر ومطابقة جميع الأدوية التي يتناولها المريض قبل الدخول خلال 24 ساعة ومطابقتها عند التحويل والخروج.',
    reviewCycleMonths: 12,
    mandatorySections: ['BPMH Collection Methodology', 'Clinical Pharmacist Role', 'Reconciliation at Transition Points', 'Patient Discharge Counseling'],
  },
  {
    docCode: 'GAHAR-POL-GSR-20',
    standardCode: 'GSR.20',
    docType: 'Policy',
    category: 'Medication Safety / سلامة الأدوية',
    titleEn: 'High-Alert Medications & Concentrated Electrolytes Management',
    titleAr: 'سياسة إدارة وتداول الأدوية عالية الخطورة والمحاليل المركزة',
    descriptionEn: 'Restricts concentrated electrolytes from patient wards, enforces independent double-check verification, and mandates distinctive auxiliary warning labels.',
    descriptionAr: 'حظر تخزين المحاليل المركزة في الأجنحة العادية، والإلزام بالتحقق المزدوج المستقل، ووضع ملصقات تحذيرية مميزة.',
    reviewCycleMonths: 12,
    mandatorySections: ['High-Alert Drug Master List', 'Storage & Segregation Rules', 'Independent Double-Check Protocol', 'Auxiliary Warning Labels'],
  },
  {
    docCode: 'GAHAR-POL-GSR-22',
    standardCode: 'GSR.22',
    docType: 'Policy',
    category: 'Infection Control / مكافحة العدوى',
    titleEn: 'Hand Hygiene Program & Multimodal Compliance Monitoring',
    titleAr: 'سياسة وبرنامج نظافة وتطهير الأيدي وفق إرشادات منظمة الصحة العالمية',
    descriptionEn: 'Implements the WHO 5 Moments of Hand Hygiene, alcohol rub availability at point of care, and direct observational compliance audits.',
    descriptionAr: 'تطبيق اللحظات الخمس لنظافة الأيدي، وتوفير مطهرات الكحول عند نقاط الرعاية، وإجراء جولات تدقيق الملاحظة المباشرة.',
    reviewCycleMonths: 12,
    mandatorySections: ['WHO 5 Moments', 'Handrub vs Handwash Indications', 'Point-of-Care Sanitizer Placement', 'Monthly Observational Audits & KPIs'],
  },
  {
    docCode: 'GAHAR-PLN-GSR-23',
    standardCode: 'GSR.23',
    docType: 'Plan',
    category: 'Facility Safety / سلامة المنشأة',
    titleEn: 'Fire Safety, Life Safety & Emergency Evacuation Plan',
    titleAr: 'خطة سلامة الحياة ومكافحة الحريق والإخلاء الطارئ للمنشأة',
    descriptionEn: 'RACE & PASS response protocols, clear egress corridor maintenance, quarterly fire drills, and compartmentation smoke barrier inspection.',
    descriptionAr: 'بروتوكولات RACE و PASS للاستجابة للحريق، وإخلاء المرضى، وتدريبات الإخلاء ربع السنوية، وصيانة كواشف وأجهزة الإطفاء.',
    reviewCycleMonths: 12,
    mandatorySections: ['RACE & PASS Actions', 'Evacuation Triage Priority', 'Fire Drill Schedule & Scenario Log', 'Zone Smoke Barriers Maintenance'],
  },
  {
    docCode: 'GAHAR-POL-QPI-01',
    standardCode: 'QPI.01',
    docType: 'Policy',
    category: 'Quality Governance / حوكمة الجودة',
    titleEn: 'Multidisciplinary Quality, Patient Safety & Risk Management Committee Charter',
    titleAr: 'ميثاق ولائحة عمل لجنة الجودة وسلامة المرضى وإدارة المخاطر',
    descriptionEn: 'Defines the composition, leadership, voting rules, meeting frequency, and reporting mechanisms of the hospital quality improvement committee.',
    descriptionAr: 'تحدد تشكيل، واجتماعات، ومسؤوليات، وآليات تقارير لجنة الجودة الشاملة وسلامة المرضى وإدارة المخاطر للمستشفى.',
    reviewCycleMonths: 12,
    mandatorySections: ['Committee Purpose', 'Membership & Quorum', 'Monthly Meeting Cadence', 'Duties & Responsibilities', 'Annual Quality Plan Approval'],
  },
  {
    docCode: 'GAHAR-POL-ATH-01',
    standardCode: 'ATH.01',
    docType: 'Policy',
    category: 'Academic & Training / التدريب والتعليم',
    titleEn: 'Clinical Trainees, Interns & Residents Supervision Policy',
    titleAr: 'سياسة الإشراف السريري وتحديد صلاحيات أطباء الامتياز والمتدربين',
    descriptionEn: 'Establishes clear levels of direct and indirect clinical supervision for trainees and residents to safeguard patient safety.',
    descriptionAr: 'تضع مستويات محددة للإشراف السريري المباشر وغير المباشر على الأطباء المتدربين والامتياز لضمان سلامة المرضى.',
    reviewCycleMonths: 12,
    mandatorySections: ['Supervision Levels (Direct/Indirect)', 'Prohibited Independent Procedures', 'Consultant Oversight Responsibilities', 'Credentialing & Evaluation'],
  }
];

// In-memory generated documents store for dev/testing
const memoryDocs = new Map();
const memoryVersions = new Map();

/**
 * Get all document catalog items with applicability calculation for tenant
 */
async function getCatalogWithApplicability(facilityId) {
  const excludedSet = await getExcludedStandardsSet(facilityId);

  return GAHAR_DOC_CATALOG.map(doc => {
    const isApplicable = !excludedSet.has(doc.standardCode);
    return {
      ...doc,
      isApplicable,
      statusLabel: isApplicable ? 'Applicable / مطلوب' : 'Non-Applicable / غير مطلوب',
    };
  });
}

/**
 * Get facility generated documents list
 */
async function getFacilityDocuments(facilityId, { category, standardCode, status } = {}) {
  let docs = [];

  if (isProduction && !isDbConnected()) {
    throw new Error('Database service unavailable in production.');
  }

  if (isDbConnected()) {
    try {
      let sql = 'SELECT * FROM generated_documents WHERE facility_id = $1';
      const params = [facilityId];

      if (category) {
        params.push(category);
        sql += ` AND metadata->>'category' = $${params.length}`;
      }
      if (standardCode) {
        params.push(standardCode);
        sql += ` AND standard_code = $${params.length}`;
      }
      if (status) {
        params.push(status);
        sql += ` AND status = $${params.length}`;
      }

      sql += ' ORDER BY updated_at DESC';
      const res = await query(sql, params);
      if (res && res.rows) {
        docs = res.rows;
      }
    } catch (e) {
      console.warn('DB getFacilityDocuments failed:', e.message);
      if (isProduction) {
        throw new Error('Database query error while loading documents in production.');
      }
    }
  }

  if (!isProduction && docs.length === 0 && memoryDocs.has(facilityId)) {
    docs = memoryDocs.get(facilityId);
  }

  return docs;
}

/**
 * Draft / Generate a Document with Pre-Question Customization
 */
async function generateDocumentDraft({
  facilityId,
  facilityName,
  standardCode,
  docCode,
  wizardAnswers = {},
  authorUser,
}) {
  const catalogItem = GAHAR_DOC_CATALOG.find(d => d.docCode === docCode || d.standardCode === standardCode);
  if (!catalogItem) {
    throw new Error(`Standard or document definition not found: ${standardCode || docCode}`);
  }

  const effectiveDate = wizardAnswers.effectiveDate || new Date().toISOString().split('T')[0];
  const revisionPeriod = wizardAnswers.reviewCycle || '12 Months';
  const targetDepartment = wizardAnswers.targetDepartment || wizardAnswers.department || 'All Hospital Clinical & Ancillary Departments';
  const ownerTitle = wizardAnswers.ownerTitle || wizardAnswers.documentOwner || 'Quality Director & Relevant Department Head';
  const committeeName = wizardAnswers.committeeName || 'Quality, Patient Safety & Risk Management Committee';

  // Construct structured professional GAHAR accreditation document
  const documentContent = `
================================================================================
🏥 ${facilityName.toUpperCase()}
HEALTHCARE ACCREDITATION POLICY & PROCEDURE SYSTEM
COMPLIANT WITH GAHAR 2025 HEALTHCARE STANDARDS
================================================================================

DOCUMENT METADATA:
--------------------------------------------------------------------------------
Document Code      : ${catalogItem.docCode}
Related Standard   : GAHAR Standard Ref: ${catalogItem.standardCode}
Document Title (EN): ${catalogItem.titleEn}
Document Title (AR): ${catalogItem.titleAr}
Document Type      : ${catalogItem.docType}
Effective Date     : ${effectiveDate}
Review Cycle       : ${revisionPeriod}
Approved Version   : v1.0 (Initial GAHAR Audit Draft)
Target Scope       : ${targetDepartment}
Governance Body    : ${committeeName}
Document Owner     : ${ownerTitle}
--------------------------------------------------------------------------------

1. 📌 PURPOSE & INTENT (الهدف والغرض):
To establish an uncompromised, standardized institutional mechanism at ${facilityName} for ${catalogItem.titleEn.toLowerCase()}, in strict conformance with GAHAR Egyptian Healthcare Accreditation Authority requirements.

2. 🌐 SCOPE OF APPLICABILITY (نطاق التطبيق):
This document applies across ${targetDepartment} to all healthcare practitioners, credentialed medical staff, nursing personnel, administrative personnel, and visiting contractors.

3. ⚖️ POLICY STATEMENT (نص السياسة الإلزامية):
It is the mandatory policy of ${facilityName} that ${catalogItem.descriptionEn}
جميع العاملين ملزمون بالامتثال التام للإجراءات الموضحة أدناه، ويعتبر أي انحراف عن هذا البروتوكول مخالفة لمعايير سلامة المرضى تستوجب التحقيق الفوري وفق نظام الإبلاغ عن الحوادث العارضة.

4. 🛠️ OPERATIONAL PROCEDURES & CLINICAL WORKFLOW (خطوات التنفيذ والإجراءات):
4.1 Preparation & Initial Verification:
    - Designated personnel shall ensure all required equipment, forms, and safety equipment are accessible prior to patient contact.
    - Two active identifiers must be independently verified and cross-referenced with the medical record.

4.2 Execution Protocols:
    - Perform all steps in accordance with approved clinical practice guidelines and evidence-based standards.
    - Document every action with exact timestamp, signature, and professional credential ID.

4.3 Emergency & Exceptional Circumstances:
    - In urgent situations, adhere to rapid intervention pathways approved by the ${committeeName}.
    - Ensure closed-loop verbal confirmation and counter-signing within designated timeframes.

5. 👥 ROLES & RESPONSIBILITIES (المسؤوليات والصلاحيات):
- Hospital Leadership: Provides adequate resources, staffing, and engineering controls.
- ${ownerTitle}: Supervises departmental compliance and conducts monthly audits.
- Frontline Staff: Executes the protocol without deviation and reports near-misses.
- Quality & Patient Safety Team: Analyzes compliance metrics and prepares quarterly board reports.

6. 📊 KEY PERFORMANCE INDICATORS & MONITORING (مؤشرات الأداء والمتابعة):
- Indicator 1: Monthly compliance rate with ${catalogItem.titleEn} (Target: ≥95%).
- Indicator 2: Number of reported variance incidents or near-miss events.
- Audit Frequency: Monthly spot-checks with documented feedback to department heads.

7. 📁 ASSOCIATED FORMS, RECORDS & REFERENCES (النماذج والمراجع):
- GAHAR Hospital Accreditation Handbook 2025 (Edition 2).
- Related Standard Evidence: ${catalogItem.standardCode}.
- Incident Reporting Form (OVR) & Corrective Action Plan.

================================================================================
APPROVAL & GOVERNANCE SIGN-OFF:
Prepared by: ${authorUser?.fullName || 'Quality Coordinator'} | Date: ${effectiveDate}
Reviewed by: ${ownerTitle} | Date: ${effectiveDate}
Approved by: Chief Executive Officer / Medical Director | Status: DRAFT PENDING REVIEW
================================================================================
`;

  const newDoc = {
    id: uuidv4(),
    facility_id: facilityId,
    standard_code: catalogItem.standardCode,
    doc_type: catalogItem.docType,
    doc_code: catalogItem.docCode,
    title: catalogItem.titleEn,
    content: documentContent.trim(),
    version: 'v1.0',
    status: 'DRAFT',
    metadata: {
      category: catalogItem.category,
      titleAr: catalogItem.titleAr,
      effectiveDate,
      reviewCycle: revisionPeriod,
      targetDepartment,
      ownerTitle,
      committeeName,
      wizardAnswers,
    },
    created_by: authorUser?.id || null,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  if (isProduction && !isDbConnected()) {
    throw new Error('Database service unavailable in production.');
  }

  if (isDbConnected()) {
    try {
      const res = await query(`
        INSERT INTO generated_documents (
          id, facility_id, standard_code, doc_type, doc_code, title, content, version, status, metadata, created_by, created_at, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW(), NOW())
        RETURNING *
      `, [
        newDoc.id,
        newDoc.facility_id,
        newDoc.standard_code,
        newDoc.doc_type,
        newDoc.doc_code,
        newDoc.title,
        newDoc.content,
        newDoc.version,
        newDoc.status,
        JSON.stringify(newDoc.metadata),
        newDoc.created_by,
      ]);

      // Save initial version record
      await query(`
        INSERT INTO document_versions (document_id, facility_id, version, content, change_summary, author_id, created_at)
        VALUES ($1, $2, 'v1.0', $3, 'Initial document generation via GAHAR wizard', $4, NOW())
      `, [newDoc.id, facilityId, newDoc.content, newDoc.created_by]);

      return res.rows[0];
    } catch (e) {
      console.warn('DB generateDocumentDraft failed:', e.message);
      if (isProduction) {
        throw new Error('Database insert error while generating document draft in production.');
      }
    }
  }

  // Fallback to memory (non-production only)
  if (!memoryDocs.has(facilityId)) memoryDocs.set(facilityId, []);
  memoryDocs.get(facilityId).unshift(newDoc);

  return newDoc;
}

/**
 * Save an edited version of an existing document
 */
async function saveDocumentVersion({
  documentId,
  facilityId,
  content,
  changeSummary,
  authorUser,
}) {
  let doc = null;

  if (isDbConnected()) {
    const res = await query('SELECT * FROM generated_documents WHERE id = $1 AND facility_id = $2', [documentId, facilityId]);
    if (res && res.rows.length > 0) {
      doc = res.rows[0];
    }
  } else if (!isProduction && memoryDocs.has(facilityId)) {
    doc = memoryDocs.get(facilityId).find(d => d.id === documentId);
  }

  if (!doc) {
    throw new Error('Document not found or access denied');
  }

  // Calculate next version: v1.0 -> v1.1
  const currentVersion = doc.version || 'v1.0';
  const match = currentVersion.match(/v(\d+)\.(\d+)/);
  let nextVersion = 'v1.1';
  if (match) {
    const major = parseInt(match[1], 10);
    const minor = parseInt(match[2], 10) + 1;
    nextVersion = `v${major}.${minor}`;
  }

  if (isDbConnected()) {
    // Insert new version history
    await query(`
      INSERT INTO document_versions (document_id, facility_id, version, content, change_summary, author_id, created_at)
      VALUES ($1, $2, $3, $4, $5, $6, NOW())
    `, [documentId, facilityId, nextVersion, content, changeSummary || 'Document updated by user', authorUser?.id || null]);

    // Update document head
    const updateRes = await query(`
      UPDATE generated_documents
      SET content = $1, version = $2, status = 'DRAFT', updated_at = NOW()
      WHERE id = $3 AND facility_id = $4
      RETURNING *
    `, [content, nextVersion, documentId, facilityId]);

    return updateRes.rows[0];
  }

  // Memory fallback
  doc.content = content;
  doc.version = nextVersion;
  doc.status = 'DRAFT';
  doc.updated_at = new Date().toISOString();
  return doc;
}

/**
 * Update Document Approval Status
 */
async function updateDocumentApprovalStatus({
  documentId,
  facilityId,
  status, // 'SUBMITTED_FOR_REVIEW', 'APPROVED', 'REJECTED', 'REVISION_REQUIRED'
  reviewerUser,
  rejectionReason,
}) {
  const allowed = ['DRAFT', 'SUBMITTED_FOR_REVIEW', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'REVISION_REQUIRED', 'ARCHIVED'];
  if (!allowed.includes(status)) {
    throw new Error(`Invalid status: ${status}`);
  }

  if (isDbConnected()) {
    const res = await query(`
      UPDATE generated_documents
      SET status = $1,
          approved_by = CASE WHEN $1 = 'APPROVED' THEN $2 ELSE approved_by END,
          approved_at = CASE WHEN $1 = 'APPROVED' THEN NOW() ELSE approved_at END,
          updated_at = NOW()
      WHERE id = $3 AND facility_id = $4
      RETURNING *
    `, [status, reviewerUser?.id || null, documentId, facilityId]);

    return res.rows[0];
  }

  if (!isProduction && memoryDocs.has(facilityId)) {
    const doc = memoryDocs.get(facilityId).find(d => d.id === documentId);
    if (doc) {
      doc.status = status;
      doc.updated_at = new Date().toISOString();
      return doc;
    }
  }

  throw new Error('Document not found');
}

/**
 * Get document version history
 */
async function getDocumentVersions(documentId, facilityId) {
  if (isDbConnected()) {
    const res = await query(`
      SELECT v.*, u.full_name as author_name, u.role as author_role
      FROM document_versions v
      LEFT JOIN users u ON v.author_id = u.id
      WHERE v.document_id = $1 AND v.facility_id = $2
      ORDER BY v.created_at DESC
    `, [documentId, facilityId]);
    return res?.rows || [];
  }
  return [];
}

/**
 * Get Document Generation Dashboard Statistics
 */
async function getDocumentDashboard(facilityId) {
  const catalog = await getCatalogWithApplicability(facilityId);
  const facilityDocs = await getFacilityDocuments(facilityId);

  const applicableCatalog = catalog.filter(c => c.isApplicable);
  const nonApplicableCatalog = catalog.filter(c => !c.isApplicable);

  const totalApplicable = applicableCatalog.length;
  const totalNonApplicable = nonApplicableCatalog.length;

  let generatedCount = 0;
  let approvedCount = 0;
  let draftCount = 0;
  let pendingCount = 0;
  let rejectedCount = 0;

  for (const doc of facilityDocs) {
    generatedCount++;
    if (doc.status === 'APPROVED') approvedCount++;
    else if (doc.status === 'DRAFT') draftCount++;
    else if (doc.status === 'SUBMITTED_FOR_REVIEW' || doc.status === 'PENDING_APPROVAL') pendingCount++;
    else if (doc.status === 'REJECTED' || doc.status === 'REVISION_REQUIRED') rejectedCount++;
  }

  const coveragePercentage = totalApplicable > 0 ? Math.min(100, Math.round((approvedCount / totalApplicable) * 100)) : 0;

  return {
    totalCatalog: catalog.length,
    totalApplicable,
    totalNonApplicable,
    generatedCount,
    notGeneratedCount: Math.max(0, totalApplicable - generatedCount),
    approvedCount,
    draftCount,
    pendingCount,
    rejectedCount,
    coveragePercentage,
    catalog: catalog.map(c => {
      const generated = facilityDocs.find(d => d.standard_code === c.standardCode || d.doc_code === c.docCode);
      return {
        ...c,
        isGenerated: Boolean(generated),
        currentDocumentId: generated?.id || null,
        currentStatus: generated?.status || (c.isApplicable ? 'NOT_GENERATED' : 'EXCLUDED'),
        currentVersion: generated?.version || null,
      };
    })
  };
}

module.exports = {
  GAHAR_DOC_CATALOG,
  getCatalogWithApplicability,
  getFacilityDocuments,
  generateDocumentDraft,
  saveDocumentVersion,
  updateDocumentApprovalStatus,
  getDocumentVersions,
  getDocumentDashboard,
};
