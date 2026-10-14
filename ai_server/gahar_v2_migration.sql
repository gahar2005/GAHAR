-- =============================================================================
-- GAHAR Healthcare Accreditation Platform - Database Expansion & Production Migration
-- Target: PostgreSQL / Supabase
-- =============================================================================

-- 1. Facility Applicability Table
CREATE TABLE IF NOT EXISTS facility_applicability (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    question_id VARCHAR(64) NOT NULL,
    answer BOOLEAN NOT NULL DEFAULT true,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_facility_applicability UNIQUE (facility_id, question_id)
);
CREATE INDEX IF NOT EXISTS idx_fac_applicability_fac ON facility_applicability(facility_id);

-- 2. Facility Settings Change Requests (Audit Trail for core profile changes)
CREATE TABLE IF NOT EXISTS facility_settings_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    requested_by UUID REFERENCES users(id) ON DELETE SET NULL,
    field_name VARCHAR(128) NOT NULL,
    old_value TEXT,
    new_value TEXT,
    reason TEXT,
    status VARCHAR(32) NOT NULL DEFAULT 'PENDING_APPROVAL', -- 'PENDING_APPROVAL', 'APPROVED', 'REJECTED'
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_fac_settings_req_fac ON facility_settings_requests(facility_id);

-- 3. Generated Accreditation Documents (Policies, Procedures, Forms, etc.)
CREATE TABLE IF NOT EXISTS generated_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    standard_code VARCHAR(32),
    doc_type VARCHAR(64) NOT NULL, -- 'Policy', 'Procedure', 'Form', 'Checklist', 'Plan'
    doc_code VARCHAR(64) NOT NULL,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    version VARCHAR(32) NOT NULL DEFAULT 'v1.0',
    status VARCHAR(32) NOT NULL DEFAULT 'DRAFT', -- 'DRAFT', 'SUBMITTED_FOR_REVIEW', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED', 'REVISION_REQUIRED', 'ARCHIVED'
    metadata JSONB DEFAULT '{}'::jsonb,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_gen_docs_fac ON generated_documents(facility_id);
CREATE INDEX IF NOT EXISTS idx_gen_docs_std ON generated_documents(standard_code);

-- 4. Document Version Control History
CREATE TABLE IF NOT EXISTS document_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID NOT NULL REFERENCES generated_documents(id) ON DELETE CASCADE,
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    version VARCHAR(32) NOT NULL,
    content TEXT NOT NULL,
    change_summary TEXT,
    author_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_doc_versions_doc ON document_versions(document_id);
CREATE INDEX IF NOT EXISTS idx_doc_versions_fac ON document_versions(facility_id);

-- 5. Mock Surveys & Survey Preparation
CREATE TABLE IF NOT EXISTS mock_surveys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    active_services TEXT[] DEFAULT '{}',
    current_accreditation_status VARCHAR(64) DEFAULT 'INITIAL',
    onsite_days INT NOT NULL DEFAULT 2,
    consultants_count INT NOT NULL DEFAULT 2,
    target_survey_date DATE,
    contact_person VARCHAR(255),
    phone VARCHAR(64),
    status VARCHAR(32) NOT NULL DEFAULT 'REQUESTED', -- 'REQUESTED', 'PROPOSAL_SENT', 'APPROVED', 'SCHEDULED', 'IN_PROGRESS', 'COMPLETED', 'REPORT_ISSUED'
    proposal_price NUMERIC(10,2),
    tracer_findings JSONB DEFAULT '[]'::jsonb,
    final_report_url TEXT,
    final_readiness_score NUMERIC(5,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_mock_surveys_fac ON mock_surveys(facility_id);

-- 6. Expert Hub Bookings
CREATE TABLE IF NOT EXISTS expert_bookings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    expert_id VARCHAR(64) NOT NULL,
    expert_name VARCHAR(255) NOT NULL,
    session_type VARCHAR(64) NOT NULL, -- 'Quick Consultant (30 min)', '1 Hour Training', '2 Hours Training', 'Custom Training Package'
    topic VARCHAR(255) NOT NULL,
    hours INT NOT NULL DEFAULT 1,
    attendees INT NOT NULL DEFAULT 1,
    scheduled_date TIMESTAMP WITH TIME ZONE,
    price NUMERIC(10,2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(10) DEFAULT 'EGP',
    status VARCHAR(32) NOT NULL DEFAULT 'REQUESTED', -- 'REQUESTED', 'PROPOSED', 'APPROVED', 'PAID', 'SCHEDULED', 'COMPLETED', 'CANCELLED'
    rating INT,
    feedback TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_expert_bookings_fac ON expert_bookings(facility_id);

-- 7. Continuous Monitoring KPIs & Action Items
CREATE TABLE IF NOT EXISTS monitoring_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    metric_name VARCHAR(128) NOT NULL,
    metric_type VARCHAR(64) NOT NULL, -- 'CORRECTIVE_ACTION', 'DOCUMENT_REVIEW', 'LICENSE_EXPIRY', 'STAFF_TRAINING', 'EVIDENCE_FRESHNESS'
    department VARCHAR(128),
    current_value NUMERIC(10,2),
    target_value NUMERIC(10,2),
    status VARCHAR(32) NOT NULL DEFAULT 'ON_TRACK', -- 'ON_TRACK', 'AT_RISK', 'OVERDUE', 'COMPLIANT'
    due_date DATE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_monitoring_fac ON monitoring_records(facility_id);

-- 8. Operational & Financial ROI Metrics
CREATE TABLE IF NOT EXISTS roi_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    accreditation_costs NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    consulting_costs NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    training_costs NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    operational_savings NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    hai_reduction_savings NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    los_reduction_savings NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    claims_rejection_savings NUMERIC(12,2) NOT NULL DEFAULT 0.00,
    roi_percentage NUMERIC(6,2) DEFAULT 0.00,
    calculation_period VARCHAR(32) DEFAULT 'Annual',
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_facility_roi UNIQUE(facility_id)
);
CREATE INDEX IF NOT EXISTS idx_roi_metrics_fac ON roi_metrics(facility_id);

-- =============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES FOR NEW TABLES
-- =============================================================================

ALTER TABLE facility_applicability ENABLE ROW LEVEL SECURITY;
ALTER TABLE facility_settings_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE generated_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE mock_surveys ENABLE ROW LEVEL SECURITY;
ALTER TABLE expert_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE monitoring_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE roi_metrics ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS tenant_isolation_fac_applicability ON facility_applicability;
    CREATE POLICY tenant_isolation_fac_applicability ON facility_applicability
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_fac_settings ON facility_settings_requests;
    CREATE POLICY tenant_isolation_fac_settings ON facility_settings_requests
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_gen_docs ON generated_documents;
    CREATE POLICY tenant_isolation_gen_docs ON generated_documents
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_doc_versions ON document_versions;
    CREATE POLICY tenant_isolation_doc_versions ON document_versions
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_mock_surveys ON mock_surveys;
    CREATE POLICY tenant_isolation_mock_surveys ON mock_surveys
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_expert_bookings ON expert_bookings;
    CREATE POLICY tenant_isolation_expert_bookings ON expert_bookings
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_monitoring ON monitoring_records;
    CREATE POLICY tenant_isolation_monitoring ON monitoring_records
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_roi ON roi_metrics;
    CREATE POLICY tenant_isolation_roi ON roi_metrics
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');
END
$$;
