-- =============================================================================
-- GAHAR Healthcare Accreditation Platform - Phase 3 & 4 Persistence Migration
-- Adds full PostgreSQL persistence for:
-- 1. gaps (Gap analysis & non-compliance items)
-- 2. action_plans (Corrective action plans)
-- 3. licenses (Facility & statutory licenses)
-- 4. trash (Centralized soft-delete recycling bin)
-- 5. mock_surveys & roi_metrics schema alignment
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Safely alter ID types to VARCHAR(64) to allow UUIDs and prefixed keys
-- -----------------------------------------------------------------------------
DO $$ 
BEGIN
    -- gaps
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'gaps' AND column_name = 'id' AND data_type = 'uuid') THEN
        ALTER TABLE action_plans DROP CONSTRAINT IF EXISTS action_plans_gap_id_fkey;
        ALTER TABLE gaps ALTER COLUMN id TYPE VARCHAR(64) USING id::text;
    END IF;

    -- action_plans
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'action_plans' AND column_name = 'id' AND data_type = 'uuid') THEN
        ALTER TABLE action_plans ALTER COLUMN id TYPE VARCHAR(64) USING id::text;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'action_plans' AND column_name = 'gap_id' AND data_type = 'uuid') THEN
        ALTER TABLE action_plans ALTER COLUMN gap_id TYPE VARCHAR(64) USING gap_id::text;
    END IF;

    -- licenses
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'licenses' AND column_name = 'id' AND data_type = 'uuid') THEN
        ALTER TABLE licenses ALTER COLUMN id TYPE VARCHAR(64) USING id::text;
    END IF;

    -- documents
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'documents' AND column_name = 'id' AND data_type = 'uuid') THEN
        ALTER TABLE documents ALTER COLUMN id TYPE VARCHAR(64) USING id::text;
    END IF;

    -- audit_logs: allow logging all security events without FK failures on invalid/uncreated entities
    ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_facility_id_fkey;
    ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_user_id_fkey;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'facility_id' AND data_type = 'uuid') THEN
        ALTER TABLE audit_logs ALTER COLUMN facility_id TYPE VARCHAR(64) USING facility_id::text;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'audit_logs' AND column_name = 'user_id' AND data_type = 'uuid') THEN
        ALTER TABLE audit_logs ALTER COLUMN user_id TYPE VARCHAR(64) USING user_id::text;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Notice altering column types: %', SQLERRM;
END $$;

