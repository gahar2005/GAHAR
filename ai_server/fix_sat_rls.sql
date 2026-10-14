-- =============================================================================
-- GAHAR Healthcare Accreditation Platform
-- Migration: Fix Supabase Security Advisor RLS on SAT Reference Tables
-- Target: public.sat_standards & public.sat_sub_evidence
-- =============================================================================

-- 1. Enable Row Level Security (RLS)
ALTER TABLE public.sat_standards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sat_sub_evidence ENABLE ROW LEVEL SECURITY;

-- 2. sat_standards Policies:
-- Allow authenticated application users to read global reference standards
DROP POLICY IF EXISTS sat_standards_read_authenticated ON public.sat_standards;
CREATE POLICY sat_standards_read_authenticated ON public.sat_standards
    FOR SELECT
    TO authenticated
    USING (true);

-- Allow Super Admin role to manage/migrate reference standards via Supabase
DROP POLICY IF EXISTS sat_standards_admin_manage ON public.sat_standards;
CREATE POLICY sat_standards_admin_manage ON public.sat_standards
    FOR ALL
    TO authenticated
    USING (
        (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
    )
    WITH CHECK (
        (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
    );

-- 3. sat_sub_evidence Policies:
-- Allow authenticated application users to read global reference sub-evidence items
DROP POLICY IF EXISTS sat_sub_evidence_read_authenticated ON public.sat_sub_evidence;
CREATE POLICY sat_sub_evidence_read_authenticated ON public.sat_sub_evidence
    FOR SELECT
    TO authenticated
    USING (true);

-- Allow Super Admin role to manage/migrate reference sub-evidence via Supabase
DROP POLICY IF EXISTS sat_sub_evidence_admin_manage ON public.sat_sub_evidence;
CREATE POLICY sat_sub_evidence_admin_manage ON public.sat_sub_evidence
    FOR ALL
    TO authenticated
    USING (
        (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
    )
    WITH CHECK (
        (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
    );
