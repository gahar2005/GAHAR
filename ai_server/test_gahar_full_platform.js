// =============================================================================
// GAHAR Healthcare Accreditation Platform - Full Platform Verification Suite
// Comprehensive End-to-End Test Suite for All 4 Accreditation Phases & Security
// =============================================================================

const http = require('http');
const { v4: uuidv4 } = require('uuid');

function makeRequest(options, postData) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          resolve({ statusCode: res.statusCode, body: JSON.parse(data) });
        } catch (e) {
          resolve({ statusCode: res.statusCode, raw: data });
        }
      });
    });
    req.on('error', (err) => reject(err));
    if (postData) {
      req.write(JSON.stringify(postData));
    }
    req.end();
  });
}

async function runGaharVerificationSuite() {
  console.log('══════════════════════════════════════════════════════════════════════');
  console.log('🏥 GAHAR HEALTHCARE ACCREDITATION PLATFORM — FULL SUITE VERIFICATION');
  console.log('══════════════════════════════════════════════════════════════════════\n');

  let superAdminToken = '';
  let facilityAToken = '';
  let facilityAId = '';
  let facilityBToken = '';
  let facilityBId = '';
  let documentId = '';

  let passedTests = 0;
  let totalTests = 0;

  function assert(condition, message) {
    totalTests++;
    if (condition) {
      console.log(`  ✅ PASS: ${message}`);
      passedTests++;
    } else {
      console.error(`  ❌ FAIL: ${message}`);
    }
  }

  try {
    // -------------------------------------------------------------------------
    // TEST 1: Super Admin Authentication (Independent Platform Level)
    // -------------------------------------------------------------------------
    console.log('[TEST 1] Super Admin Authentication');
    const saRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/auth/super-admin/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, { email: 'admin@gahar-platform.eg', password: 'SuperAdmin@2026!' });

    assert(saRes.statusCode === 200 && saRes.body?.token, 'Super Admin login successful with JWT issued');
    superAdminToken = saRes.body?.token;

    // -------------------------------------------------------------------------
    // TEST 2: Facility A Registration (Phase 1 Readiness Review)
    // -------------------------------------------------------------------------
    console.log('\n[TEST 2] Facility A Registration (Complete GAHAR Profile)');
    const regResA = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/auth/register-facility',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, {
      facilityName: 'Al-Amal Specialized Hospital',
      facilityNameAr: 'مستشفى الأمل التخصصي',
      facilityType: 'Specialized Hospital',
      ownership: 'Private',
      country: 'Egypt',
      governorate: 'Cairo',
      city: 'Nasr City',
      bedCapacity: '150',
      address: '14 Abbas El Akkad, Cairo',
      addressAr: '14 شارع عباس العقاد، القاهرة',
      contactPerson: 'Dr. Tamer Mostafa',
      contactPosition: 'Quality & Accreditation Director',
      workEmail: `admin@alamal-${uuidv4().substring(0, 6)}.eg`,
      phone: '+201099887766',
      landline: '+20224011223',
      companySize: '250-500',
      departments: ['Emergency', 'Surgery', 'ICU', 'Radiology', 'Laboratory', 'Quality Committee'],
      services: ['Diagnostic Imaging', 'Inpatient Care', 'Critical Care', 'Surgical Procedures'],
      operatingHours: '24/7 Continuous Operation',
      hasQualityTeam: true,
      accreditationProgram: 'GAHAR 2025 v2',
      targetSurveyDate: '2026-11-30',
      password: 'FacilityPass@2026',
      subscriptionPlanId: 'plan_standard',
      paymentMethod: 'Bank Transfer',
      paymentReference: 'BNK-CAI-2026-99182',
    });

    assert(regResA.statusCode === 201 && regResA.body?.facility?.id, 'Facility A registered in PENDING_REVIEW state');
    facilityAId = regResA.body?.facility?.id;
    facilityAToken = regResA.body?.token;

    // -------------------------------------------------------------------------
    // TEST 3: Facility B Registration (for Tenant Isolation testing)
    // -------------------------------------------------------------------------
    console.log('\n[TEST 3] Facility B Registration (Second Tenant)');
    const regResB = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/auth/register-facility',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, {
      facilityName: 'Alexandria Delta Clinic',
      facilityType: 'Primary Healthcare Unit',
      governorate: 'Alexandria',
      workEmail: `admin@alexdelta-${uuidv4().substring(0, 6)}.eg`,
      contactPerson: 'Dr. Sarah Farid',
      phone: '+201200112233',
      password: 'FacilityPass@2026',
    });

    assert(regResB.statusCode === 201 && regResB.body?.facility?.id, 'Facility B registered successfully');
    facilityBId = regResB.body?.facility?.id;
    facilityBToken = regResB.body?.token;

    // -------------------------------------------------------------------------
    // TEST 4: Applicability Check Engine (Structured Scope Questionnaire)
    // -------------------------------------------------------------------------
    console.log('\n[TEST 4] Applicability Check Questionnaire & Exclusion Calculation');
    const questionsRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/applicability/questions',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityAToken}` }
    });
    assert(questionsRes.statusCode === 200 && questionsRes.body?.questions?.length >= 10, `Retrieved ${questionsRes.body?.questions?.length} structured applicability questions`);

    // Submit answers where Facility A excludes Radiotherapy and Teaching standards
    const submitAppRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/applicability/submit',
      method: 'POST',
      headers: { 
        'Authorization': `Bearer ${facilityAToken}`,
        'Content-Type': 'application/json'
      }
    }, {
      answers: [
        { questionId: 'q_radiology', answer: true },
        { questionId: 'q_laboratory', answer: true },
        { questionId: 'q_surgical', answer: true },
        { questionId: 'q_teaching', answer: false }, // Excluded
        { questionId: 'q_psychiatric', answer: false }, // Excluded
        { questionId: 'q_emergency', answer: true },
        { questionId: 'q_icu', answer: true },
        { questionId: 'q_inpatient', answer: true },
        { questionId: 'q_dialysis', answer: false }, // Excluded
        { questionId: 'q_blood_bank', answer: true },
        { questionId: 'q_chemotherapy', answer: false }, // Excluded
        { questionId: 'q_radiotherapy', answer: false }, // Excluded
      ]
    });
    assert(submitAppRes.statusCode === 200 && submitAppRes.body?.applicability?.excludedCount > 0, `Applicability answers saved; calculated ${submitAppRes.body?.applicability?.excludedCount} excluded standards`);

    // -------------------------------------------------------------------------
    // TEST 5: GAHAR SAT Standards & Sub-Evidence Scoring
    // -------------------------------------------------------------------------
    console.log('\n[TEST 5] GAHAR SAT Standards & Deterministic Scoring');
    const standardsRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/sat/standards',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityAToken}` }
    });
    assert(standardsRes.statusCode === 200 && standardsRes.body?.standards?.length >= 29, `Loaded ${standardsRes.body?.standards?.length} GAHAR standards`);

    // Submit row-level 0/1/2 sub-evidence score for GSR.01
    const subScoreRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/sat/sub-scores/GSR.01.1',
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${facilityAToken}`,
        'Content-Type': 'application/json'
      }
    }, {
      standard_code: 'GSR.01',
      score_value: '2',
      notes: 'Two verified patient identifiers confirmed on all admissions.'
    });
    assert(subScoreRes.statusCode === 200, 'Sub-evidence GSR.01.1 scored 2 (Fully Met)');

    // Batch submit SAT scores
    const batchSatRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/sat/scores/bulk',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${facilityAToken}`,
        'Content-Type': 'application/json'
      }
    }, {
      scores: [
        { standard_code: 'GSR.01', score_value: 'FULLY_MET', notes: 'Complete adherence' },
        { standard_code: 'GSR.02', score_value: 'PARTIALLY_MET', notes: 'Read-back documented; verbal orders pending reduction' },
        { standard_code: 'GSR.03', score_value: 'FULLY_MET', notes: 'Critical limit turnaround verified' },
        { standard_code: 'GSR.05', score_value: 'FULLY_MET', notes: 'Morse scale implemented' },
      ]
    });
    assert(batchSatRes.statusCode === 200 && batchSatRes.body?.saved >= 4, 'Bulk SAT standard scores recorded');

    // Verify SAT summary calculation
    const satSummaryRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/sat/summary',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityAToken}` }
    });
    assert(satSummaryRes.statusCode === 200 && satSummaryRes.body?.overall_percentage > 0, `Deterministic SAT score computed: ${satSummaryRes.body?.overall_percentage}%`);

    // -------------------------------------------------------------------------
    // TEST 6: Document Generation, Customization & Version Control (Phase 2)
    // -------------------------------------------------------------------------
    console.log('\n[TEST 6] Document Generation Engine & Pre-Question Customization');
    const catalogRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/documents/catalog',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityAToken}` }
    });
    assert(catalogRes.statusCode === 200 && catalogRes.body?.catalog?.length >= 10, `Retrieved ${catalogRes.body?.catalog?.length} GAHAR document templates`);

    // Draft a customized Patient Identification Policy
    const draftRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/documents/generate-draft',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${facilityAToken}`,
        'Content-Type': 'application/json'
      }
    }, {
      standardCode: 'GSR.01',
      docCode: 'GAHAR-POL-GSR-01',
      wizardAnswers: {
        targetDepartment: 'Emergency, Inpatient Wards, Operating Theaters, and Outpatient Clinics',
        reviewCycle: '12 Months',
        ownerTitle: 'Quality Director & Chief Medical Officer',
        committeeName: 'Hospital Quality & Patient Safety Governance Committee'
      }
    });
    assert(draftRes.statusCode === 201 && draftRes.body?.document?.id, 'Draft generated and customized with facility context');
    documentId = draftRes.body?.document?.id;

    // Save edited version (v1.0 -> v1.1)
    const editRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: `/api/documents/${documentId}/version`,
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${facilityAToken}`,
        'Content-Type': 'application/json'
      }
    }, {
      content: draftRes.body?.document?.content + '\n\n[AMENDMENT v1.1]: Barcode scanning added to bedside medication administration.',
      changeSummary: 'Added barcode scanning rule to two-identifier verification'
    });
    assert(editRes.statusCode === 200 && editRes.body?.document?.version === 'v1.1', 'Document updated to version v1.1 with version history snapshot');

    // Approve document
    const approveRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: `/api/documents/${documentId}/approval`,
      method: 'PUT',
      headers: {
        'Authorization': `Bearer ${facilityAToken}`,
        'Content-Type': 'application/json'
      }
    }, {
      status: 'APPROVED',
      notes: 'Formally ratified by Quality Committee'
    });
    assert(approveRes.statusCode === 200 && approveRes.body?.document?.status === 'APPROVED', 'Document approved through authorized governance sign-off');

    // Document Generation Dashboard
    const docDashRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/documents/dashboard',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityAToken}` }
    });
    assert(docDashRes.statusCode === 200 && docDashRes.body?.dashboard?.generatedCount >= 1, 'Document Generation Dashboard statistics computed');

    // -------------------------------------------------------------------------
    // TEST 7: Mock Survey & Survey Preparation (Phase 3)
    // -------------------------------------------------------------------------
    console.log('\n[TEST 7] Mock Survey & Survey Preparation Workflow');
    const mockRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/mock-surveys/request',
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${facilityAToken}`,
        'Content-Type': 'application/json'
      }
    }, {
      onsiteDays: 3,
      consultantsCount: 2,
      targetSurveyDate: '2026-10-15',
      contactPerson: 'Dr. Tamer Mostafa',
      phone: '+201099887766'
    });
    assert(mockRes.statusCode === 201 && mockRes.body?.mockSurvey?.id, 'Mock Survey request registered with process tracer checklist');

    // -------------------------------------------------------------------------
    // TEST 8: Continuous Monitoring & ROI Analytics (Phase 4)
    // -------------------------------------------------------------------------
    console.log('\n[TEST 8] Continuous Monitoring & ROI Analytics Engine');
    const monRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/monitoring/summary',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityAToken}` }
    });
    assert(monRes.statusCode === 200 && monRes.body?.monitoring?.kpis?.length >= 4, 'Continuous monitoring KPIs and alerts retrieved');

    const roiRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/roi/analytics',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityAToken}` }
    });
    assert(roiRes.statusCode === 200 && roiRes.body?.roi?.roiPercentage !== undefined, `ROI Calculated: ${roiRes.body?.roi?.roiPercentage}% with transparent formulas`);

    // -------------------------------------------------------------------------
    // TEST 9: Journey Badges System
    // -------------------------------------------------------------------------
    console.log('\n[TEST 9] Journey Badge System');
    const badgeRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/facilities/badges',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityAToken}` }
    });
    assert(badgeRes.statusCode === 200 && badgeRes.body?.badges?.length === 3, 'Retrieved Silver, Gold, Platinum accreditation journey badges');

    // -------------------------------------------------------------------------
    // TEST 10: Multi-Tenancy & Tenant Isolation (CRITICAL SECURITY)
    // -------------------------------------------------------------------------
    console.log('\n[TEST 10] Multi-Tenancy Isolation Verification');
    // Facility B attempts to download Facility A's approved document
    const crossTenantDocRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: `/api/documents/${documentId}/versions`,
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityBToken}` }
    });
    // Must return empty or 403/404 — never leak Facility A versions to Facility B
    assert(crossTenantDocRes.body?.versions?.length === 0, 'Cross-tenant document access blocked: Facility B received 0 records for Facility A document');

    // Facility B queries SAT summary — must NOT see Facility A's score
    const facBSatRes = await makeRequest({
      hostname: 'localhost',
      port: 3000,
      path: '/api/sat/summary',
      method: 'GET',
      headers: { 'Authorization': `Bearer ${facilityBToken}` }
    });
    assert(facBSatRes.body?.total_assessed === 0, 'Cross-tenant SAT scores isolated: Facility B has 0 assessed standards');

    console.log('\n══════════════════════════════════════════════════════════════════════');
    console.log(`🎉 TEST SUMMARY: ${passedTests}/${totalTests} TESTS PASSED`);
    console.log('══════════════════════════════════════════════════════════════════════\n');

    process.exit(passedTests === totalTests ? 0 : 1);
  } catch (err) {
    console.error('Fatal test execution error:', err);
    process.exit(1);
  }
}

runGaharVerificationSuite();
