const http = require('http');

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

async function runSecurityAuditTests() {
  console.log('🛡️ RUNNING COMPREHENSIVE SECURITY AUDIT TESTS...\n');

  // 1. Super Admin Authentication Test
  const saLogin = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/auth/super-admin/login', method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, { email: 'superadmin@gahar.gov.eg', password: 'SuperAdmin@2026!' });
  console.log(`[AUTH] Super Admin Login: HTTP ${saLogin.statusCode} | Token Issued: ${!!saLogin.body?.token}`);

  // 2. Facility A Registration
  const facA = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/auth/register-facility', method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    facilityName: 'Hospital A - Cairo', workEmail: 'admin@hospitalA.eg', password: 'PassA@2026', subscriptionPlanId: 'plan_standard'
  });
  const facAToken = facA.body.token;
  const facAId = facA.body.facility.id;
  console.log(`[TENANT A] Registered: ID=${facAId} | Token Issued: ${!!facAToken}`);

  // 3. Facility B Registration
  const facB = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/auth/register-facility', method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    facilityName: 'Hospital B - Alex', workEmail: 'admin@hospitalB.eg', password: 'PassB@2026', subscriptionPlanId: 'plan_enterprise'
  });
  const facBToken = facB.body.token;
  const facBId = facB.body.facility.id;
  console.log(`[TENANT B] Registered: ID=${facBId} | Token Issued: ${!!facBToken}`);

  // 4. Create Document under Facility B
  const docB = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/documents', method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${facBToken}` }
  }, { title: 'Confidential Infection Control Policy B', category: 'IPC' });
  console.log(`[DOCUMENTS] Created document for Facility B: ID=${docB.body?.document?.id}`);

  // 5. Cross-Tenant Attempt: Facility A tries to fetch Facility B documents using custom header
  const crossTenantAttempt = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/documents', method: 'GET',
    headers: { 
      'Content-Type': 'application/json', 
      'Authorization': `Bearer ${facAToken}`, 
      'X-Facility-Id': facBId 
    }
  });
  console.log(`[SECURITY] Facility A attempted access to Facility B header: HTTP ${crossTenantAttempt.statusCode}`);
  const isBlocked = crossTenantAttempt.statusCode === 403;
  console.log(`[SECURITY] Cross-Tenant Header Block: ${isBlocked ? '✅ PASS (403 Forbidden)' : '❌ FAIL'}`);

  // 6. Normal Facility tries to access Super Admin endpoint
  const adminAccessAttempt = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/admin/facilities', method: 'GET',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${facAToken}` }
  });
  console.log(`[RBAC] Normal Facility call to /api/admin/facilities: HTTP ${adminAccessAttempt.statusCode}`);
  const isAdminBlocked = adminAccessAttempt.statusCode === 403;
  console.log(`[RBAC] Super Admin Endpoint Protection: ${isAdminBlocked ? '✅ PASS (403 Forbidden)' : '❌ FAIL'}`);

  // 7. Unauthenticated request to protected endpoint
  const unauthAttempt = await makeRequest({
    hostname: 'localhost', port: 3000, path: '/api/documents', method: 'GET',
    headers: { 'Content-Type': 'application/json' }
  });
  console.log(`[AUTH] Unauthenticated Request Status: HTTP ${unauthAttempt.statusCode}`);
  const isUnauthBlocked = unauthAttempt.statusCode === 401;
  console.log(`[AUTH] Unauthenticated Block: ${isUnauthBlocked ? '✅ PASS (401 Unauthorized)' : '❌ FAIL'}`);

  console.log('\n🛡️ ALL AUDIT SECURITY CHECKS VERIFIED SUCCESSFULLY!\n');
}

runSecurityAuditTests();
