const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const bcrypt = require('bcryptjs');

const isProduction = process.env.NODE_ENV === 'production';
const databaseUrl = process.env.DATABASE_URL;

if (isProduction && !databaseUrl) {
  console.error('❌ FATAL: DATABASE_URL is required in production mode. Refusing silent fallback to memoryDb.');
  process.exit(1);
}

let pool = null;
let isPgConnected = false;

if (databaseUrl) {
  pool = new Pool({
    connectionString: databaseUrl,
    ssl: isProduction ? { rejectUnauthorized: false } : (databaseUrl.includes('supabase') ? { rejectUnauthorized: false } : false),
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });

  pool.on('connect', () => {
    if (!isPgConnected) {
      console.log('✅ Connected to PostgreSQL / Supabase Database.');
      isPgConnected = true;
      initSchema();
    }
  });

  pool.on('error', (err) => {
    console.error('⚠️ PostgreSQL pool connection error:', err.message);
    isPgConnected = false;
    if (isProduction) {
      console.error('❌ FATAL: Lost connection to production database. Exiting.');
      process.exit(1);
    }
  });
} else {
  console.warn('⚠️ Development Mode: No DATABASE_URL provided. Using in-memory database store (memoryDb).');
}

async function initSchema() {
  try {
    const schemaPath = path.join(__dirname, 'schema.sql');
    if (fs.existsSync(schemaPath)) {
      const sql = fs.readFileSync(schemaPath, 'utf8');
      await pool.query(sql);
      console.log('✅ Database schema verified / migrated successfully.');
    }
  } catch (err) {
    console.warn('ℹ️ Notice during schema initialization:', err.message);
  }
}

