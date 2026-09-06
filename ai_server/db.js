const { Pool } = require('pg');
const { v4: uuidv4 } = require('uuid');

// PostgreSQL Pool setup
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/accredigo',
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

let isPgConnected = false;

pool.on('connect', () => {
  if (!isPgConnected) {
    console.log('✅ Connected to PostgreSQL Database pool.');
    isPgConnected = true;
  }
});

pool.on('error', (err) => {
  if (isPgConnected) {
    console.warn('⚠️ PostgreSQL pool connection warning:', err.message);
  }
  isPgConnected = false;
});

// Fallback in-memory persistent database store (used if PostgreSQL connection is absent)
const memoryDb = {
  facilities: [
    {
      id: "fac_01000000-0000-0000-0000-000000000001",
      name: "Cairo International Medical Center",
      type: "Hospital (300 Beds)",
      governorate: "Cairo",
      address: "125 El Tahrir St, Cairo",
      bed_capacity: 300,
      contact_person: "Dr. Ahmed Hassan",
      work_email: "admin@cairohospital.eg",
      phone: "+201001234567",
      gahar_version: "GAHAR 2025 v2",
      status: "APPROVED",
      subscription_plan_id: "plan_enterprise",
      created_at: new Date("2025-01-15").toISOString()
    },
    {
      id: "fac_02000000-0000-0000-0000-000000000002",
      name: "Alexandria Specialized Children Hospital",
      type: "Specialized Hospital (120 Beds)",
      governorate: "Alexandria",
      address: "45 Fouad St, Alexandria",
      bed_capacity: 120,
      contact_person: "Dr. Mona El Sayed",
      work_email: "contact@alexchildren.eg",
      phone: "+201009876543",
      gahar_version: "GAHAR 2025 v2",
      status: "PENDING_REVIEW",
      subscription_plan_id: "plan_standard",
      created_at: new Date("2025-03-02").toISOString()
    }
  ],
  users: [
    {
      id: "usr_superadmin_0001",
      email: "admin@accredigo.eg",
      password_hash: "$2a$10$e8w.p4uF7/A/1N8F3z8H.e9P2a3b4c5d6e7f8g9h0i1j2k3l4m5n6", // SuperAdmin@2026!
      full_name: "AccrediGo Platform Super Admin",
      role: "SUPER_ADMIN",
      facility_id: null,
      department: "Executive",
      phone: "+201000000000",
      is_active: true,
      created_at: new Date().toISOString()
    },
    {
      id: "usr_facility_0001",
      email: "admin@cairohospital.eg",
      password_hash: "$2a$10$e8w.p4uF7/A/1N8F3z8H.e9P2a3b4c5d6e7f8g9h0i1j2k3l4m5n6",
      full_name: "Dr. Ahmed Hassan",
      role: "FACILITY_ADMIN",
      facility_id: "fac_01000000-0000-0000-0000-000000000001",
      department: "Quality",
      phone: "+201001234567",
      is_active: true,
      created_at: new Date().toISOString()
    }
  ],
  subscription_plans: [
    {
      id: "plan_standard",
      name: "Standard Hospital",
      price_egp: 45000,
      billing_period: "annual",
      facility_limit: 1,
      user_limit: 20,
      features: ["Full GAHAR 2025 Checklist", "AI Copilot Assistance", "Gap Analysis & Action Plans", "Licenses Tracker"],
      is_active: true
    },
    {
      id: "plan_enterprise",
      name: "Enterprise Multi-Branch",
      price_egp: 120000,
      billing_period: "annual",
      facility_limit: 5,
      user_limit: 100,
      features: ["All Standard Features", "Unlimited Branches", "Dedicated Accreditation Advisor", "Priority AI Processing"],
      is_active: true
    }
  ],
  payments: [
    {
      id: "pay_01",
      facility_id: "fac_01000000-0000-0000-0000-000000000001",
      plan_id: "plan_enterprise",
      amount: 120000,
      payment_method: "Bank Transfer",
      status: "VERIFIED",
      transaction_ref: "CIB-89320194",
      created_at: new Date("2025-01-15").toISOString()
    }
  ],
  gaps: [],
  action_plans: [],
  licenses: [],
  documents: [],
  audit_logs: []
};

// Database Query Wrapper
async function query(text, params = []) {
  try {
    const res = await pool.query(text, params);
    return res;
  } catch (err) {
    // If PostgreSQL pool fails/disconnected, log warning and use fallback store
    if (process.env.DEBUG_DB) {
      console.warn("ℹ️ Database query fallback executed:", err.message);
    }
    return null;
  }
}

module.exports = {
  pool,
  query,
  memoryDb
};
