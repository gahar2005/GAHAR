const { Pool } = require('pg');
require('dotenv').config();

async function run() {
  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS name_ar VARCHAR(255);
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS ownership VARCHAR(64) DEFAULT 'Private';
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS country VARCHAR(64) DEFAULT 'Egypt';
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS city VARCHAR(128);
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS address_ar TEXT;
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS contact_position VARCHAR(128);
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS landline VARCHAR(64);
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS company_size VARCHAR(64);
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS departments TEXT[] DEFAULT '{}';
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS services TEXT[] DEFAULT '{}';
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS operating_hours VARCHAR(128);
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS has_quality_team BOOLEAN DEFAULT true;
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS accreditation_program VARCHAR(128) DEFAULT 'GAHAR 2025 v2';
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS license_document_url TEXT;
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS authorization_letter_url TEXT;
      ALTER TABLE facilities ADD COLUMN IF NOT EXISTS logo_url TEXT;
    `);
    await client.query('COMMIT');
    console.log('✅ Facilities columns expanded successfully!');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Error expanding schema:', err.message);
  } finally {
    client.release();
    await pool.end();
  }
}

run();
