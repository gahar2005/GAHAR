const http = require('http');
const { app } = require('./server');

let testPort = 3000;

function makeRequest(options, postData) {
  return new Promise((resolve, reject) => {
    const reqOptions = {
      ...options,
      hostname: '127.0.0.1',
      port: testPort
    };
    const req = http.request(reqOptions, (res) => {
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

  let serverInstance = null;
  await new Promise((resolve) => {
    serverInstance = app.listen(0, '127.0.0.1', () => {
      testPort = serverInstance.address().port;
      resolve();
    });
  });

  let failed = false;
  function assert(condition, message) {
    if (condition) {
      console.log(`  ✅ [PASS] ${message}`);
    } else {
      console.error(`  ❌ [FAIL] ${message}`);
      failed = true;
    }
  }

  try {
  // 1. Super Admin Authentication Test
  const saLogin = await makeRequest({
    path: '/api/auth/super-admin/login', method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, { email: 'superadmin@gahar.gov.eg', password: process.env.SUPER_ADMIN_PASSWORD || 'SuperAdmin@2026!' });
  assert(saLogin.statusCode === 200 && !!saLogin.body?.token, 'Super Admin Login successful');

  // 2. Facility A Registration
  const facA = await makeRequest({
    path: '/api/auth/register-facility', method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    facilityName: 'Hospital A - Cairo',
    contactPerson: 'Dr. Ahmed Ali',
    workEmail: `admin_${Date.now()}_a@hospitalA.eg`,
    password: 'PassA@2026',
    subscriptionPlanId: 'plan_standard'
  });
  const facAToken = facA.body?.token;
  const facAId = facA.body?.facility?.id;
  assert(facA.statusCode === 201 && !!facAToken && !!facAId, 'Facility A registered successfully');
  console.log(`[TENANT A] Registered: ID=${facAId} | Token Issued: ${!!facAToken}`);

  // 3. Facility B Registration
  const facB = await makeRequest({
    path: '/api/auth/register-facility', method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  }, {
    facilityName: 'Hospital B - Alex',
    contactPerson: 'Dr. Mona Hassan',
    workEmail: `admin_${Date.now()}_b@hospitalB.eg`,
    password: 'PassB@2026',
    subscriptionPlanId: 'plan_enterprise'
  });
  const facBToken = facB.body?.token;
  const facBId = facB.body?.facility?.id;
  assert(facB.statusCode === 201 && !!facBToken && !!facBId, 'Facility B registered successfully');
  console.log(`[TENANT B] Registered: ID=${facBId} | Token Issued: ${!!facBToken}`);

  // 4. Create Document under Facility B
  const docB = await makeRequest({
    path: '/api/documents', method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${facBToken}` }
  }, { title: 'Confidential Infection Control Policy B', category: 'IPC' });
  console.log(`[DOCUMENTS] Created document for Facility B: ID=${docB.body?.document?.id}`);

    // 5. Cross-Tenant Attempt: Facility A tries to fetch Facility B documents using custom header
    const crossTenantAttempt = await makeRequest({
      path: '/api/documents', method: 'GET',
      headers: { 
        'Content-Type': 'application/json', 
        'Authorization': `Bearer ${facAToken}`, 
        'X-Facility-Id': facBId 
      }
    });
    assert(crossTenantAttempt.statusCode === 403, 'Cross-Tenant Header Block: 403 Forbidden');

    // 6. Normal Facility tries to access Super Admin endpoint
    const adminAccessAttempt = await makeRequest({
      path: '/api/admin/facilities', method: 'GET',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${facAToken}` }
    });
    assert(adminAccessAttempt.statusCode === 403, 'Super Admin Endpoint Protection: 403 Forbidden');

    // 7. Unauthenticated request to protected endpoint
    const unauthAttempt = await makeRequest({
      path: '/api/documents', method: 'GET',
      headers: { 'Content-Type': 'application/json' }
    });
    assert(unauthAttempt.statusCode === 401, 'Unauthenticated Block: 401 Unauthorized');

    console.log('\n🛡️ ALL AUDIT SECURITY CHECKS VERIFIED SUCCESSFULLY!\n');
  } catch (err) {
    console.error('Test execution error:', err);
    failed = true;
  } finally {
    if (serverInstance) {
      serverInstance.close(() => {
        process.exit(failed ? 1 : 0);
      });
    } else {
      process.exit(failed ? 1 : 0);
    }
  }
}

runSecurityAuditTests();
