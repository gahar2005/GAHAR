const http = require('http');
const { app } = require('./server');

let server;
let baseUrl;

function makeRequest({ path, method = 'GET', headers = {} }, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const options = {
      hostname: url.hostname,
      port: url.port,
      path: url.pathname + url.search,
      method,
      headers: {
        'Content-Type': 'application/json',
        ...headers
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          resolve({ statusCode: res.statusCode, headers: res.headers, body: parsed });
        } catch (_) {
          resolve({ statusCode: res.statusCode, headers: res.headers, raw: data });
        }
      });
    });

    req.on('error', reject);
    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

async function runPersistenceSuite() {
  console.log('=============================================================================');
  console.log('🧪 RUNNING GAPS, ACTION PLANS, LICENSES & MONITORING/ROI PERSISTENCE SUITE');
  console.log('=============================================================================\n');

  let passed = 0;
  let failed = 0;

  function assert(condition, message) {
    if (condition) {
      console.log(`  ✅ [PASS] ${message}`);
      passed++;
    } else {
      console.error(`  ❌ [FAIL] ${message}`);
      failed++;
    }
  }

  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const port = server.address().port;
  baseUrl = `http://127.0.0.1:${port}`;
  console.log(`📡 In-process test server running on ${baseUrl}\n`);

  try {
    // -------------------------------------------------------------------------
    // 1. Setup Two Isolated Tenants
    // -------------------------------------------------------------------------
    console.log('--- 1. Setup Tenant Accounts ---');
    const emailA = `tenant_a_${Date.now()}@cairo-health.eg`;
    const regA = await makeRequest({ path: '/api/auth/register-facility', method: 'POST' }, {
      facilityName: 'Cairo Heart Institute',
      contactPerson: 'Dr. Mahmoud',
      workEmail: emailA,
      password: 'Password123!',
      subscriptionPlanId: 'plan_standard'
    });
    const tokenA = regA.body?.token;
    const facAId = regA.body?.facility?.id;
    assert(regA.statusCode === 201 && !!tokenA, 'Tenant A successfully registered');

    const emailB = `tenant_b_${Date.now()}@alex-med.eg`;
    const regB = await makeRequest({ path: '/api/auth/register-facility', method: 'POST' }, {
      facilityName: 'Alexandria Oncology Center',
      contactPerson: 'Dr. Nadia',
      workEmail: emailB,
      password: 'Password123!',
      subscriptionPlanId: 'plan_standard'
    });
    const tokenB = regB.body?.token;
    const facBId = regB.body?.facility?.id;
    assert(regB.statusCode === 201 && !!tokenB, 'Tenant B successfully registered');

    // -------------------------------------------------------------------------
    // 2. Gaps CRUD & Multi-Tenant Isolation
    // -------------------------------------------------------------------------
    console.log('\n--- 2. Gaps CRUD & Tenant Isolation ---');
    const createGapRes = await makeRequest({
      path: '/api/gaps',
      method: 'POST',
      headers: { Authorization: `Bearer ${tokenA}` }
    }, {
      gapTitle: 'Emergency Exit Corridor Partially Obstructed',
      standardCode: 'FMS.04',
      severity: 'high',
      description: 'Storage boxes found near OR exit door.'
    });
    const gap = createGapRes.body?.gap;
    assert(createGapRes.statusCode === 201 && gap?.gapTitle === 'Emergency Exit Corridor Partially Obstructed', 'Tenant A created gap item');
    assert(gap?.facilityId === facAId, 'Gap automatically stamped with Tenant A facilityId');

    const listGapsA = await makeRequest({
      path: '/api/gaps',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    assert(listGapsA.statusCode === 200 && listGapsA.body?.gaps?.length >= 1, 'Tenant A lists its own active gaps');

    const listGapsB = await makeRequest({
      path: '/api/gaps',
      headers: { Authorization: `Bearer ${tokenB}` }
    });
    const leakGap = listGapsB.body?.gaps?.find(g => g.id === gap.id);
    assert(listGapsB.statusCode === 200 && !leakGap, 'Tenant B cannot see Tenant A gap (Tenant isolation verified)');

    // -------------------------------------------------------------------------
    // 3. Action Plans CRUD & Multi-Tenant Isolation
    // -------------------------------------------------------------------------
    console.log('\n--- 3. Action Plans CRUD & Tenant Isolation ---');
    const createPlanRes = await makeRequest({
      path: '/api/action-plans',
      method: 'POST',
      headers: { Authorization: `Bearer ${tokenA}` }
    }, {
      title: 'Clear OR Emergency Exit Corridors',
      gapId: gap.id,
      department: 'Safety & Security',
      priority: 'high',
      dueDate: new Date(Date.now() + 7 * 86400000).toISOString().split('T')[0]
    });
    const plan = createPlanRes.body?.actionPlan;
    assert(createPlanRes.statusCode === 201 && plan?.title === 'Clear OR Emergency Exit Corridors', 'Tenant A created action plan');
    assert(plan?.facilityId === facAId, 'Action plan stamped with Tenant A facilityId');

    const listPlansA = await makeRequest({
      path: '/api/action-plans',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    assert(listPlansA.statusCode === 200 && listPlansA.body?.actionPlans?.length >= 1, 'Tenant A lists its action plans');

    const listPlansB = await makeRequest({
      path: '/api/action-plans',
      headers: { Authorization: `Bearer ${tokenB}` }
    });
    const leakPlan = listPlansB.body?.actionPlans?.find(p => p.id === plan.id);
    assert(listPlansB.statusCode === 200 && !leakPlan, 'Tenant B cannot see Tenant A action plans');

    // -------------------------------------------------------------------------
    // 4. Licenses CRUD & Multi-Tenant Isolation
    // -------------------------------------------------------------------------
    console.log('\n--- 4. Licenses CRUD & Tenant Isolation ---');
    const createLicRes = await makeRequest({
      path: '/api/licenses',
      method: 'POST',
      headers: { Authorization: `Bearer ${tokenA}` }
    }, {
      licenseName: 'Ministry of Health Hospital Operating License',
      licenseNumber: 'MOH-EGY-2026-9988',
      issuingAuthority: 'Egyptian Ministry of Health',
      expirationDate: new Date(Date.now() + 180 * 86400000).toISOString().split('T')[0]
    });
    const license = createLicRes.body?.license;
    assert(createLicRes.statusCode === 201 && license?.licenseName === 'Ministry of Health Hospital Operating License', 'Tenant A created statutory license');

    const listLicA = await makeRequest({
      path: '/api/licenses',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    assert(listLicA.statusCode === 200 && listLicA.body?.licenses?.length >= 1, 'Tenant A lists its licenses');

    const listLicB = await makeRequest({
      path: '/api/licenses',
      headers: { Authorization: `Bearer ${tokenB}` }
    });
    const leakLic = listLicB.body?.licenses?.find(l => l.id === license.id);
    assert(listLicB.statusCode === 200 && !leakLic, 'Tenant B cannot see Tenant A licenses');

    // -------------------------------------------------------------------------
    // 5. Soft-Delete & Trash Integration
    // -------------------------------------------------------------------------
    console.log('\n--- 5. Soft-Delete & Trash Verification ---');
    const delGap = await makeRequest({
      path: `/api/gaps/${gap.id}`,
      method: 'DELETE',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    assert(delGap.statusCode === 200, 'Tenant A soft-deleted gap item');

    const listGapsAfterDel = await makeRequest({
      path: '/api/gaps',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    const foundDeletedGap = listGapsAfterDel.body?.gaps?.find(g => g.id === gap.id);
    assert(!foundDeletedGap, 'Soft-deleted gap no longer returned in active list');

    const trashA = await makeRequest({
      path: '/api/trash',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    const trashEntry = trashA.body?.trash?.find(t => t.item_id === gap.id || t.itemId === gap.id);
    assert(trashA.statusCode === 200 && !!trashEntry, 'Trashed gap appears in facility trash bin');

    const restoreRes = await makeRequest({
      path: `/api/trash/${trashEntry.id}/restore`,
      method: 'POST',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    assert(restoreRes.statusCode === 200, 'Restored gap item from trash');

    const listGapsRestored = await makeRequest({
      path: '/api/gaps',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    const gapIsBack = listGapsRestored.body?.gaps?.find(g => g.id === gap.id);
    assert(!!gapIsBack, 'Restored gap reappears in active list');

    // -------------------------------------------------------------------------
    // 6. Monitoring & ROI Analytics
    // -------------------------------------------------------------------------
    console.log('\n--- 6. Monitoring Summary & ROI Analytics ---');
    const monRes = await makeRequest({
      path: '/api/monitoring/summary',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    assert(monRes.statusCode === 200 && Array.isArray(monRes.body?.monitoring?.kpis), 'GET /api/monitoring/summary returns structured KPIs');
    assert(monRes.body?.monitoring?.facilityId === facAId, 'Monitoring summary is scoped strictly to Tenant A');

    const roiRes = await makeRequest({
      path: '/api/roi/analytics',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    assert(roiRes.statusCode === 200 && roiRes.body?.roi?.currency === 'EGP', 'GET /api/roi/analytics returns EGP-denominated financial analysis');
    assert(roiRes.body?.roi?.totalAnnualSavings > 0, 'ROI analytics computes valid healthcare savings');

    // -------------------------------------------------------------------------
    // 7. Mock Survey Request Engine
    // -------------------------------------------------------------------------
    console.log('\n--- 7. Mock Survey Engine ---');
    const mockReqRes = await makeRequest({
      path: '/api/mock-surveys/request',
      method: 'POST',
      headers: { Authorization: `Bearer ${tokenA}` }
    }, {
      activeServices: ['Inpatient', 'Surgery', 'ICU'],
      onsiteDays: 3,
      consultantsCount: 2,
      contactPerson: 'Dr. Mahmoud'
    });
    assert(mockReqRes.statusCode === 201 && mockReqRes.body?.mockSurvey?.status === 'REQUESTED', 'Mock survey request created');
    assert(mockReqRes.body?.mockSurvey?.proposal_price === (3 * 2 * 15000), 'Proposal price formula accurately computed');

    const listSurveysA = await makeRequest({
      path: '/api/mock-surveys',
      headers: { Authorization: `Bearer ${tokenA}` }
    });
    assert(listSurveysA.statusCode === 200 && listSurveysA.body?.mockSurveys?.length >= 1, 'Tenant A lists its mock surveys');

    const listSurveysB = await makeRequest({
      path: '/api/mock-surveys',
      headers: { Authorization: `Bearer ${tokenB}` }
    });
    const leakSurvey = listSurveysB.body?.mockSurveys?.find(s => s.id === mockReqRes.body?.mockSurvey?.id);
    assert(listSurveysB.statusCode === 200 && !leakSurvey, 'Tenant B cannot see Tenant A mock survey');

    console.log('\n=============================================================================');
    console.log(`📊 PERSISTENCE SUITE RESULTS: ${passed} PASSED, ${failed} FAILED`);
    console.log('=============================================================================\n');

    process.exit(failed > 0 ? 1 : 0);
  } catch (err) {
    console.error('Fatal suite error:', err);
    process.exit(1);
  } finally {
    if (server) server.close();
  }
}

runPersistenceSuite();
