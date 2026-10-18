const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

async function applyMigration() {
  console.log('🔄 Executing Complete Migration Pipeline against database...');
  if (!process.env.DATABASE_URL) {
    console.error('❌ DATABASE_URL environment variable is required to run migrations.');
    process.exit(1);
  }

  const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.DATABASE_URL.includes('supabase') ? { rejectUnauthorized: false } : false
  });

  const client = await pool.connect();
  try {
    const migrationFiles = [
      { name: 'schema.sql', path: path.join(__dirname, 'schema.sql') },
      { name: 'gahar_v2_migration.sql', path: path.join(__dirname, 'gahar_v2_migration.sql') },
      { name: 'fix_sat_dataset_duplicates.sql', path: path.join(__dirname, 'fix_sat_dataset_duplicates.sql') },
      { name: 'gahar_v3_persistence_migration.sql', path: path.join(__dirname, 'gahar_v3_persistence_migration.sql') },
    ];

    for (const file of migrationFiles) {
      if (fs.existsSync(file.path)) {
        console.log(`Applying ${file.name}...`);
        const sql = fs.readFileSync(file.path, 'utf8');
        await client.query(sql);
        console.log(`✅ ${file.name} applied successfully.`);
      }
    }

    console.log('🎉 All migrations executed successfully.');
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

applyMigration();
