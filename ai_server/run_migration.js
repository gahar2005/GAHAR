const { Pool } = require('c:/code with vscode/my_app/ai_server/node_modules/pg');
const fs = require('fs');
const path = require('path');
require('c:/code with vscode/my_app/ai_server/node_modules/dotenv').config({ path: 'c:/code with vscode/my_app/ai_server/.env' });

async function applyMigration() {
  console.log('🔄 Executing fix_sat_rls.sql against live Supabase database...');
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  const client = await pool.connect();
  try {
    const sqlPath = path.join(__dirname, 'fix_sat_rls.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');

    await client.query('BEGIN');
    await client.query(sql);
    await client.query('COMMIT');

    console.log('✅ Migration executed successfully within transaction.');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

applyMigration();
