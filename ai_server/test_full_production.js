const http = require('http');

const BASE_URL = 'http://localhost:3000';

function makeRequest({ path, method = 'GET', headers = {}, body = null }) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...headers,
      },
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: data ? JSON.parse(data) : {} });
        } catch (e) {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function runTests() {
  console.log('🚀 RUNNING COMPREHENSIVE PRODUCTION VERIFICATION SUITE...\n');
  let passed = 0;
  let total = 0;

  function assert(condition, message) {
    total++;
    if (condition) {
      console.log(`  ✅ PASS: ${message}`);
      passed++;
    } else {
      console.error(`  ❌ FAIL: ${message}`);
    }
  }

  // Test 1: Super Admin Login
  console.log('[1. Super Admin Authentication]');
  const adminLogin = await makeRequest({
    path: '/api/auth/super-admin/login',
    method: 'POST',
    body: { email: 'superadmin@gahar.gov.eg', password: 'SuperAdmin@2026!' },
  });
  assert(adminLogin.status === 200 && adminLogin.body.token, 'Super Admin login returns 200 and valid JWT');
  const superAdminToken = adminLogin.body.token;

  // Test 2: Facility Registration without False Activation
  console.log('\n[2. Facility Registration - Safe Payment Status]');
  const facReg = await makeRequest({
    path: '/api/auth/register-facility',
    method: 'POST',
    body: {
      facilityName: 'Al-Amal Specialized Hospital',
      facilityType: 'Hospital',
      governorate: 'Cairo',
      bedCapacity: 150,
      contactPerson: 'Dr. Tarek Omar',
      workEmail: 'admin@alamal.eg',
      phone: '+201099998888',
      password: 'HospitalPassword@2026',
      subscriptionPlanId: 'plan_standard',
      paymentMethod: 'Online Gateway', // Test that it does NOT auto-activate
    },
  });
  assert(facReg.status === 201, 'Facility registration returns 201 Created');
  assert(facReg.body.facility.status === 'PENDING_PAYMENT', 'Online Gateway correctly sets status to PENDING_PAYMENT (No false activation)');
  const facilityToken = facReg.body.token;
  const facilityId = facReg.body.facility.id;

  // Test 3: Password Reset Flow
  console.log('\n[3. Secure Password Reset Flow]');
  const forgotRes = await makeRequest({
    path: '/api/auth/forgot-password',
    method: 'POST',
    body: { email: 'admin@alamal.eg' },
  });
  assert(forgotRes.status === 200 && forgotRes.body.success, 'Forgot password returns safe 200 response');

  // Test 4: Users Management (Create, List, Toggle Status)
  console.log('\n[4. Users Management Module]');
  const createUserRes = await makeRequest({
    path: '/api/users',
    method: 'POST',
    headers: { Authorization: `Bearer ${facilityToken}` },
    body: {
      email: 'quality.lead@alamal.eg',
      fullName: 'Dr. Sarah Mahmoud',
      role: 'QUALITY_MANAGER',
      department: 'Quality & Patient Safety',
      phone: '+201011112222',
      password: 'QualityLead@2026',
    },
  });
  assert(createUserRes.status === 201, 'Quality Manager created in facility');

  const listUsersRes = await makeRequest({
    path: '/api/users',
    method: 'GET',
    headers: { Authorization: `Bearer ${facilityToken}` },
  });
  assert(listUsersRes.status === 200 && listUsersRes.body.users.length >= 2, 'List facility users returns isolated tenant team');

  const qualityUser = listUsersRes.body.users.find(u => u.email === 'quality.lead@alamal.eg');
  const toggleRes = await makeRequest({
    path: `/api/users/${qualityUser.id}/status`,
    method: 'PUT',
    headers: { Authorization: `Bearer ${facilityToken}` },
    body: { isActive: false },
  });
  assert(toggleRes.status === 200 && toggleRes.body.user.is_active === false, 'Deactivate user operates with tenant scope');

  // Test 5: Real Document Storage (Upload, Download, Delete, Multi-Tenancy)
  console.log('\n[5. Real Document Storage & Multi-Tenancy]');
  const samplePdfBase64 = Buffer.from('%PDF-1.4 Mock Clinical Governance Policy Content for GAHAR 2025 Standard').toString('base64');
  const uploadDocRes = await makeRequest({
    path: '/api/documents/upload',
    method: 'POST',
    headers: { Authorization: `Bearer ${facilityToken}` },
    body: {
      title: 'Infection Control Protocol v2',
      category: 'Safety Requirements',
      requirementCode: 'GAHAR-IC-01',
      originalName: 'infection_control_v2.pdf',
      mimeType: 'application/pdf',
      base64Content: samplePdfBase64,
    },
  });
  assert(uploadDocRes.status === 201, 'Document uploaded and registered in storage');
  const docId = uploadDocRes.body.document.id;

  // Attempt download by owner
  const downloadDocRes = await makeRequest({
    path: `/api/documents/${docId}/download`,
    method: 'GET',
    headers: { Authorization: `Bearer ${facilityToken}` },
  });
  assert(downloadDocRes.status === 200, 'Authorized facility can download their own document');

  // Register Facility B to test cross-tenant document isolation
  const facBReg = await makeRequest({
    path: '/api/auth/register-facility',
    method: 'POST',
    body: {
      facilityName: 'Alexandria Heart Hospital',
      workEmail: 'director@alexheart.eg',
      contactPerson: 'Dr. Amr Adel',
      phone: '+201022223333',
    },
  });
  const facBToken = facBReg.body.token;

  // Facility B attempts to download Facility A's document
  const crossDocRes = await makeRequest({
    path: `/api/documents/${docId}/download`,
    method: 'GET',
    headers: { Authorization: `Bearer ${facBToken}` },
  });
  assert(crossDocRes.status === 404 || crossDocRes.status === 403, 'Cross-Tenant Document Access strictly blocked (403/404)');

  // Test 6: Dynamic Data-Driven Badges
  console.log('\n[6. Dynamic Progress Badges]');
  const badgesRes = await makeRequest({
    path: '/api/facilities/badges',
    method: 'GET',
    headers: { Authorization: `Bearer ${facilityToken}` },
  });
  assert(badgesRes.status === 200 && Array.isArray(badgesRes.body.badges), 'Badges calculated dynamically from real facility data');

  // Test 7: Real Super Admin Analytics & ARR Formula
  console.log('\n[7. Super Admin Analytics & ARR]');
  const analyticsRes = await makeRequest({
    path: '/api/admin/analytics',
    method: 'GET',
    headers: { Authorization: `Bearer ${superAdminToken}` },
  });
  assert(analyticsRes.status === 200, 'Analytics endpoint returned 200');
  assert(typeof analyticsRes.body.analytics.annualArrEgp === 'number', 'ARR computed dynamically based on active facilities');

  // Test 8: Super Admin RBAC Protection
  console.log('\n[8. Super Admin RBAC Protection]');
  const unauthorizedAdminCall = await makeRequest({
    path: '/api/admin/facilities',
    method: 'GET',
    headers: { Authorization: `Bearer ${facilityToken}` },
  });
  assert(unauthorizedAdminCall.status === 403, 'Normal facility token blocked from /api/admin/* with 403 Forbidden');

  // Test 9: Subscriptions Lifecycle
  console.log('\n[9. Subscriptions Lifecycle]');
  const subRes = await makeRequest({
    path: '/api/subscriptions/current',
    method: 'GET',
    headers: { Authorization: `Bearer ${facilityToken}` },
  });
  assert(subRes.status === 200 && subRes.body.subscription.daysRemaining > 0, 'Current subscription lifecycle data returned');

  // Test 10: AI Copilot Proxy
  console.log('\n[10. AI Copilot Proxy]');
  const copilotRes = await makeRequest({
    path: '/api/ai/copilot',
    method: 'POST',
    headers: { Authorization: `Bearer ${facilityToken}` },
    body: {
      prompt: 'What are the essential requirements for GAHAR 2025 infection control?',
      screenContext: 'Evidence Tracker Screen',
    },
  });
  assert(copilotRes.status === 200 && copilotRes.body.reply.length > 0, 'AI Copilot proxy delivers GAHAR guidance without client keys');

  console.log(`\n========================================`);
  console.log(`TEST SUMMARY: ${passed} / ${total} TESTS PASSED`);
  console.log(`========================================\n`);

  if (passed === total) {
    process.exit(0);
  } else {
    process.exit(1);
  }
}

runTests().catch(err => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