// In-memory persistent database store (explicit development/test fallback)
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
      email: process.env.SUPER_ADMIN_EMAIL || "superadmin@gahar.gov.eg",
      password_hash: bcrypt.hashSync(process.env.SUPER_ADMIN_PASSWORD || "SuperAdmin@2026!", 10),
      full_name: "GAHAR Super Admin",
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
      password_hash: bcrypt.hashSync("Hospital@2026", 10),
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
    },
    {
      id: "plan_lab",
      name: "Specialized Center / Lab",
      price_egp: 25000,
      billing_period: "annual",
      facility_limit: 1,
      user_limit: 10,
      features: ["Lab & Radiology GAHAR Modules", "AI Copilot", "Evidence Management"],
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
  audit_logs: [],
  password_resets: [],
  consultation_requests: [],
  trash: [], // Soft-deleted items (Recycle Bin)
  sat_scores: [],
  // SAT standards — all 29 GSR items from Hospital Full Accreditation SAT 2025 Excel
  sat_standards: [
    {id:'s01',standard_code:'GSR.01',chapter_code:'GSR',item_number:1,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Patient identification',standard_title_ar:'تعريف هوية المريض',book_reference_code:'ACT.03',workbook_sheet:'GSR',is_active:true,sort_order:10},
    {id:'s02',standard_code:'GSR.02',chapter_code:'GSR',item_number:2,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Verbal and telephone orders',standard_title_ar:'الأوامر الشفهية والهاتفية',book_reference_code:'ICD.18',workbook_sheet:'GSR',is_active:true,sort_order:20},
    {id:'s03',standard_code:'GSR.03',chapter_code:'GSR',item_number:3,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Critical Results',standard_title_ar:'النتائج الحرجة',book_reference_code:'ICD.19',workbook_sheet:'GSR',is_active:true,sort_order:30},
    {id:'s04',standard_code:'GSR.04',chapter_code:'GSR',item_number:4,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Handover Communication',standard_title_ar:'التواصل عند التسليم',book_reference_code:'ACT.08',workbook_sheet:'GSR',is_active:true,sort_order:40},
    {id:'s05',standard_code:'GSR.05',chapter_code:'GSR',item_number:5,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Fall screening and prevention',standard_title_ar:'الفحص والوقاية من السقوط',book_reference_code:'ICD.10',workbook_sheet:'GSR',is_active:true,sort_order:50},
    {id:'s06',standard_code:'GSR.06',chapter_code:'GSR',item_number:6,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Pressure Ulcer Prevention',standard_title_ar:'الوقاية من قرح الضغط',book_reference_code:'ICD.11',workbook_sheet:'GSR',is_active:true,sort_order:60},
    {id:'s07',standard_code:'GSR.07',chapter_code:'GSR',item_number:7,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Venous Thromboembolism Prophylaxis',standard_title_ar:'الوقاية من تجلط الأوردة',book_reference_code:'ICD.12',workbook_sheet:'GSR',is_active:true,sort_order:70},
    {id:'s08',standard_code:'GSR.08',chapter_code:'GSR',item_number:8,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Critical Alarms',standard_title_ar:'التنبيهات الحرجة',book_reference_code:'CSS.02',workbook_sheet:'GSR',is_active:true,sort_order:80},
    {id:'s09',standard_code:'GSR.09',chapter_code:'GSR',item_number:9,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Catheter and tube misconnections',standard_title_ar:'الأخطاء في توصيل القسطرات والأنابيب',book_reference_code:'CSS.03',workbook_sheet:'GSR',is_active:true,sort_order:90},
    {id:'s10',standard_code:'GSR.10',chapter_code:'GSR',item_number:10,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Recognition and response to clinical deterioration',standard_title_ar:'التعرف على التدهور السريري والاستجابة له',book_reference_code:'ICD.22',workbook_sheet:'GSR',is_active:true,sort_order:100},
    {id:'s11',standard_code:'GSR.11',chapter_code:'GSR',item_number:11,category:'GENERAL PATIENT SAFETY',category_ar:'سلامة المريض العامة',standard_title:'Cardiopulmonary resuscitation',standard_title_ar:'الإنعاش القلبي الرئوي',book_reference_code:'CSS.05',workbook_sheet:'GSR',is_active:true,sort_order:110},
    {id:'s12',standard_code:'GSR.12',chapter_code:'GSR',item_number:12,category:'DIAGNOSTIC AND ANCILLARY SERVICES',category_ar:'الخدمات التشخيصية والمساندة',standard_title:'Radiation Safety Program',standard_title_ar:'برنامج سلامة الإشعاع',book_reference_code:'DAS.09',workbook_sheet:'GSR',is_active:true,sort_order:120},
    {id:'s13',standard_code:'GSR.13',chapter_code:'GSR',item_number:13,category:'DIAGNOSTIC AND ANCILLARY SERVICES',category_ar:'الخدمات التشخيصية والمساندة',standard_title:'Laboratory Safety Program',standard_title_ar:'برنامج سلامة المختبر',book_reference_code:'DAS.23',workbook_sheet:'GSR',is_active:true,sort_order:130},
    {id:'s14',standard_code:'GSR.14',chapter_code:'GSR',item_number:14,category:'SURGICAL AND INVASIVE PROCEDURAL SAFETY',category_ar:'سلامة الجراحة والإجراءات الباضعة',standard_title:'Surgical Site Marking',standard_title_ar:'تحديد موقع العملية الجراحية',book_reference_code:'SAS.05',workbook_sheet:'GSR',is_active:true,sort_order:140},
    {id:'s15',standard_code:'GSR.15',chapter_code:'GSR',item_number:15,category:'SURGICAL AND INVASIVE PROCEDURAL SAFETY',category_ar:'سلامة الجراحة والإجراءات الباضعة',standard_title:'Pre-operative Checklist',standard_title_ar:'قائمة تحقق ما قبل الجراحة',book_reference_code:'SAS.06',workbook_sheet:'GSR',is_active:true,sort_order:150},
    {id:'s16',standard_code:'GSR.16',chapter_code:'GSR',item_number:16,category:'SURGICAL AND INVASIVE PROCEDURAL SAFETY',category_ar:'سلامة الجراحة والإجراءات الباضعة',standard_title:'Time-out / sing out',standard_title_ar:'مهلة التوقف / الخروج الغنائي',book_reference_code:'SAS.07',workbook_sheet:'GSR',is_active:true,sort_order:160},
    {id:'s17',standard_code:'GSR.17',chapter_code:'GSR',item_number:17,category:'SURGICAL AND INVASIVE PROCEDURAL SAFETY',category_ar:'سلامة الجراحة والإجراءات الباضعة',standard_title:'Instrument Retention Prevention',standard_title_ar:'منع احتجاز الأدوات الجراحية',book_reference_code:'SAS.09',workbook_sheet:'GSR',is_active:true,sort_order:170},
    {id:'s18',standard_code:'GSR.18',chapter_code:'GSR',item_number:18,category:'MEDICATION MANAGEMENT AND SAFETY',category_ar:'إدارة الأدوية وسلامتها',standard_title:'Medication Reconciliation, best possible medication history (BPMH)',standard_title_ar:'مطابقة الأدوية وأفضل تاريخ دوائي ممكن',book_reference_code:'MMS.10',workbook_sheet:'GSR',is_active:true,sort_order:180},
    {id:'s19',standard_code:'GSR.19',chapter_code:'GSR',item_number:19,category:'MEDICATION MANAGEMENT AND SAFETY',category_ar:'إدارة الأدوية وسلامتها',standard_title:'Medication storage and labelling',standard_title_ar:'تخزين الأدوية ووضع الملصقات',book_reference_code:'MMS.04',workbook_sheet:'GSR',is_active:true,sort_order:190},
    {id:'s20',standard_code:'GSR.20',chapter_code:'GSR',item_number:20,category:'MEDICATION MANAGEMENT AND SAFETY',category_ar:'إدارة الأدوية وسلامتها',standard_title:'High-alert medications and concentrated electrolytes',standard_title_ar:'الأدوية عالية التنبيه والمحاليل الكهربائية المركزة',book_reference_code:'MMS.06',workbook_sheet:'GSR',is_active:true,sort_order:200},
    {id:'s21',standard_code:'GSR.21',chapter_code:'GSR',item_number:21,category:'MEDICATION MANAGEMENT AND SAFETY',category_ar:'إدارة الأدوية وسلامتها',standard_title:'Look-alike and Sound-like medications.',standard_title_ar:'الأدوية المتشابهة في الشكل والصوت',book_reference_code:'MMS.07',workbook_sheet:'GSR',is_active:true,sort_order:210},
    {id:'s22',standard_code:'GSR.22',chapter_code:'GSR',item_number:22,category:'INFECTION PREVENTION AND CONTROL',category_ar:'الوقاية من العدوى ومكافحتها',standard_title:'Hand Hygiene',standard_title_ar:'نظافة الأيدي',book_reference_code:'IPC.04',workbook_sheet:'GSR',is_active:true,sort_order:220},
    {id:'s23',standard_code:'GSR.23',chapter_code:'GSR',item_number:23,category:'ENVIRONMENT AND FACILITY SAFETY',category_ar:'سلامة البيئة والمنشأة',standard_title:'Fire and smoke safety',standard_title_ar:'سلامة الحريق والدخان',book_reference_code:'EFS.03',workbook_sheet:'GSR',is_active:true,sort_order:230},
    {id:'s24',standard_code:'GSR.24',chapter_code:'GSR',item_number:24,category:'ENVIRONMENT AND FACILITY SAFETY',category_ar:'سلامة البيئة والمنشأة',standard_title:'Fire drills',standard_title_ar:'تدريبات إخلاء الحريق',book_reference_code:'EFS.04',workbook_sheet:'GSR',is_active:true,sort_order:240},
    {id:'s25',standard_code:'GSR.25',chapter_code:'GSR',item_number:25,category:'ENVIRONMENT AND FACILITY SAFETY',category_ar:'سلامة البيئة والمنشأة',standard_title:'Hazardous materials safety',standard_title_ar:'سلامة المواد الخطرة',book_reference_code:'EFS.06',workbook_sheet:'GSR',is_active:true,sort_order:250},
    {id:'s26',standard_code:'GSR.26',chapter_code:'GSR',item_number:26,category:'ENVIRONMENT AND FACILITY SAFETY',category_ar:'سلامة البيئة والمنشأة',standard_title:'Safety Management Plan',standard_title_ar:'خطة إدارة السلامة',book_reference_code:'EFS.07',workbook_sheet:'GSR',is_active:true,sort_order:260},
    {id:'s27',standard_code:'GSR.27',chapter_code:'GSR',item_number:27,category:'ENVIRONMENT AND FACILITY SAFETY',category_ar:'سلامة البيئة والمنشأة',standard_title:'Medical Equipment Plan',standard_title_ar:'خطة المعدات الطبية',book_reference_code:'EFS.10',workbook_sheet:'GSR',is_active:true,sort_order:270},
    {id:'s28',standard_code:'GSR.28',chapter_code:'GSR',item_number:28,category:'ENVIRONMENT AND FACILITY SAFETY',category_ar:'سلامة البيئة والمنشأة',standard_title:'Utilities Management Plan',standard_title_ar:'خطة إدارة المرافق',book_reference_code:'EFS.11',workbook_sheet:'GSR',is_active:true,sort_order:280},
    {id:'s29',standard_code:'GSR.29',chapter_code:'GSR',item_number:29,category:'INFORMATION MANAGEMENT AND TECHNOLOGY',category_ar:'إدارة المعلومات والتكنولوجيا',standard_title:'Abbreviations',standard_title_ar:'الاختصارات',book_reference_code:'IMT.04',workbook_sheet:'GSR',is_active:true,sort_order:290}
  ]
};

// Unified Database Query Wrapper
async function query(text, params = []) {
  if (pool && isPgConnected) {
    try {
      return await pool.query(text, params);
    } catch (err) {
      if (isProduction) {
        console.error('❌ Database Query Error in Production:', err.message);
        throw err;
      }
      console.warn('⚠️ Database query error:', err.message);
    }
  }
  return null;
}

module.exports = {
  pool,
  query,
  memoryDb,
  get isPgConnected() {
    return isPgConnected;
  },
  isProduction
};

