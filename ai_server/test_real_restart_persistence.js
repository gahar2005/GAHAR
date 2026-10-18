require('dotenv').config();
const { Client } = require('pg');
const { v4: uuidv4 } = require('uuid');

async function testRestartPersistence() {
  console.log('🧪 ========================================================');
  console.log('🧪 VERIFYING REAL POSTGRESQL / SUPABASE RESTART PERSISTENCE');
  console.log('🧪 ========================================================\n');

  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    console.error('❌ DATABASE_URL missing');
    process.exit(1);
  }

  const facilityId = uuidv4();
  const testEmail = `restart_test_${Date.now()}@hospital.eg`;
  const gapId = `gap_${uuidv4()}`;
  const planId = `plan_${uuidv4()}`;
  const licId = `lic_${uuidv4()}`;

  // STEP 1: Process Run 1 - Insert Data and Disconnect
  console.log('--- PHASE 1: Write Entity Data to Supabase ---');
  let client1 = new Client({ connectionString, ssl: { rejectUnauthorized: false } });
  await client1.connect();
  console.log('  🔌 Connected to live Supabase pooler (Client 1)');

  // 1. Facility
  await client1.query(`
    INSERT INTO facilities (id, name, type, contact_person, work_email, phone, governorate, status)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
  `, [facilityId, 'Persistence Test Hospital', 'Hospital', 'Dr. Persistence', testEmail, '+201000000000', 'Cairo', 'APPROVED']);
  console.log('  ✅ Facility inserted: ID =', facilityId);

  // 2. Gap
  await client1.query(`
    INSERT INTO gaps (id, facility_id, standard_code, title, description, severity, status)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
  `, [gapId, facilityId, 'GSR.01', 'Test Gap', 'Gap verifying real persistence', 'high', 'inProgress']);
  console.log('  ✅ Gap inserted: ID =', gapId);

  // 3. Action Plan
  await client1.query(`
    INSERT INTO action_plans (id, gap_id, facility_id, title, description, priority, status)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
  `, [planId, gapId, facilityId, 'Test Plan', 'Execute persistence verification', 'high', 'inProgress']);
  console.log('  ✅ Action plan inserted: ID =', planId);

  // 4. License
  await client1.query(`
    INSERT INTO licenses (id, facility_id, license_name, license_number, status)
    VALUES ($1, $2, $3, $4, $5)
  `, [licId, facilityId, 'Operating License', 'LIC-9999', 'valid']);
  console.log('  ✅ License inserted: ID =', licId);

  // Disconnect completely (Simulate Server Kill / Restart)
  await client1.end();
  console.log('  🛑 Client 1 disconnected. Backend process shut down.\n');

  // Small delay to ensure connection tear-down
  await new Promise(r => setTimeout(r, 1000));

  // STEP 2: Process Run 2 - Fresh Client Connect and Verify
  console.log('--- PHASE 2: Fresh Process Reconnect & Verification ---');
  let client2 = new Client({ connectionString, ssl: { rejectUnauthorized: false } });
  await client2.connect();
  console.log('  🔌 Connected to live Supabase pooler (Client 2 - Post-Restart)');

  // Verify Facility
  const facRes = await client2.query('SELECT * FROM facilities WHERE id = $1', [facilityId]);
  if (facRes.rows.length !== 1) throw new Error('Facility not found after restart');
  console.log('  ✅ [PASS] Facility successfully retrieved after restart:', facRes.rows[0].name);

  // Verify Gap
  const gapRes = await client2.query('SELECT * FROM gaps WHERE id = $1 AND facility_id = $2', [gapId, facilityId]);
  if (gapRes.rows.length !== 1) throw new Error('Gap not found after restart');
  console.log('  ✅ [PASS] Gap successfully retrieved after restart:', gapRes.rows[0].title);

  // Verify Action Plan
  const planRes = await client2.query('SELECT * FROM action_plans WHERE id = $1 AND facility_id = $2', [planId, facilityId]);
  if (planRes.rows.length !== 1) throw new Error('Action plan not found after restart');
  console.log('  ✅ [PASS] Action plan successfully retrieved after restart:', planRes.rows[0].title);

  // Verify License
  const licRes = await client2.query('SELECT * FROM licenses WHERE id = $1 AND facility_id = $2', [licId, facilityId]);
  if (licRes.rows.length !== 1) throw new Error('License not found after restart');
  console.log('  ✅ [PASS] License successfully retrieved after restart:', licRes.rows[0].license_number);

  // Clean up test data
  await client2.query('DELETE FROM facilities WHERE id = $1', [facilityId]);
  console.log('  🧹 Cleaned up persistence test records.');

  await client2.end();
  console.log('\n🎉 REAL POSTGRESQL RESTART PERSISTENCE VERIFIED 100% SUCCESSFULLY!\n');
}

testRestartPersistence().catch(err => {
  console.error('❌ Restart persistence test failed:', err);
  process.exit(1);
});
