-- =============================================================================
-- GAHAR Platform - Migration V5: Consultation Requests & Subscriptions Optimization
-- Phase 2 Production-Readiness (Prepared Migration - DO NOT EXECUTE AUTOMATICALLY)
-- =============================================================================
-- This migration ensures the consultation_requests table supports flexible ID formats
-- and provides optimized indexing for tenant-scoped consultation history.
--
-- STATUS: PREPARED ONLY. Do NOT run against live Supabase database without review.
-- Backward Compatibility: The backend code is adapted to function with the existing
-- schema.sql definition without executing this migration.
-- =============================================================================

-- 1. Ensure consultation_requests table exists
CREATE TABLE IF NOT EXISTS consultation_requests (
    id VARCHAR(64) PRIMARY KEY,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    expert_id VARCHAR(64) NOT NULL,
    expert_name VARCHAR(255) NOT NULL,
    topic VARCHAR(255) NOT NULL,
    preferred_date DATE,
    notes TEXT,
    status VARCHAR(32) NOT NULL DEFAULT 'PENDING',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. Alter column ID to VARCHAR(64) if currently UUID for ID compatibility
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'consultation_requests' 
          AND column_name = 'id' 
          AND data_type = 'uuid'
    ) THEN
        ALTER TABLE consultation_requests ALTER COLUMN id TYPE VARCHAR(64) USING id::text;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Notice altering consultation_requests.id type: %', SQLERRM;
END $$;

-- 3. Composite index for tenant-scoped consultation history ordered by date
CREATE INDEX IF NOT EXISTS idx_consultation_requests_fac_created 
ON consultation_requests(facility_id, created_at DESC);

-- 4. Row Level Security policy for defense-in-depth PostgREST access
ALTER TABLE consultation_requests ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS tenant_isolation_consultations ON consultation_requests;
    CREATE POLICY tenant_isolation_consultations ON consultation_requests
        FOR ALL
        USING (
            facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId')
            OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
        );
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Notice creating tenant isolation policy for consultations: %', SQLERRM;
END $$;
