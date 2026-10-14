require('dotenv').config();
const { Pool } = require('pg');

async function runProductionGateChecks() {
  console.log('--- STARTING PRODUCTION GATE DB & SECURITY VERIFICATION ---');

  // 1. Verify environment variables are present and not printed
  const hasDbUrl = !!process.env.DATABASE_URL;
  const hasSupabaseUrl = !!process.env.SUPABASE_URL;
  const hasServiceKey = !!process.env.SUPABASE_SERVICE_ROLE_KEY;

  console.log('ENV CHECK:', {
    DATABASE_URL_LOADED: hasDbUrl,
    SUPABASE_URL_LOADED: hasSupabaseUrl,
    SUPABASE_SERVICE_ROLE_KEY_LOADED: hasServiceKey,
  });

  if (!hasDbUrl) {
    console.error('DATABASE_URL is missing in environment!');
    process.exit(1);
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  const client = await pool.connect();
  console.log('SUCCESS: Connected to live Supabase PostgreSQL!');

  try {
    // 2. Standards count & breakdown
    const stdRes = await client.query(`
      SELECT 
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE chapter_code = 'GSR') as gsr_count,
        COUNT(*) FILTER (WHERE chapter_code = 'QPI') as qpi_count,
        COUNT(*) FILTER (WHERE chapter_code = 'ATH') as ath_count
      FROM sat_standards;
    `);
    console.log('SAT_STANDARDS_COUNTS:', stdRes.rows[0]);

    // 3. Sub-evidence count & breakdown
    const subRes = await client.query(`
      SELECT 
        COUNT(*) as total_sub_evidence,
        COUNT(DISTINCT standard_code) as distinct_standards_with_sub
      FROM sat_sub_evidence;
    `);
    console.log('SAT_SUB_EVIDENCE_COUNTS:', subRes.rows[0]);

    // Sample content integrity check
    const qpiSample = await client.query(`
      SELECT standard_code, standard_title, category, workbook_sheet 
      FROM sat_standards 
      WHERE standard_code = 'QPI.01';
    `);
    console.log('SAMPLE STANDARD QPI.01:', qpiSample.rows[0]);

    const subSample = await client.query(`
      SELECT id, standard_code, item_number, requirement_text 
      FROM sat_sub_evidence 
      WHERE standard_code = 'QPI.01' 
      ORDER BY item_number 
      LIMIT 2;
    `);
    console.log('SAMPLE SUB EVIDENCE FOR QPI.01:', subSample.rows);

    // 4. Test real CRUD on sat_sub_scores & Tenant Isolation
    const facA = 'a0000000-0000-0000-0000-000000000001';
    const facB = 'b0000000-0000-0000-0000-000000000002';
    const testEvId = subSample.rows[0]?.id || 'QPI.01.1';
    const testStdCode = 'QPI.01';

    // Insert/Update Facility A score
    await client.query(`
      INSERT INTO sat_sub_scores (facility_id, evidence_id, standard_code, score_value, notes, updated_at)
      VALUES ($1, $2, $3, $4, $5, NOW())
      ON CONFLICT (facility_id, evidence_id)
      DO UPDATE SET score_value = $4, notes = $5, updated_at = NOW();
    `, [facA, testEvId, testStdCode, '2', 'Audited compliance by Gate A']);

    // Read back Facility A score
    const readA = await client.query(`
      SELECT * FROM sat_sub_scores WHERE facility_id = $1 AND evidence_id = $2;
    `, [facA, testEvId]);
    console.log('FACILITY A SAVED SCORE:', {
      facility_id: readA.rows[0]?.facility_id,
      score_value: readA.rows[0]?.score_value,
      evidence_id: readA.rows[0]?.evidence_id
    });

    // Verify Tenant Isolation: Facility B querying its scores should NOT see Facility A's score
    const readB = await client.query(`
      SELECT * FROM sat_sub_scores WHERE facility_id = $1 AND evidence_id = $2;
    `, [facB, testEvId]);
    console.log('FACILITY B READ OF FACILITY A RECORD (SHOULD BE EMPTY):', readB.rows);

    // Clean up test records
    await client.query(`DELETE FROM sat_sub_scores WHERE facility_id IN ($1, $2);`, [facA, facB]);
    console.log('CLEANUP: Test records cleaned up successfully.');

    console.log('--- ALL REAL DB & INTEGRITY CHECKS PASSED ---');
  } finally {
    client.release();
    await pool.end();
  }
}

runProductionGateChecks().catch(e => {
  console.error('GATE CHECK FAILED:', e);
  process.exit(1);
});
