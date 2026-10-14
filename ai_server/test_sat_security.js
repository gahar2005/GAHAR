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

async function runSATTenantIsolationTests() {
  console.log('================================================================');
  console.log('🏥 RUNNING GAHAR SAT API & TENANT ISOLATION TESTS');
  console.log('================================================================\n');

  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`  ✅ PASS: ${message}`);
      passed++;
    } else {
      console.error(`  ❌ FAIL: ${message}`);
      failed++;
    }
  }

  try {
    // 1. Super Admin Authentication
    const saLogin = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/auth/super-admin/login', method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, { email: 'superadmin@gahar.gov.eg', password: 'SuperAdmin@2026!' });
    assert(saLogin.statusCode === 200 && saLogin.body?.token, 'Super Admin login successful with JWT');
    const saToken = saLogin.body.token;

    // 2. Register Tenant A (Hospital A)
    const facA = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/auth/register-facility', method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, {
      facilityName: 'Hospital A - Heliopolis',
      workEmail: 'sat_admin_a@hospitalA.eg',
      password: 'PassA@2026!',
      subscriptionPlanId: 'plan_standard'
    });
    assert(facA.statusCode === 201 && facA.body?.token, 'Hospital A registered successfully');
    const tokenA = facA.body.token;
    const facAId = facA.body.facility.id;

    // 3. Register Tenant B (Hospital B)
    const facB = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/auth/register-facility', method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    }, {
      facilityName: 'Hospital B - Alexandria',
      workEmail: 'sat_admin_b@hospitalB.eg',
      password: 'PassB@2026!',
      subscriptionPlanId: 'plan_enterprise'
    });
    assert(facB.statusCode === 201 && facB.body?.token, 'Hospital B registered successfully');
    const tokenB = facB.body.token;
    const facBId = facB.body.facility.id;

    // 4. Test GET /api/sat/standards (All 29 GSR standards from Excel)
    const stdsRes = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/sat/standards', method: 'GET',
      headers: { 'Authorization': `Bearer ${tokenA}` }
    });
    assert(stdsRes.statusCode === 200 && stdsRes.body.standards?.length >= 29, `Retrieved ${stdsRes.body.standards?.length} standards (>= 29 GSR items)`);

    // 5. Tenant A saves a single score on GSR.01
    const putRes = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/sat/scores/GSR.01', method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${tokenA}`
      }
    }, {
      score_status: 'FULLY_MET',
      numeric_score: 100,
      notes: 'Facility license valid until 2028'
    });
    assert(putRes.statusCode === 200 && putRes.body.success === true, 'Tenant A saved score on GSR.01 (FULLY_MET)');

    // 6. Tenant A bulk saves GSR.02 and GSR.03
    const bulkRes = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/sat/scores/bulk', method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${tokenA}`
      }
    }, {
      scores: [
        { standard_code: 'GSR.02', score_status: 'PARTIALLY_MET', numeric_score: 50, notes: 'Emergency lighting under repair' },
        { standard_code: 'GSR.03', score_status: 'NOT_APPLICABLE', numeric_score: null, notes: 'Off-site clinic exempt' }
      ]
    });
    assert(bulkRes.statusCode === 200 && bulkRes.body.count === 2, 'Tenant A saved bulk scores on GSR.02 and GSR.03');

    // 7. Tenant A retrieves its scores
    const getResA = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/sat/scores', method: 'GET',
      headers: { 'Authorization': `Bearer ${tokenA}` }
    });
    assert(getResA.statusCode === 200 && getResA.body.scores?.length === 3, 'Tenant A sees its 3 recorded scores');

    // 8. CRITICAL TENANT ISOLATION: Tenant B queries /api/sat/scores
    const getResB = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/sat/scores', method: 'GET',
      headers: { 'Authorization': `Bearer ${tokenB}` }
    });
    assert(getResB.statusCode === 200 && getResB.body.scores?.length === 0, 'Tenant B CANNOT see Tenant A scores (Scores length = 0)');

    // 9. CRITICAL SPOOFING TEST: Tenant B sends X-Facility-Id = facAId
    const spoofRes = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/sat/scores', method: 'GET',
      headers: {
        'Authorization': `Bearer ${tokenB}`,
        'X-Facility-Id': facAId // Spoof attempt!
      }
    });
    // Server must reject (403) OR return 0 scores — X-Facility-Id header MUST NOT grant cross-tenant access
    const spoofThwarted = spoofRes.statusCode === 403 || (spoofRes.body.scores?.length === 0);
    assert(spoofThwarted, 'X-Facility-Id spoofing attempt thwarted: Tenant identity derived strictly from JWT');

    // 10. Tenant A retrieves SAT Summary and Report
    const summaryRes = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/sat/summary', method: 'GET',
      headers: { 'Authorization': `Bearer ${tokenA}` }
    });
    assert(summaryRes.statusCode === 200 && summaryRes.body.summary?.length > 0, 'Tenant A retrieved SAT Chapter Summary');

    const reportRes = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/sat/report', method: 'GET',
      headers: { 'Authorization': `Bearer ${tokenA}` }
    });
    assert(reportRes.statusCode === 200 && reportRes.body.report?.overall_score !== undefined, `Tenant A retrieved SAT Report (Overall Score: ${reportRes.body.report?.overall_score}%)`);

    // 11. Super Admin accesses Platform-wide SAT Summary
    const adminRes = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/admin/sat/platform-summary', method: 'GET',
      headers: { 'Authorization': `Bearer ${saToken}` }
    });
    assert(adminRes.statusCode === 200 && adminRes.body.success === true, 'Super Admin accessed platform SAT aggregate summary');

    // 12. Normal user tries to access /api/admin/sat/platform-summary -> 403 Forbidden
    const unauthAdminRes = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/admin/sat/platform-summary', method: 'GET',
      headers: { 'Authorization': `Bearer ${tokenA}` }
    });
    assert(unauthAdminRes.statusCode === 403, 'Normal facility user blocked from Super Admin SAT summary (HTTP 403 Forbidden)');

    // 13. Unauthenticated request -> 401 Unauthorized
    const unauthRes = await makeRequest({
      hostname: 'localhost', port: 3000, path: '/api/sat/scores', method: 'GET'
    });
    assert(unauthRes.statusCode === 401, 'Unauthenticated request rejected with HTTP 401 Unauthorized');

    console.log('\n================================================================');
    console.log(`🏁 SAT TEST RESULTS: ${passed} PASSED, ${failed} FAILED`);
    console.log('================================================================\n');

    process.exit(failed > 0 ? 1 : 0);
  } catch (err) {
    console.error('Test execution error:', err);
    process.exit(1);
  }
}

runSATTenantIsolationTests();
