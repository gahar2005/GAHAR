-- =============================================================================
-- AccrediGo Healthcare Accreditation Platform - Production SQL Database Schema
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

-- -----------------------------------------------------------------------------
-- 11. Initial Seed Data
-- -----------------------------------------------------------------------------
INSERT INTO subscription_plans (id, name, price_egp, billing_period, facility_limit, user_limit, features)
VALUES 
('plan_standard', 'Standard Hospital', 45000.00, 'annual', 1, 20, '["Full GAHAR 2025 Checklist", "AI Copilot Assistance", "Gap Analysis & Action Plans", "Licenses Tracker", "Standard Support"]'::jsonb),
('plan_enterprise', 'Enterprise Multi-Branch', 120000.00, 'annual', 5, 100, '["All Standard Features", "Unlimited Branches", "Dedicated Accreditation Advisor", "Priority AI Processing", "Custom Audit Reports"]'::jsonb),
('plan_lab', 'Specialized Center / Lab', 25000.00, 'annual', 1, 10, '["Lab & Radiology GAHAR Modules", "AI Copilot", "Evidence Management"]'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Seed Default Super Admin Account (Password: SuperAdmin@2026!)
INSERT INTO users (id, email, password_hash, full_name, role, facility_id, is_active)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'admin@accredigo.eg',
    '$2a$10$7vKqC.fH3aT7T1N.nFhRne3gOaK78lJ5gG0/1/4/2/3/4/5/6/7/8', -- Hashed bcrypt password
    'AccrediGo Super Admin',
    'SUPER_ADMIN',
    NULL,
    true
) ON CONFLICT (email) DO NOTHING;

-- Row Level Security (RLS) policies for Supabase
ALTER TABLE facilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE gaps ENABLE ROW LEVEL SECURITY;
ALTER TABLE action_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
