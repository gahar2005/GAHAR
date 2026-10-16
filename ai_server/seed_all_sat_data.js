const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

async function runFullSeed() {
  console.log('🚀 Starting Full Database Migration & 16-Chapter SAT Seeding...');

  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.error('❌ No DATABASE_URL found in environment.');
    process.exit(1);
  }

  const pool = new Pool({
    connectionString: databaseUrl,
    ssl: databaseUrl.includes('supabase') ? { rejectUnauthorized: false } : false,
    connectionTimeoutMillis: 10000,
  });

  const client = await pool.connect();

  try {
    console.log('🔌 Connected to PostgreSQL/Supabase database.');

    // Step 1: Run schema.sql to ensure all base tables exist
    console.log('Applying schema.sql...');
    const schemaSql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
    await client.query(schemaSql);
    await client.query('ALTER TABLE sat_standards ADD COLUMN IF NOT EXISTS is_essential BOOLEAN DEFAULT false;');
    console.log('✅ schema.sql applied successfully.');

    // Step 1b: Run gahar_v2_migration.sql to create v2 tables (facility_settings_requests, generated_documents, etc.)
    const v2Path = path.join(__dirname, 'gahar_v2_migration.sql');
    if (fs.existsSync(v2Path)) {
      console.log('Applying gahar_v2_migration.sql...');
      const v2Sql = fs.readFileSync(v2Path, 'utf8');
      await client.query(v2Sql);
      console.log('✅ gahar_v2_migration.sql applied successfully.');
    }

    await client.query('BEGIN');

    // Step 2: Create sat_sub_evidence table
    await client.query(`
      CREATE TABLE IF NOT EXISTS sat_sub_evidence (
        id VARCHAR(50) PRIMARY KEY,
        standard_code VARCHAR(50) NOT NULL,
        item_number INT NOT NULL,
        requirement_text TEXT NOT NULL,
        documents_required TEXT,
        interview_required TEXT,
        observation_required TEXT,
        sort_order INT DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS idx_sat_sub_std ON sat_sub_evidence(standard_code);
    `);

    // Step 3: Create sat_sub_scores table with RLS
    await client.query(`
      CREATE TABLE IF NOT EXISTS sat_sub_scores (
        id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
        facility_id UUID NOT NULL,
        evidence_id VARCHAR(50) NOT NULL,
        standard_code VARCHAR(50) NOT NULL,
        score_value VARCHAR(10) NOT NULL, -- '0', '1', '2', 'N/A'
        notes TEXT,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        UNIQUE(facility_id, evidence_id)
      );
      CREATE INDEX IF NOT EXISTS idx_sat_sub_scores_fac ON sat_sub_scores(facility_id);
      CREATE INDEX IF NOT EXISTS idx_sat_sub_scores_std ON sat_sub_scores(standard_code);
      CREATE INDEX IF NOT EXISTS idx_sat_sub_scores_fac_std ON sat_sub_scores(facility_id, standard_code);

      ALTER TABLE sat_sub_scores ENABLE ROW LEVEL SECURITY;
      DO $$
      BEGIN
        DROP POLICY IF EXISTS tenant_isolation_sat_sub_scores ON sat_sub_scores;
        CREATE POLICY tenant_isolation_sat_sub_scores ON sat_sub_scores
          FOR ALL
          USING (
            facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId')
            OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
          );
      EXCEPTION WHEN OTHERS THEN NULL;
      END $$;
    `);

    // Step 4: Load dataset
    const dataPath = path.join(__dirname, 'sat_full_dataset.json');
    const { standards, subEvidence } = JSON.parse(fs.readFileSync(dataPath, 'utf8'));

    // Step 5: Upsert sat_standards (all 277: 248 chapter + 29 GSR)
    console.log(`Seeding ${standards.length} sat_standards...`);
    for (const s of standards) {
      await client.query(`
        INSERT INTO sat_standards (
          standard_code, chapter_code, item_number, category, standard_title,
          book_reference_code, workbook_sheet, sort_order, is_essential, is_active
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, true)
        ON CONFLICT (standard_code) DO UPDATE SET
          chapter_code = EXCLUDED.chapter_code,
          category = EXCLUDED.category,
          standard_title = EXCLUDED.standard_title,
          book_reference_code = EXCLUDED.book_reference_code,
          workbook_sheet = EXCLUDED.workbook_sheet,
          sort_order = EXCLUDED.sort_order,
          is_essential = EXCLUDED.is_essential,
          is_active = true;
      `, [
        s.standard_code,
        s.chapter_code,
        s.item_number || 1,
        s.category || s.chapter_title,
        s.standard_title,
        s.book_reference_code || null,
        s.workbook_sheet,
        s.sort_order || 0,
        s.is_essential || false,
      ]);
    }
    console.log(`✅ Upserted ${standards.length} standards.`);

    // Step 6: Upsert sat_sub_evidence (all 1,159 items)
    console.log(`Seeding ${subEvidence.length} sat_sub_evidence items...`);
    for (const sub of subEvidence) {
      await client.query(`
        INSERT INTO sat_sub_evidence (
          id, standard_code, item_number, requirement_text,
          documents_required, interview_required, observation_required, sort_order
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (id) DO UPDATE SET
          standard_code = EXCLUDED.standard_code,
          item_number = EXCLUDED.item_number,
          requirement_text = EXCLUDED.requirement_text,
          documents_required = EXCLUDED.documents_required,
          interview_required = EXCLUDED.interview_required,
          observation_required = EXCLUDED.observation_required,
          sort_order = EXCLUDED.sort_order;
      `, [
        sub.id,
        sub.standard_code,
        sub.item_number,
        sub.requirement_text,
        sub.documents_required,
        sub.interview_required,
        sub.observation_required,
        sub.sort_order
      ]);
    }
    console.log(`✅ Upserted ${subEvidence.length} sub-evidence items.`);

    await client.query('COMMIT');
    console.log('🎉 Full database migration and seeding committed successfully!');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Seeding failed, transaction rolled back:', err);
    throw err;
  } finally {
    client.release();
    await pool.end();
  }
}

runFullSeed().catch(err => {
  console.error(err);
  process.exit(1);
});
