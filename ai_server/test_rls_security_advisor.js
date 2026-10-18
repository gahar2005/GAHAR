const { Pool } = require('pg');
require('dotenv').config();

async function runSecurityAdvisorVerification() {
  console.log('================================================================');
  console.log('🛡️  SUPABASE SECURITY ADVISOR & RLS VERIFICATION SUITE');
  console.log('================================================================\n');

  if (!process.env.DATABASE_URL) {
    console.log('ℹ️ [SKIPPED] DATABASE_URL is not configured. Live Supabase RLS checks require a connected database.');
    return;
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  let client;
  try {
    client = await pool.connect();
  } catch (connErr) {
    console.warn('⚠️ [SKIPPED] Could not connect to DATABASE_URL:', connErr.message);
    await pool.end().catch(() => {});
    return;
  }

  let passed = 0;
  let failed = 0;

  function assert(condition, testName) {
    if (condition) {
      console.log(`  ✅ PASS: ${testName}`);
      passed++;
    } else {
      console.error(`  ❌ FAIL: ${testName}`);
      failed++;
    }
  }

  try {
    // -------------------------------------------------------------------------
    // 1. SUPABASE SECURITY ADVISOR LIVE CHECK
    // -------------------------------------------------------------------------
    console.log('--- 1. Supabase Security Advisor Status in public schema ---');
    const disabledTablesRes = await client.query(`
      SELECT tablename
      FROM pg_tables
      WHERE schemaname = 'public' AND rowsecurity = false;
    `);
    assert(
      disabledTablesRes.rows.length === 0,
      `No tables in public schema have RLS disabled (Found: ${disabledTablesRes.rows.map(r => r.tablename).join(', ') || '0 tables'})`
    );

    const satStdRls = await client.query(`
      SELECT tablename, rowsecurity
      FROM pg_tables
      WHERE schemaname = 'public' AND tablename = 'sat_standards';
    `);
    assert(satStdRls.rows[0]?.rowsecurity === true, 'public.sat_standards has RLS ENABLED');

    const satSubEvRls = await client.query(`
      SELECT tablename, rowsecurity
      FROM pg_tables
      WHERE schemaname = 'public' AND tablename = 'sat_sub_evidence';
    `);
    assert(satSubEvRls.rows[0]?.rowsecurity === true, 'public.sat_sub_evidence has RLS ENABLED');

    // -------------------------------------------------------------------------
    // 2. CHECK FORCE RLS STATUS (Must be FALSE to prevent breaking backend)
    // -------------------------------------------------------------------------
    console.log('\n--- 2. Architecture Check: FORCE ROW LEVEL SECURITY status ---');
    const forceRlsRes = await client.query(`
      SELECT relname, relforcerowsecurity
      FROM pg_class
      JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
      WHERE pg_namespace.nspname = 'public' AND relname IN ('sat_standards', 'sat_sub_evidence');
    `);
    const forceDisabled = forceRlsRes.rows.every(r => r.relforcerowsecurity === false);
    assert(
      forceDisabled,
      'FORCE RLS is appropriately disabled so backend service connections operate reliably'
    );

    // -------------------------------------------------------------------------
    // 3. POSTGREST / SUPABASE AUTHENTICATED USER CONTEXT TESTS
    // -------------------------------------------------------------------------
    console.log('\n--- 3. PostgREST / Supabase "authenticated" Context Tests ---');

    const facAId = 'a0000000-0000-0000-0000-000000000001';
    const facBId = 'b0000000-0000-0000-0000-000000000002';
    const testClaimsFacA = JSON.stringify({ role: 'FACILITY_ADMIN', facilityId: facAId });
    const testClaimsSuperAdmin = JSON.stringify({ role: 'SUPER_ADMIN', facilityId: null });

    // 3.1 Authenticated facility user can READ sat_standards
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE authenticated');
    await client.query(`SET LOCAL "request.jwt.claims" = '${testClaimsFacA}'`);

    const readStandardsRes = await client.query('SELECT COUNT(*) FROM sat_standards WHERE is_active = true');
    const stdCount = parseInt(readStandardsRes.rows[0].count, 10);
    assert(stdCount > 0, `Authenticated facility user CAN READ sat_standards (${stdCount} standards found)`);

    // 3.2 Authenticated facility user can READ sat_sub_evidence
    const readSubRes = await client.query('SELECT COUNT(*) FROM sat_sub_evidence');
    const subCount = parseInt(readSubRes.rows[0].count, 10);
    assert(subCount > 0, `Authenticated facility user CAN READ sat_sub_evidence (${subCount} items found)`);

    // 3.3 Normal facility user CANNOT INSERT into sat_standards (must fail or 0 rows)
    let insertStdBlocked = false;
    try {
      await client.query(`
        INSERT INTO sat_standards (standard_code, chapter_code, item_number, category, standard_title)
        VALUES ('HACK.01', 'HACK', 99, 'HACK', 'Unauthorized Standard');
      `);
      // If it didn't throw, check if row exists
      const checkHack = await client.query("SELECT * FROM sat_standards WHERE standard_code = 'HACK.01'");
      insertStdBlocked = checkHack.rows.length === 0;
    } catch (e) {
      insertStdBlocked = true; // RLS violation exception
    }
    assert(insertStdBlocked, 'Normal facility user BLOCKED from INSERT into sat_standards (RLS enforced)');

    // 3.4 Normal facility user CANNOT UPDATE sat_standards
    let updateStdBlocked = false;
    try {
      const upRes = await client.query("UPDATE sat_standards SET standard_title = 'Tampered' WHERE standard_code = 'GSR.01'");
      updateStdBlocked = upRes.rowCount === 0;
    } catch (e) {
      updateStdBlocked = true;
    }
    assert(updateStdBlocked, 'Normal facility user BLOCKED from UPDATE on sat_standards (0 rows updated)');

    // 3.5 Normal facility user CANNOT DELETE from sat_standards
    let deleteStdBlocked = false;
    try {
      const delRes = await client.query("DELETE FROM sat_standards WHERE standard_code = 'GSR.01'");
      deleteStdBlocked = delRes.rowCount === 0;
    } catch (e) {
      deleteStdBlocked = true;
    }
    assert(deleteStdBlocked, 'Normal facility user BLOCKED from DELETE on sat_standards (0 rows deleted)');

    // 3.6 Normal facility user CANNOT INSERT into sat_sub_evidence
    let insertSubBlocked = false;
    try {
      await client.query(`
        INSERT INTO sat_sub_evidence (id, standard_code, item_number, requirement_text)
        VALUES ('HACK.01.1', 'GSR.01', 99, 'Malicious Injection');
      `);
      const checkHackSub = await client.query("SELECT * FROM sat_sub_evidence WHERE id = 'HACK.01.1'");
      insertSubBlocked = checkHackSub.rows.length === 0;
    } catch (e) {
      insertSubBlocked = true;
    }
    assert(insertSubBlocked, 'Normal facility user BLOCKED from INSERT into sat_sub_evidence (RLS enforced)');

    // 3.7 Normal facility user CANNOT UPDATE sat_sub_evidence
    let updateSubBlocked = false;
    try {
      const upSub = await client.query("UPDATE sat_sub_evidence SET requirement_text = 'Tampered' WHERE standard_code = 'GSR.01'");
      updateSubBlocked = upSub.rowCount === 0;
    } catch (e) {
      updateSubBlocked = true;
    }
    assert(updateSubBlocked, 'Normal facility user BLOCKED from UPDATE on sat_sub_evidence (0 rows updated)');

    // 3.8 Normal facility user CANNOT DELETE from sat_sub_evidence
    let deleteSubBlocked = false;
    try {
      const delSub = await client.query("DELETE FROM sat_sub_evidence WHERE standard_code = 'GSR.01'");
      deleteSubBlocked = delSub.rowCount === 0;
    } catch (e) {
      deleteSubBlocked = true;
    }
    assert(deleteSubBlocked, 'Normal facility user BLOCKED from DELETE on sat_sub_evidence (0 rows deleted)');

    await client.query('ROLLBACK');

    // -------------------------------------------------------------------------
    // 4. SUPER ADMIN AUTHORIZATION TEST (RLS admin policies)
    // -------------------------------------------------------------------------
    console.log('\n--- 4. Super Admin RLS Management Policy Tests ---');
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE authenticated');
    await client.query(`SET LOCAL "request.jwt.claims" = '${testClaimsSuperAdmin}'`);

    let adminCanManageStd = false;
    try {
      const adminInsert = await client.query(`
        INSERT INTO sat_standards (standard_code, chapter_code, item_number, category, standard_title)
        VALUES ('ADMIN.TEST.01', 'GSR', 999, 'ADMIN TESTING', 'Super Admin Standard')
        ON CONFLICT (standard_code) DO UPDATE SET standard_title = 'Super Admin Standard Updated';
      `);
      adminCanManageStd = adminInsert.rowCount > 0;
      await client.query("DELETE FROM sat_standards WHERE standard_code = 'ADMIN.TEST.01'");
    } catch (e) {
      console.error('Super admin manage error:', e.message);
      adminCanManageStd = false;
    }
    assert(adminCanManageStd, 'Super Admin role with claim role=SUPER_ADMIN can manage sat_standards');

    await client.query('ROLLBACK');

    // -------------------------------------------------------------------------
    // 5. CROSS-TENANT ISOLATION UNDER SUPABASE RLS
    // -------------------------------------------------------------------------
    console.log('\n--- 5. Cross-Tenant Isolation Tests under RLS ---');

    // Setup: ensure test facilities exist in facilities table
    await client.query(`
      INSERT INTO facilities (id, name, type, governorate, contact_person, work_email, phone)
      VALUES 
        ('${facAId}', 'Test Facility A', 'Hospital', 'Cairo', 'Contact A', 'test_a@rls.eg', '0100000001'),
        ('${facBId}', 'Test Facility B', 'Hospital', 'Alexandria', 'Contact B', 'test_b@rls.eg', '0100000002')
      ON CONFLICT (id) DO NOTHING;
    `);

    // Setup: privileged insert of test scores for Facility B
    await client.query(`
      INSERT INTO sat_scores (facility_id, standard_code, score_value, score_percentage, notes)
      VALUES ('${facBId}', 'GSR.01', 'FULLY_MET', 100, 'Confidential Facility B Audit Notes')
      ON CONFLICT (facility_id, standard_code) DO NOTHING;
    `);

    await client.query(`
      INSERT INTO sat_sub_scores (facility_id, evidence_id, standard_code, score_value, notes)
      VALUES ('${facBId}', 'GSR.01.1', 'GSR.01', '2', 'Confidential Subscore B')
      ON CONFLICT (facility_id, evidence_id) DO NOTHING;
    `);

    // Now test as Facility A in authenticated RLS role:
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE authenticated');
    await client.query(`SET LOCAL "request.jwt.claims" = '${testClaimsFacA}'`);

    // 5.1 Facility A tries to SELECT Facility B sat_scores
    const facAScoresFromB = await client.query(`
      SELECT * FROM sat_scores WHERE facility_id = '${facBId}';
    `);
    assert(facAScoresFromB.rows.length === 0, 'Facility A CANNOT READ Facility B sat_scores (0 rows returned)');

    // 5.2 Facility A tries to UPDATE Facility B sat_scores
    const facAUpdateB = await client.query(`
      UPDATE sat_scores SET notes = 'Malicious Hack' WHERE facility_id = '${facBId}';
    `);
    assert(facAUpdateB.rowCount === 0, 'Facility A CANNOT UPDATE Facility B sat_scores (0 rows updated)');

    // 5.3 Facility A tries to DELETE Facility B sat_scores
    const facADeleteB = await client.query(`
      DELETE FROM sat_scores WHERE facility_id = '${facBId}';
    `);
    assert(facADeleteB.rowCount === 0, 'Facility A CANNOT DELETE Facility B sat_scores (0 rows deleted)');

    // 5.4 Facility A tries to SELECT Facility B sat_sub_scores
    const facASubScoresFromB = await client.query(`
      SELECT * FROM sat_sub_scores WHERE facility_id = '${facBId}';
    `);
    assert(facASubScoresFromB.rows.length === 0, 'Facility A CANNOT READ Facility B sat_sub_scores (0 rows returned)');

    // 5.5 Facility A tries to UPDATE Facility B sat_sub_scores
    const facAUpdateSubB = await client.query(`
      UPDATE sat_sub_scores SET notes = 'Malicious Hack' WHERE facility_id = '${facBId}';
    `);
    assert(facAUpdateSubB.rowCount === 0, 'Facility A CANNOT UPDATE Facility B sat_sub_scores (0 rows updated)');

    // 5.6 Facility A tries to DELETE Facility B sat_sub_scores
    const facADeleteSubB = await client.query(`
      DELETE FROM sat_sub_scores WHERE facility_id = '${facBId}';
    `);
    assert(facADeleteSubB.rowCount === 0, 'Facility A CANNOT DELETE Facility B sat_sub_scores (0 rows deleted)');

    await client.query('ROLLBACK');

    // Cleanup test records
    await client.query(`DELETE FROM sat_scores WHERE facility_id IN ('${facAId}', '${facBId}');`);
    await client.query(`DELETE FROM sat_sub_scores WHERE facility_id IN ('${facAId}', '${facBId}');`);
    await client.query(`DELETE FROM facilities WHERE id IN ('${facAId}', '${facBId}');`);

    // -------------------------------------------------------------------------
    // 6. ANONYMOUS ACCESS TEST (RLS Default Deny)
    // -------------------------------------------------------------------------
    console.log('\n--- 6. Anonymous (Public Unauthenticated) Access Tests ---');
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE anon');
    await client.query(`SET LOCAL "request.jwt.claims" = '{}'`);

    // Anon should not see tenant scores
    const anonScores = await client.query('SELECT * FROM sat_scores;');
    assert(anonScores.rows.length === 0, 'Anonymous role CANNOT READ sat_scores (0 rows returned)');

    const anonSubScores = await client.query('SELECT * FROM sat_sub_scores;');
    assert(anonSubScores.rows.length === 0, 'Anonymous role CANNOT READ sat_sub_scores (0 rows returned)');

    await client.query('ROLLBACK');

    console.log('\n================================================================');
    console.log(`🏁 RLS SECURITY TEST RESULTS: ${passed} PASSED, ${failed} FAILED`);
    console.log('================================================================\n');

    process.exit(failed > 0 ? 1 : 0);
  } catch (err) {
    console.error('Fatal error during security test execution:', err);
    await client.query('ROLLBACK').catch(() => {});
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

runSecurityAdvisorVerification();
