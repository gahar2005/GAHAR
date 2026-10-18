const http = require('http');
const { app } = require('./server');
const { isDbConnected, initializeDatabase } = require('./db');

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

async function runRegression() {
  console.log('🧪 ========================================================');
  console.log('🧪 RUNNING NON-DESTRUCTIVE BACKEND REGRESSION SUITE');
  console.log('🧪 ========================================================\n');

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

  // Await database initialization handshake
  console.log('⏳ Connecting to Supabase PostgreSQL pooler...');
  await initializeDatabase();
  console.log('🔌 Database handshake complete.');

  server = app.listen(0, '127.0.0.1');
  await new Promise(r => server.once('listening', r));
  const port = server.address().port;
  baseUrl = `http://127.0.0.1:${port}`;
  console.log(`📡 In-process test server running on ${baseUrl}\n`);

  try {
    // 1. Dynamic Database State & Health Check
    console.log('--- 1. Database Connection & Health Verification ---');
    assert(isDbConnected() === true, 'Database is confirmed dynamically connected via isDbConnected()');
    
    const healthRes = await makeRequest({ path: '/health' });
    assert(healthRes.statusCode === 200, 'GET /health returns HTTP 200');
    assert(healthRes.body?.database === 'connected', 'GET /health reports database is connected');

    // 2. Super Admin Login
    console.log('\n--- 2. Super Admin Authorization & Persistent Read Endpoints ---');
    const adminLoginRes = await makeRequest({
      path: '/api/auth/super-admin/login',
      method: 'POST'
    }, {
      email: 'admin@accredigo.eg',
      password: process.env.SUPER_ADMIN_PASSWORD || 'SuperAdmin@2026!'
    });
    const adminToken = adminLoginRes.body?.token;
    assert(adminLoginRes.statusCode === 200 && adminToken, 'Super Admin authenticated successfully');

    // 3. Super Admin Plans (Reading from PostgreSQL)
    const plansRes = await makeRequest({
      path: '/api/admin/plans',
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    assert(plansRes.statusCode === 200, 'GET /api/admin/plans returns HTTP 200');
    assert(Array.isArray(plansRes.body?.plans) && plansRes.body.plans.length >= 3, 'Subscription plans retrieved from persistent database (3+ plans)');

    // 4. Super Admin Facilities (Reading from PostgreSQL)
    const facRes = await makeRequest({
      path: '/api/admin/facilities',
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    assert(facRes.statusCode === 200, 'GET /api/admin/facilities returns HTTP 200');
    assert(Array.isArray(facRes.body?.facilities), 'Facilities array returned from database query');

    // 5. Super Admin Analytics (Computed from PostgreSQL)
    const analyticsRes = await makeRequest({
      path: '/api/admin/analytics',
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    assert(analyticsRes.statusCode === 200, 'GET /api/admin/analytics returns HTTP 200');
    assert(analyticsRes.body?.analytics?.arrFormula, 'Analytics computed with valid formula');

    // 6. Super Admin Audit Logs (Reading from PostgreSQL)
    const auditRes = await makeRequest({
      path: '/api/admin/audit-logs',
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    assert(auditRes.statusCode === 200, 'GET /api/admin/audit-logs returns HTTP 200');
    assert(Array.isArray(auditRes.body?.auditLogs), 'Audit logs retrieved from PostgreSQL audit_logs table');

    // 7. SAT Standards (281 standards from PostgreSQL)
    console.log('\n--- 3. SAT Standards & Evidence Mapping ---');
    const stdRes = await makeRequest({
      path: '/api/sat/standards',
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    assert(stdRes.statusCode === 200, 'GET /api/sat/standards returns HTTP 200');
    assert(stdRes.body?.total === 281, `GET /api/sat/standards returned all 281 standards from PostgreSQL (got ${stdRes.body?.total})`);

    // 8. Direct Standard Code Sub-Evidence: ACT.03
    const actSubRes = await makeRequest({
      path: '/api/sat/sub-evidence/ACT.03',
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    assert(actSubRes.statusCode === 200, 'GET /api/sat/sub-evidence/ACT.03 returns HTTP 200');
    const actItems = actSubRes.body?.evidence_items || [];
    assert(actItems.length === 5, `Direct ACT.03 standard returns 5 sub-evidence items (got ${actItems.length})`);

    // 9. Mapped GSR Code Sub-Evidence: GSR.01 -> ACT.03
    const gsrSubRes = await makeRequest({
      path: '/api/sat/sub-evidence/GSR.01',
      headers: { Authorization: `Bearer ${adminToken}` }
    });
    assert(gsrSubRes.statusCode === 200, 'GET /api/sat/sub-evidence/GSR.01 returns HTTP 200');
    const gsrItems = gsrSubRes.body?.evidence_items || [];
    assert(gsrItems.length === 5, `Mapped GSR.01 standard returns 5 sub-evidence items via book_reference_code ACT.03 (got ${gsrItems.length})`);
    assert(actItems[0]?.id === gsrItems[0]?.id, 'GSR.01 maps to exact same evidence item IDs as ACT.03');

    // 10. User Management Authorization & RBAC
    console.log('\n--- 4. User Management Endpoint Protection ---');
    const unauthUsersRes = await makeRequest({ path: '/api/users' });
    assert(unauthUsersRes.statusCode === 401, 'GET /api/users rejects unauthenticated requests with HTTP 401');

    console.log('\n========================================================');
    console.log(`📊 REGRESSION SUITE: ${passed} PASSED, ${failed} FAILED`);
    console.log('========================================================\n');

    if (failed > 0) process.exit(1);
  } finally {
    if (server) {
      await new Promise(r => server.close(r));
    }
  }
}

runRegression().catch(err => {
  console.error('Test execution failed:', err);
  process.exit(1);
});