-- -----------------------------------------------------------------------------
-- 2. Gaps Table Definition & Columns
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gaps (
    id VARCHAR(64) PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    standard_code VARCHAR(64),
    chapter_code VARCHAR(64),
    gap_title VARCHAR(255),
    title VARCHAR(255),
    description TEXT,
    severity VARCHAR(32) DEFAULT 'medium',
    status VARCHAR(32) DEFAULT 'inProgress',
    responsible_person VARCHAR(255),
    due_date DATE,
    action_plan_id VARCHAR(64),
    evidence_ids TEXT[] DEFAULT '{}',
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE gaps ADD COLUMN IF NOT EXISTS title VARCHAR(255);
ALTER TABLE gaps ADD COLUMN IF NOT EXISTS standard_code VARCHAR(64);
ALTER TABLE gaps ADD COLUMN IF NOT EXISTS chapter_code VARCHAR(64);
ALTER TABLE gaps ADD COLUMN IF NOT EXISTS action_plan_id VARCHAR(64);
ALTER TABLE gaps ADD COLUMN IF NOT EXISTS evidence_ids TEXT[] DEFAULT '{}';
ALTER TABLE gaps ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE gaps ADD COLUMN IF NOT EXISTS deleted_by VARCHAR(255);
ALTER TABLE gaps ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

DO $$ BEGIN
    ALTER TABLE gaps ALTER COLUMN standard_code DROP NOT NULL;
    ALTER TABLE gaps ALTER COLUMN chapter_code DROP NOT NULL;
    ALTER TABLE gaps ALTER COLUMN gap_title DROP NOT NULL;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_gaps_facility ON gaps(facility_id);
CREATE INDEX IF NOT EXISTS idx_gaps_deleted ON gaps(facility_id, deleted_at);

-- -----------------------------------------------------------------------------
-- 3. Action Plans Table Definition & Columns
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS action_plans (
    id VARCHAR(64) PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    gap_id VARCHAR(64),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    assigned_user VARCHAR(255),
    department VARCHAR(128) DEFAULT 'Quality',
    priority VARCHAR(32) DEFAULT 'high',
    start_date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    status VARCHAR(64) DEFAULT 'In Progress',
    progress NUMERIC(5, 2) DEFAULT 0.00,
    notes TEXT[] DEFAULT '{}',
    completion_date TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE action_plans ADD COLUMN IF NOT EXISTS notes TEXT[] DEFAULT '{}';
ALTER TABLE action_plans ADD COLUMN IF NOT EXISTS completion_date TIMESTAMP WITH TIME ZONE;
ALTER TABLE action_plans ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE action_plans ADD COLUMN IF NOT EXISTS deleted_by VARCHAR(255);
ALTER TABLE action_plans ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_action_plans_facility ON action_plans(facility_id);
CREATE INDEX IF NOT EXISTS idx_action_plans_deleted ON action_plans(facility_id, deleted_at);

-- -----------------------------------------------------------------------------
-- 4. Licenses Table Definition & Columns
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS licenses (
    id VARCHAR(64) PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    license_name VARCHAR(255) NOT NULL,
    license_number VARCHAR(128) DEFAULT '',
    issuing_authority VARCHAR(255) DEFAULT 'Ministry of Health',
    issue_date DATE DEFAULT CURRENT_DATE,
    expiration_date DATE DEFAULT (CURRENT_DATE + INTERVAL '1 year'),
    status VARCHAR(32) DEFAULT 'valid',
    responsible_person VARCHAR(255),
    document_url TEXT,
    notes TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE,
    deleted_by VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE licenses ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE licenses ADD COLUMN IF NOT EXISTS deleted_by VARCHAR(255);
ALTER TABLE licenses ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

DO $$ BEGIN
    ALTER TABLE licenses ALTER COLUMN license_number DROP NOT NULL;
    ALTER TABLE licenses ALTER COLUMN issuing_authority DROP NOT NULL;
    ALTER TABLE licenses ALTER COLUMN issue_date DROP NOT NULL;
    ALTER TABLE licenses ALTER COLUMN expiration_date DROP NOT NULL;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_licenses_facility ON licenses(facility_id);
CREATE INDEX IF NOT EXISTS idx_licenses_deleted ON licenses(facility_id, deleted_at);

-- -----------------------------------------------------------------------------
-- 5. Centralized Trash / Recycling Bin Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS trash (
    id VARCHAR(64) PRIMARY KEY,
    item_id VARCHAR(64) NOT NULL,
    item_type VARCHAR(64) NOT NULL,
    item_name VARCHAR(255),
    module VARCHAR(128),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_by VARCHAR(255),
    snapshot JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_trash_facility ON trash(facility_id);
CREATE INDEX IF NOT EXISTS idx_trash_type ON trash(facility_id, item_type);
CREATE INDEX IF NOT EXISTS idx_trash_deleted_at ON trash(facility_id, deleted_at DESC);

-- -----------------------------------------------------------------------------
-- 6. Add deleted_at to documents table
-- -----------------------------------------------------------------------------
ALTER TABLE documents ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE documents ADD COLUMN IF NOT EXISTS deleted_by VARCHAR(255);

-- -----------------------------------------------------------------------------
-- 7. Row Level Security Policies (Defense-in-depth for PostgREST)
-- -----------------------------------------------------------------------------
ALTER TABLE gaps ENABLE ROW LEVEL SECURITY;
ALTER TABLE action_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE trash ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    -- Gaps
    DROP POLICY IF EXISTS tenant_isolation_gaps ON gaps;
    CREATE POLICY tenant_isolation_gaps ON gaps
        FOR ALL
        USING (
            facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId')
            OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
        );

    -- Action Plans
    DROP POLICY IF EXISTS tenant_isolation_action_plans ON action_plans;
    CREATE POLICY tenant_isolation_action_plans ON action_plans
        FOR ALL
        USING (
            facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId')
            OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
        );

    -- Licenses
    DROP POLICY IF EXISTS tenant_isolation_licenses ON licenses;
    CREATE POLICY tenant_isolation_licenses ON licenses
        FOR ALL
        USING (
            facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId')
            OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
        );

    -- Trash
    DROP POLICY IF EXISTS tenant_isolation_trash ON trash;
    CREATE POLICY tenant_isolation_trash ON trash
        FOR ALL
        USING (
            facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId')
            OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
        );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
