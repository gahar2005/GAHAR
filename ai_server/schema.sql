-- =============================================================================
-- GAHAR Healthcare Accreditation Platform - Production SQL Database Schema
-- Target Database: PostgreSQL / Supabase
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- -----------------------------------------------------------------------------
-- 1. Subscription Plans Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscription_plans (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price_egp NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    billing_period VARCHAR(32) NOT NULL DEFAULT 'annual', -- 'monthly', 'annual'
    facility_limit INT NOT NULL DEFAULT 1,
    user_limit INT NOT NULL DEFAULT 10,
    features JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- -----------------------------------------------------------------------------
-- 2. Facilities / Tenants Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS facilities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    type VARCHAR(128) NOT NULL, -- 'Hospital', 'Specialized Hospital', 'Primary Care', 'Lab', 'Radiology'
    governorate VARCHAR(128) NOT NULL,
    address TEXT,
    bed_capacity INT NOT NULL DEFAULT 0,
    contact_person VARCHAR(255) NOT NULL,
    work_email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(64) NOT NULL,
    gahar_version VARCHAR(64) DEFAULT 'GAHAR 2025 v2',
    target_survey_date DATE,
    status VARCHAR(64) NOT NULL DEFAULT 'PENDING_REVIEW', -- 'PENDING_PAYMENT', 'PENDING_REVIEW', 'PAYMENT_VERIFICATION', 'APPROVED', 'REJECTED', 'SUSPENDED', 'ACTIVE', 'EXPIRED'
    subscription_plan_id VARCHAR(64) REFERENCES subscription_plans(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_facilities_status ON facilities(status);
CREATE INDEX IF NOT EXISTS idx_facilities_work_email ON facilities(work_email);

-- -----------------------------------------------------------------------------
-- 3. Users Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    role VARCHAR(64) NOT NULL, -- 'SUPER_ADMIN', 'FACILITY_ADMIN', 'QUALITY_MANAGER', 'STAFF', 'EXPERT'
    facility_id UUID REFERENCES facilities(id) ON DELETE CASCADE,
    department VARCHAR(128),
    phone VARCHAR(64),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_facility_id ON users(facility_id);

-- -----------------------------------------------------------------------------
-- 4. Subscriptions Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    plan_id VARCHAR(64) NOT NULL REFERENCES subscription_plans(id),
    status VARCHAR(64) NOT NULL DEFAULT 'ACTIVE', -- 'ACTIVE', 'PENDING_PAYMENT', 'EXPIRED', 'CANCELLED'
    start_date TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    end_date TIMESTAMP WITH TIME ZONE NOT NULL,
    auto_renew BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_facility ON subscriptions(facility_id);

-- -----------------------------------------------------------------------------
-- 5. Payments Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    plan_id VARCHAR(64) NOT NULL REFERENCES subscription_plans(id),
    amount NUMERIC(10, 2) NOT NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'EGP',
    payment_method VARCHAR(64) NOT NULL, -- 'Vodafone Cash', 'Bank Transfer', 'Online Gateway'
    status VARCHAR(64) NOT NULL DEFAULT 'PENDING_VERIFICATION', -- 'PENDING_VERIFICATION', 'VERIFIED', 'REJECTED', 'FAILED'
    transaction_ref VARCHAR(255),
    proof_url TEXT,
    verified_by UUID REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_payments_facility ON payments(facility_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);

-- -----------------------------------------------------------------------------
-- 6. Gap Items Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gaps (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    standard_code VARCHAR(64) NOT NULL,
    chapter_code VARCHAR(64) NOT NULL,
    gap_title VARCHAR(255) NOT NULL,
    description TEXT,
    severity VARCHAR(32) NOT NULL DEFAULT 'medium', -- 'critical', 'high', 'medium', 'low'
    status VARCHAR(32) NOT NULL DEFAULT 'inProgress', -- 'notStarted', 'inProgress', 'compliant'
    responsible_person VARCHAR(255),
    due_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_gaps_facility ON gaps(facility_id);

-- -----------------------------------------------------------------------------
-- 7. Action Plans Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS action_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    gap_id UUID REFERENCES gaps(id) ON DELETE SET NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    assigned_user VARCHAR(255),
    department VARCHAR(128),
    priority VARCHAR(32) DEFAULT 'high',
    start_date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    status VARCHAR(64) DEFAULT 'In Progress',
    progress NUMERIC(5, 2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_action_plans_facility ON action_plans(facility_id);

-- -----------------------------------------------------------------------------
-- 8. Licenses Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS licenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    license_name VARCHAR(255) NOT NULL,
    license_number VARCHAR(128) NOT NULL,
    issuing_authority VARCHAR(255) NOT NULL,
    issue_date DATE NOT NULL,
    expiration_date DATE NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'valid', -- 'valid', 'expiringSoon', 'expired'
    responsible_person VARCHAR(255),
    document_url TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_licenses_facility ON licenses(facility_id);

-- -----------------------------------------------------------------------------
-- 9. Documents Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    requirement_code VARCHAR(64),
    title VARCHAR(255) NOT NULL,
    category VARCHAR(128) NOT NULL,
    file_path TEXT,
    version VARCHAR(32) DEFAULT 'v1.0',
    status VARCHAR(64) DEFAULT 'Approved',
    uploaded_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_documents_facility ON documents(facility_id);

-- -----------------------------------------------------------------------------
-- 10. Audit Logs Table
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID REFERENCES facilities(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    user_email VARCHAR(255),
    action VARCHAR(128) NOT NULL,
    entity_type VARCHAR(64),
    entity_id VARCHAR(255),
    details JSONB DEFAULT '{}'::jsonb,
    ip_address VARCHAR(64),
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_facility ON audit_logs(facility_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);

CREATE TABLE IF NOT EXISTS password_resets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_password_resets_token ON password_resets(token_hash);
CREATE INDEX IF NOT EXISTS idx_password_resets_email ON password_resets(email);

-- -----------------------------------------------------------------------------
-- 11. Consultation Requests Table (Experts Hub)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS consultation_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id UUID NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    expert_id VARCHAR(64) NOT NULL,
    expert_name VARCHAR(255) NOT NULL,
    topic VARCHAR(255) NOT NULL,
    preferred_date DATE,
    notes TEXT,
    status VARCHAR(32) NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'ACCEPTED', 'COMPLETED', 'CANCELLED'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_consultation_facility ON consultation_requests(facility_id);

-- -----------------------------------------------------------------------------
-- 12. Initial Seed Data
-- -----------------------------------------------------------------------------
INSERT INTO subscription_plans (id, name, price_egp, billing_period, facility_limit, user_limit, features)
VALUES 
('plan_standard', 'Standard Hospital', 45000.00, 'annual', 1, 20, '["Full GAHAR 2025 Checklist", "AI Copilot Assistance", "Gap Analysis & Action Plans", "Licenses Tracker", "Standard Support"]'::jsonb),
('plan_enterprise', 'Enterprise Multi-Branch', 120000.00, 'annual', 5, 100, '["All Standard Features", "Unlimited Branches", "Dedicated Accreditation Advisor", "Priority AI Processing", "Custom Audit Reports"]'::jsonb),
('plan_lab', 'Specialized Center / Lab', 25000.00, 'annual', 1, 10, '["Lab & Radiology GAHAR Modules", "AI Copilot", "Evidence Management"]'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Seed Default Super Admin Account
-- NOTE: actual email/password must come from SUPER_ADMIN_EMAIL / SUPER_ADMIN_PASSWORD env vars at runtime.
-- This seed row uses a placeholder hash; the real hash is set dynamically by server.js on first boot.
INSERT INTO users (id, email, password_hash, full_name, role, facility_id, is_active)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'superadmin@gahar.gov.eg',
    '$2a$10$placeholder_hash_replaced_at_runtime_by_server',
    'GAHAR Super Admin',
    'SUPER_ADMIN',
    NULL,
    true
) ON CONFLICT (email) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 13. Row Level Security (RLS) Policies for Multi-Tenancy
-- -----------------------------------------------------------------------------
ALTER TABLE facilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE gaps ENABLE ROW LEVEL SECURITY;
ALTER TABLE action_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE consultation_requests ENABLE ROW LEVEL SECURITY;

-- Dynamic tenant isolation policies based on verified JWT claims (or super admin bypass)
DO $$
BEGIN
    DROP POLICY IF EXISTS tenant_isolation_facilities ON facilities;
    CREATE POLICY tenant_isolation_facilities ON facilities
        FOR ALL
        USING (id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_users ON users;
    CREATE POLICY tenant_isolation_users ON users
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_gaps ON gaps;
    CREATE POLICY tenant_isolation_gaps ON gaps
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_action_plans ON action_plans;
    CREATE POLICY tenant_isolation_action_plans ON action_plans
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_licenses ON licenses;
    CREATE POLICY tenant_isolation_licenses ON licenses
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_documents ON documents;
    CREATE POLICY tenant_isolation_documents ON documents
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');

    DROP POLICY IF EXISTS tenant_isolation_payments ON payments;
    CREATE POLICY tenant_isolation_payments ON payments
        FOR ALL
        USING (facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId') OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');
END
$$;

-- =============================================================================
-- SAT (Self-Assessment Tool) Tables
-- Source: Hospital Full Accreditation SAT 2025 Excel Workbook
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 14. SAT Standards Reference Table (platform-wide, not per-facility)
-- Contains all items from the Excel workbook: GSR, QPI, ATH chapters
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sat_standards (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    standard_code  VARCHAR(32)  NOT NULL UNIQUE,   -- e.g. 'GSR.01'
    chapter_code   VARCHAR(16)  NOT NULL,            -- e.g. 'GSR', 'QPI', 'ATH'
    item_number    INT          NOT NULL DEFAULT 0,  -- sequential # within chapter
    category       VARCHAR(256) NOT NULL,            -- section header from Excel
    category_ar    VARCHAR(256),                     -- Arabic section header
    standard_title TEXT         NOT NULL,            -- NSR KEYWORDS column
    standard_title_ar TEXT,                          -- Arabic title (if available)
    book_reference_code VARCHAR(32),                 -- CODE IN THIS BOOK column e.g. 'ACT.03'
    workbook_sheet VARCHAR(32)  NOT NULL DEFAULT 'GSR', -- which Excel sheet
    is_essential   BOOLEAN      NOT NULL DEFAULT false,
    is_active      BOOLEAN      NOT NULL DEFAULT true,
    sort_order     INT          NOT NULL DEFAULT 0,
    created_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sat_standards_chapter ON sat_standards(chapter_code);
CREATE INDEX IF NOT EXISTS idx_sat_standards_category ON sat_standards(category);
CREATE INDEX IF NOT EXISTS idx_sat_standards_sort ON sat_standards(workbook_sheet, sort_order);

-- -----------------------------------------------------------------------------
-- 14b. SAT Sub-Evidence / Measurement Items Table (16 chapters, 0/1/2 scoring)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sat_sub_evidence (
    id VARCHAR(50) PRIMARY KEY, -- e.g. 'QPI.01.1'
    standard_code VARCHAR(50) NOT NULL,
    item_number INT NOT NULL,
    requirement_text TEXT NOT NULL,
    documents_required TEXT,
    interview_required TEXT,
    observation_required TEXT,
    sort_order INT DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_sat_sub_std ON sat_sub_evidence(standard_code);

ALTER TABLE sat_sub_evidence ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    DROP POLICY IF EXISTS sat_sub_evidence_read_authenticated ON sat_sub_evidence;
    CREATE POLICY sat_sub_evidence_read_authenticated ON sat_sub_evidence
        FOR SELECT
        TO authenticated
        USING (true);

    DROP POLICY IF EXISTS sat_sub_evidence_admin_manage ON sat_sub_evidence;
    CREATE POLICY sat_sub_evidence_admin_manage ON sat_sub_evidence
        FOR ALL
        TO authenticated
        USING ((current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN')
        WITH CHECK ((current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- -----------------------------------------------------------------------------
-- 14c. SAT Sub-Evidence Scores Table (per-facility, 0/1/2/NA scoring)
-- -----------------------------------------------------------------------------
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

-- -----------------------------------------------------------------------------
-- 15. SAT Scores Table (per-facility, tenant-isolated)
-- Scoring model confirmed from Excel: SCORING column uses N/A (not yet assessed)
-- Implemented scale:
--   FULLY_MET       = 100% score weight
--   PARTIALLY_MET   = 50% score weight
--   NOT_MET         = 0% score weight
--   NOT_APPLICABLE  = excluded from denominator
--   NOT_ASSESSED    = not yet assessed (default/pending)
-- Chapter % = SUM(applicable scores) / (COUNT(applicable) * 100) * 100
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sat_scores (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    facility_id    UUID        NOT NULL REFERENCES facilities(id) ON DELETE CASCADE,
    standard_code  VARCHAR(32) NOT NULL,
    score_value    VARCHAR(32) NOT NULL DEFAULT 'NOT_ASSESSED',
    -- 'FULLY_MET' | 'PARTIALLY_MET' | 'NOT_MET' | 'NOT_APPLICABLE' | 'NOT_ASSESSED'
    score_percentage INT,          -- numeric: 100 | 50 | 0 | NULL (not_applicable) | NULL (not_assessed)
    notes          TEXT,
    assessed_by    VARCHAR(255),   -- user who saved this score
    assessed_at    TIMESTAMP WITH TIME ZONE,
    created_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT sat_scores_facility_standard_uq UNIQUE (facility_id, standard_code),
    CONSTRAINT sat_scores_value_chk CHECK (
        score_value IN ('FULLY_MET','PARTIALLY_MET','NOT_MET','NOT_APPLICABLE','NOT_ASSESSED')
    )
);

CREATE INDEX IF NOT EXISTS idx_sat_scores_facility ON sat_scores(facility_id);
CREATE INDEX IF NOT EXISTS idx_sat_scores_standard ON sat_scores(standard_code);
CREATE INDEX IF NOT EXISTS idx_sat_scores_facility_chapter ON sat_scores(facility_id, standard_code);

-- RLS for sat_scores (tenant isolation)
ALTER TABLE sat_scores ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS tenant_isolation_sat_scores ON sat_scores;
    CREATE POLICY tenant_isolation_sat_scores ON sat_scores
        FOR ALL
        USING (
            facility_id::text = (current_setting('request.jwt.claims', true)::jsonb->>'facilityId')
            OR (current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN'
        );
END
$$;

-- RLS for sat_standards (Master reference data: authenticated read, super admin manage)
ALTER TABLE sat_standards ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    DROP POLICY IF EXISTS sat_standards_read_authenticated ON sat_standards;
    CREATE POLICY sat_standards_read_authenticated ON sat_standards
        FOR SELECT
        TO authenticated
        USING (true);

    DROP POLICY IF EXISTS sat_standards_admin_manage ON sat_standards;
    CREATE POLICY sat_standards_admin_manage ON sat_standards
        FOR ALL
        TO authenticated
        USING ((current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN')
        WITH CHECK ((current_setting('request.jwt.claims', true)::jsonb->>'role') = 'SUPER_ADMIN');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- -----------------------------------------------------------------------------
-- 16. SAT Standards Seed Data
-- Source: GSR sheet of Hospital Full Accreditation SAT 2025 Excel workbook
-- All 29 GSR items confirmed from screenshots
-- QPI and ATH frameworks seeded as placeholders (PARTIALLY IMPLEMENTED)
-- -----------------------------------------------------------------------------
INSERT INTO sat_standards
    (standard_code, chapter_code, item_number, category, category_ar, standard_title, standard_title_ar, book_reference_code, workbook_sheet, sort_order)
VALUES
-- ── GENERAL PATIENT SAFETY (GSR.01 – GSR.11) ─────────────────────────────
('GSR.01', 'GSR',  1, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Patient identification',                                   'تعريف هوية المريض',                         'ACT.03', 'GSR',  10),
('GSR.02', 'GSR',  2, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Verbal and telephone orders',                              'الأوامر الشفهية والهاتفية',                  'ICD.18', 'GSR',  20),
('GSR.03', 'GSR',  3, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Critical Results',                                         'النتائج الحرجة',                             'ICD.19', 'GSR',  30),
('GSR.04', 'GSR',  4, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Handover Communication',                                   'التواصل عند التسليم',                        'ACT.08', 'GSR',  40),
('GSR.05', 'GSR',  5, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Fall screening and prevention',                            'الفحص والوقاية من السقوط',                   'ICD.10', 'GSR',  50),
('GSR.06', 'GSR',  6, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Pressure Ulcer Prevention',                                'الوقاية من قرح الضغط',                       'ICD.11', 'GSR',  60),
('GSR.07', 'GSR',  7, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Venous Thromboembolism Prophylaxis',                       'الوقاية من تجلط الأوردة',                    'ICD.12', 'GSR',  70),
('GSR.08', 'GSR',  8, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Critical Alarms',                                          'التنبيهات الحرجة',                           'CSS.02', 'GSR',  80),
('GSR.09', 'GSR',  9, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Catheter and tube misconnections',                         'الأخطاء في توصيل القسطرات والأنابيب',        'CSS.03', 'GSR',  90),
('GSR.10', 'GSR', 10, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Recognition and response to clinical deterioration',       'التعرف على التدهور السريري والاستجابة له',   'ICD.22', 'GSR', 100),
('GSR.11', 'GSR', 11, 'GENERAL PATIENT SAFETY', 'سلامة المريض العامة',       'Cardiopulmonary resuscitation',                            'الإنعاش القلبي الرئوي',                      'CSS.05', 'GSR', 110),
-- ── DIAGNOSTIC AND ANCILLARY SERVICES (GSR.12 – GSR.13) ──────────────────
('GSR.12', 'GSR', 12, 'DIAGNOSTIC AND ANCILLARY SERVICES', 'الخدمات التشخيصية والمساندة', 'Radiation Safety Program',             'برنامج سلامة الإشعاع',                       'DAS.09', 'GSR', 120),
('GSR.13', 'GSR', 13, 'DIAGNOSTIC AND ANCILLARY SERVICES', 'الخدمات التشخيصية والمساندة', 'Laboratory Safety Program',            'برنامج سلامة المختبر',                       'DAS.23', 'GSR', 130),
-- ── SURGICAL AND INVASIVE PROCEDURAL SAFETY (GSR.14 – GSR.17) ───────────
('GSR.14', 'GSR', 14, 'SURGICAL AND INVASIVE PROCEDURAL SAFETY', 'سلامة الجراحة والإجراءات الباضعة', 'Surgical Site Marking',      'تحديد موقع العملية الجراحية',                'SAS.05', 'GSR', 140),
('GSR.15', 'GSR', 15, 'SURGICAL AND INVASIVE PROCEDURAL SAFETY', 'سلامة الجراحة والإجراءات الباضعة', 'Pre-operative Checklist',    'قائمة تحقق ما قبل الجراحة',                  'SAS.06', 'GSR', 150),
('GSR.16', 'GSR', 16, 'SURGICAL AND INVASIVE PROCEDURAL SAFETY', 'سلامة الجراحة والإجراءات الباضعة', 'Time-out / sing out',        'مهلة التوقف / الخروج الغنائي',               'SAS.07', 'GSR', 160),
('GSR.17', 'GSR', 17, 'SURGICAL AND INVASIVE PROCEDURAL SAFETY', 'سلامة الجراحة والإجراءات الباضعة', 'Instrument Retention Prevention', 'منع احتجاز الأدوات الجراحية',             'SAS.09', 'GSR', 170),
-- ── MEDICATION MANAGEMENT AND SAFETY (GSR.18 – GSR.21) ───────────────────
('GSR.18', 'GSR', 18, 'MEDICATION MANAGEMENT AND SAFETY', 'إدارة الأدوية وسلامتها', 'Medication Reconciliation, best possible medication history (BPMH)', 'مطابقة الأدوية وأفضل تاريخ دوائي ممكن', 'MMS.10', 'GSR', 180),
('GSR.19', 'GSR', 19, 'MEDICATION MANAGEMENT AND SAFETY', 'إدارة الأدوية وسلامتها', 'Medication storage and labelling',             'تخزين الأدوية ووضع الملصقات',               'MMS.04', 'GSR', 190),
('GSR.20', 'GSR', 20, 'MEDICATION MANAGEMENT AND SAFETY', 'إدارة الأدوية وسلامتها', 'High-alert medications and concentrated electrolytes', 'الأدوية عالية التنبيه والمحاليل الكهربائية المركزة', 'MMS.06', 'GSR', 200),
('GSR.21', 'GSR', 21, 'MEDICATION MANAGEMENT AND SAFETY', 'إدارة الأدوية وسلامتها', 'Look-alike and Sound-like medications.',        'الأدوية المتشابهة في الشكل والصوت',          'MMS.07', 'GSR', 210),
-- ── INFECTION PREVENTION AND CONTROL (GSR.22) ────────────────────────────
('GSR.22', 'GSR', 22, 'INFECTION PREVENTION AND CONTROL', 'الوقاية من العدوى ومكافحتها', 'Hand Hygiene',                           'نظافة الأيدي',                               'IPC.04', 'GSR', 220),
-- ── ENVIRONMENT AND FACILITY SAFETY (GSR.23 – GSR.28) ────────────────────
('GSR.23', 'GSR', 23, 'ENVIRONMENT AND FACILITY SAFETY', 'سلامة البيئة والمنشأة', 'Fire and smoke safety',                        'سلامة الحريق والدخان',                       'EFS.03', 'GSR', 230),
('GSR.24', 'GSR', 24, 'ENVIRONMENT AND FACILITY SAFETY', 'سلامة البيئة والمنشأة', 'Fire drills',                                  'تدريبات إخلاء الحريق',                       'EFS.04', 'GSR', 240),
('GSR.25', 'GSR', 25, 'ENVIRONMENT AND FACILITY SAFETY', 'سلامة البيئة والمنشأة', 'Hazardous materials safety',                   'سلامة المواد الخطرة',                        'EFS.06', 'GSR', 250),
('GSR.26', 'GSR', 26, 'ENVIRONMENT AND FACILITY SAFETY', 'سلامة البيئة والمنشأة', 'Safety Management Plan',                       'خطة إدارة السلامة',                          'EFS.07', 'GSR', 260),
('GSR.27', 'GSR', 27, 'ENVIRONMENT AND FACILITY SAFETY', 'سلامة البيئة والمنشأة', 'Medical Equipment Plan',                       'خطة المعدات الطبية',                         'EFS.10', 'GSR', 270),
('GSR.28', 'GSR', 28, 'ENVIRONMENT AND FACILITY SAFETY', 'سلامة البيئة والمنشأة', 'Utilities Management Plan',                    'خطة إدارة المرافق',                          'EFS.11', 'GSR', 280),
-- ── INFORMATION MANAGEMENT AND TECHNOLOGY (GSR.29) ───────────────────────
('GSR.29', 'GSR', 29, 'INFORMATION MANAGEMENT AND TECHNOLOGY', 'إدارة المعلومات والتكنولوجيا', 'Abbreviations',                  'الاختصارات',                                  'IMT.04', 'GSR', 290)
ON CONFLICT (standard_code) DO NOTHING;

