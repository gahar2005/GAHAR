const http = require('http');
const assert = require('assert');

function makeRequest({ path, method = 'GET', headers = {}, body = null }) {
  return new Promise((resolve, reject) => {
    const payload = body ? JSON.stringify(body) : null;
    const reqHeaders = { ...headers };
    if (payload) {
      reqHeaders['Content-Type'] = 'application/json';
      reqHeaders['Content-Length'] = Buffer.byteLength(payload);
    }
    const req = http.request({
      hostname: 'localhost',
      port: 3000,
      path,
      method,
      headers: reqHeaders,
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        let json = null;
        try { json = JSON.parse(data); } catch (_) {}
        resolve({ status: res.statusCode, headers: res.headers, raw: data, body: json });
      });
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function run() {
  console.log('🧪 Starting Master Regression Suite for GAHAR Platform...');

  // 1. Authenticate facility user via registration or login
  const regEmail = `regression_${Date.now()}@alamal.eg`;
  const regRes = await makeRequest({
    path: '/api/auth/register-facility',
    method: 'POST',
    body: {
      facilityName: 'Al Noor Specialized Hospital',
      facilityType: 'Hospital',
      governorate: 'Cairo',
      bedCapacity: 120,
      contactPerson: 'Dr. Ahmed Quality',
      workEmail: regEmail,
      phone: '+201099887766',
      password: 'HospitalPassword@2026',
      subscriptionPlanId: 'plan_standard',
      paymentMethod: 'Bank Transfer',
    },
  });
  assert(regRes.status === 201 && regRes.body.token, 'Facility registration failed');
  const token = regRes.body.token;
  const facilityId = regRes.body.facility.id;
  const authHeaders = { Authorization: `Bearer ${token}` };
  console.log('✅ 1. Authentication successful');

  // TEST A: Applicability Engine
  console.log('\n--- TEST A: Applicability Engine Contract ---');
  const appStatusRes = await makeRequest({
    path: '/api/applicability/status',
    headers: authHeaders,
  });
  assert(appStatusRes.status === 200, 'Applicability status failed');
  assert(appStatusRes.body.success === true, 'Applicability status success is true');
  assert(Array.isArray(appStatusRes.body.applicability.answers), 'Applicability answers is an Array');
  assert(typeof appStatusRes.body.applicability.answersMap === 'object', 'Applicability answersMap is an Object/Map');
  assert(Array.isArray(appStatusRes.body.applicability.excludedStandards), 'excludedStandards is an Array');
  console.log(`✅ TEST A PASSED: Applicability returns typed data (answers count: ${appStatusRes.body.applicability.answers.length}, excluded: ${appStatusRes.body.applicability.excludedCount})`);

  // Applicability Submit with Map (as Flutter ApiService sends it)
  const appSubmitRes = await makeRequest({
    path: '/api/applicability/submit',
    method: 'POST',
    headers: authHeaders,
    body: {
      answers: {
        q_radiology: true,
        q_laboratory: true,
        q_surgical: true,
        q_teaching: false,
        q_psychiatric: false,
        q_emergency: true,
        q_icu: true,
        q_inpatient: true,
        q_dialysis: false,
        q_blood_bank: true,
        q_chemotherapy: false,
        q_radiotherapy: false,
      }
    }
  });
  assert(appSubmitRes.status === 200, 'Applicability submission failed');
  assert(appSubmitRes.body.success === true, 'Applicability submission success is true');
  console.log('✅ TEST A.2 PASSED: Applicability submission accepting Map format verified');

  // TEST E: Document Generation API returns JSON (not HTML <!DOCTYPE)
  console.log('\n--- TEST E: Document Generation API (GSR-06) ---');
  const docGenRes = await makeRequest({
    path: '/api/documents/draft',
    method: 'POST',
    headers: authHeaders,
    body: {
      docCode: 'GAHAR-POL-GSR-06',
      customization: {
        facilityName: 'Al Noor Specialized Hospital',
        docCode: 'GAHAR-POL-GSR-06',
        department: 'Quality & Accreditation',
        documentOwner: 'Quality Manager',
        effectiveDate: '2026-10-04',
        reviewCycle: '12 Months',
      }
    }
  });
  assert(docGenRes.status === 201, `Document draft returned ${docGenRes.status}: ${docGenRes.raw}`);
  assert(docGenRes.body.success === true, 'Document generation success is true');
  assert(docGenRes.body.document != null, 'Document object returned');
  assert(docGenRes.body.draft != null, 'Draft object returned for Flutter client');
  assert(docGenRes.body.draft.content.includes('AL NOOR SPECIALIZED HOSPITAL'), 'Document draft contains entered facility name');
  assert(docGenRes.body.draft.content.includes('GSR.06'), 'Document draft grounded in standard GSR.06');
  console.log('✅ TEST E PASSED: Document generation returned valid JSON (HTTP 201) grounded in GSR-06 with customized facility name');

  // Also test /api/documents/generate-draft endpoint
  const docGenAliasRes = await makeRequest({
    path: '/api/documents/generate-draft',
    method: 'POST',
    headers: authHeaders,
    body: {
      standardCode: 'GSR.01',
      wizardAnswers: {
        facilityName: 'Al Noor Specialized Hospital',
        department: 'Governance',
      }
    }
  });
  assert(docGenAliasRes.status === 201 && docGenAliasRes.body.success, 'Document generate-draft alias failed');
  console.log('✅ TEST E.2 PASSED: Alias route /api/documents/generate-draft verified');

  // TEST C: AI Copilot Grounding for GSR.01
  console.log('\n--- TEST C: AI Copilot Grounding (GSR.01) ---');
  const copilotRes = await makeRequest({
    path: '/api/ai/copilot',
    method: 'POST',
    headers: authHeaders,
    body: {
      prompt: 'Explain GSR.01 according to the GAHAR 2025 standards. List the specific requirements and evidence required for GSR.01. Do not include unrelated standards.',
      screenContext: 'Standards Reference',
    }
  });
  assert(copilotRes.status === 200, 'AI Copilot request failed');
  assert(copilotRes.body.success === true, 'AI Copilot response success is true');
  assert(copilotRes.body.reply.length > 50, 'AI Copilot reply is non-empty');
  assert(copilotRes.body.reply.toUpperCase().includes('GSR.01') || copilotRes.body.reply.includes('patient identification') || copilotRes.body.reply.includes('Patient identification') || copilotRes.body.reply.includes('تعريف هوية المريض'), 'AI Copilot reply grounded in GSR.01 patient identification');
  console.log('✅ TEST C PASSED: AI Copilot grounded strictly in GSR.01');

  // Non-existent standard test
  const nonExistentRes = await makeRequest({
    path: '/api/ai/copilot',
    method: 'POST',
    headers: authHeaders,
    body: {
      prompt: 'Explain standard XYZ.99 according to GAHAR standards.',
      screenContext: 'Standards Reference',
    }
  });
  assert(nonExistentRes.body.reply.includes('not found'), 'AI Copilot does not hallucinate non-existent standard');
  console.log('✅ TEST C.2 PASSED: AI Copilot correctly rejects non-existent standard without hallucination');

  // Verify Catch-all 404 returns JSON, never HTML
  console.log('\n--- Catch-all JSON 404 Test ---');
  const notFoundRes = await makeRequest({
    path: '/api/non-existent-route-endpoint',
    headers: authHeaders,
  });
  assert(notFoundRes.status === 404, 'Catch-all 404 status mismatch');
  assert(notFoundRes.body != null && notFoundRes.body.success === false, 'Catch-all 404 returns proper JSON');
  assert(!notFoundRes.raw.includes('<!DOCTYPE'), 'Catch-all 404 never returns HTML');
  console.log('✅ Catch-all 404 PASSED: API returned strict JSON instead of HTML error page');

  // Super Admin tenant isolation test
  console.log('\n--- Super Admin & Tenant Isolation ---');
  const fakeTenantRes = await makeRequest({
    path: '/api/documents/catalog',
    headers: { ...authHeaders, 'x-facility-id': 'fac-tampered-id-123' },
  });
  assert(fakeTenantRes.status === 403, 'Cross-tenant manipulation should return 403');
  console.log('✅ Tenant Isolation PASSED: Blocked mismatched facility ID with 403 Forbidden');

  console.log('\n========================================');
  console.log('🎉 ALL MASTER REGRESSION TESTS PASSED!');
  console.log('========================================\n');
}

run().catch(err => {
  console.error('❌ REGRESSION TEST FAILED:', err);
  process.exit(1);
});
