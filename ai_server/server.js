const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcryptjs");
const { v4: uuidv4 } = require("uuid");
require("dotenv").config();

const db = require("./db");
const { pool, query, withTransaction, memoryDb, ensureSuperAdminProvisioned, initializeDatabase, isProduction } = db;

// Safe wrapper for database connectivity check (backward & forward compatible)
const isDbConnected = typeof db.isDbConnected === "function"
  ? db.isDbConnected
  : (typeof db.getIsPgConnected === "function"
      ? db.getIsPgConnected
      : () => Boolean(db.isPgConnected));

const getIsPgConnected = isDbConnected;

function checkPg() {
  return isDbConnected();
}
const { 
  verifySmtpConnection,
  sendRegistrationWelcomeEmail,
  sendFacilityRegistrationNotification, 
  sendSubscriptionActivatedNotification,
  sendFacilityStatusNotification,
  sendPasswordResetNotification,
  sendPaymentVerificationNotification,
  sendEmail
} = require("./email_service");
const { logAuditEvent } = require("./audit_service");
const {
  uploadDocument,
  getDocumentBuffer,
  getSignedDownloadUrl,
  deleteDocumentFile,
  validateFile,
  MAX_FILE_SIZE_BYTES,
  ALLOWED_MIME_TYPES
} = require("./storage_service");

const {
  getApplicabilityQuestions,
  getFacilityApplicability,
  saveFacilityApplicability,
  getExcludedStandardsSet,
} = require("./applicability_service");

const {
  GAHAR_DOC_CATALOG,
  getCatalogWithApplicability,
  getFacilityDocuments,
  generateDocumentDraft,
  saveDocumentVersion,
  updateDocumentApprovalStatus,
  getDocumentVersions,
  getDocumentDashboard,
} = require("./document_service");

const {
  createMockSurveyRequest,
  getMockSurveysForFacility,
  getMonitoringSummary,
  getFacilityRoiAnalytics,
} = require("./monitoring_roi_service");

const {
  generateCopilotReply,
  getProviderStatus,
} = require("./ai_service");

const app = express();
app.use(helmet({
  crossOriginResourcePolicy: { policy: "cross-origin" },
}));

// Configurable CORS for production security
const allowedOrigins = process.env.ALLOWED_ORIGINS 
  ? process.env.ALLOWED_ORIGINS.split(',').map(s => s.trim()) 
  : null;

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || !isProduction || !allowedOrigins) {
      return callback(null, true);
    }
    if (allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    return callback(new Error("CORS policy violation: Origin not allowed"), false);
  },
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization", "X-Facility-Id"],
  credentials: true,
}));
app.use(express.json({ limit: "20mb" }));

// In-memory sliding-window rate limiters for sensitive endpoints
function createRateLimiter({ windowMs, maxRequests, message }) {
  const hits = new Map();
  const cleanupInterval = setInterval(() => {
    const now = Date.now();
    for (const [key, timestamps] of hits.entries()) {
      const valid = timestamps.filter(t => now - t < windowMs);
      if (valid.length === 0) hits.delete(key);
      else hits.set(key, valid);
    }
  }, Math.min(windowMs, 60000));
  if (cleanupInterval.unref) cleanupInterval.unref();

  return (req, res, next) => {
    const key = req.ip || req.connection?.remoteAddress || 'unknown';
    const now = Date.now();
    const timestamps = hits.get(key) || [];
    const valid = timestamps.filter(t => now - t < windowMs);
    if (valid.length >= maxRequests) {
      return res.status(429).json({
        success: false,
        code: "RATE_LIMIT_EXCEEDED",
        message: message || "Too many requests. Please try again later."
      });
    }
    valid.push(now);
    hits.set(key, valid);
    next();
  };
}

const authLimiter = createRateLimiter({ windowMs: 15 * 60 * 1000, maxRequests: 25, message: "Too many login attempts. Please try again after 15 minutes." });
const registerLimiter = createRateLimiter({ windowMs: 60 * 60 * 1000, maxRequests: 15, message: "Too many registration attempts. Please try again after one hour." });
const passwordResetLimiter = createRateLimiter({ windowMs: 60 * 60 * 1000, maxRequests: 10, message: "Too many password reset attempts. Please try again later." });
const copilotLimiter = createRateLimiter({ windowMs: 60 * 1000, maxRequests: 60, message: "AI Copilot request limit reached. Please wait a moment." });

// =============================================================================
// Health & Readiness Probes
// =============================================================================

// Root route — confirms the API is online
app.get("/", (req, res) => {
  res.status(200).json({
    status: "online",
    service: "GAHAR Healthcare Accreditation Platform API",
    version: "1.0.0",
    timestamp: new Date().toISOString(),
    endpoints: {
      health: "/health",
      readiness: "/readiness",
      api: "/api/*",
    },
  });
});


// Liveness probe (checks if HTTP process is alive)
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "ok",
    timestamp: new Date().toISOString(),
    service: "GAHAR Accreditation Platform API",
    database: isDbConnected() ? "connected" : "in-memory-fallback",
    ai: getProviderStatus(),
  });
});

// Readiness probe (verifies database readiness before traffic routing)
app.get("/readiness", (req, res) => {
  const dbConnected = isDbConnected();
  if (isProduction && !dbConnected) {
    return res.status(503).json({
      ready: false,
      timestamp: new Date().toISOString(),
      service: "GAHAR Accreditation Platform API",
      database: "disconnected",
      message: "Database connection unavailable in production."
    });
  }
  return res.status(200).json({
    ready: true,
    timestamp: new Date().toISOString(),
    service: "GAHAR Accreditation Platform API",
    database: dbConnected ? "connected" : "in-memory-fallback",
  });
});

// Production secret validation: fail safely at startup if required secrets are missing
if (isProduction) {
  if (!process.env.JWT_SECRET) {
    console.error("❌ FATAL: JWT_SECRET environment variable is required in production mode.");
    process.exit(1);
  }
  if (!process.env.SUPER_ADMIN_PASSWORD) {
    console.error("❌ FATAL: SUPER_ADMIN_PASSWORD environment variable is required in production mode.");
    process.exit(1);
  }
}

const JWT_SECRET = process.env.JWT_SECRET || (isProduction ? null : "GAHAR_dev_jwt_secret_key_2026_fallback");
const SUPER_ADMIN_EMAIL = process.env.SUPER_ADMIN_EMAIL || "admin@gahar-platform.eg";

// =============================================================================
// Security & Authentication Middlewares
// =============================================================================

function authenticateToken(req, res, next) {
  const authHeader = req.headers["authorization"];
  const token = authHeader && authHeader.split(" ")[1];

  if (!token) {
    return res.status(401).json({ success: false, code: "UNAUTHORIZED", message: "Authentication token required." });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(401).json({ success: false, code: "UNAUTHORIZED", message: "Invalid or expired session token." });
    }
    req.user = user; // { userId, email, role, facilityId }
    next();
  });
}

function authorizeRoles(...allowedRoles) {
  return (req, res, next) => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      logAuditEvent({ 
        facilityId: req.user?.facilityId, 
        userId: req.user?.userId, 
        userEmail: req.user?.email, 
        action: "UNAUTHORIZED_ROLE_ACCESS", 
        details: { attemptedRole: req.user?.role, requiredRoles: allowedRoles }, 
        req 
      });
      return res.status(403).json({ success: false, message: "Forbidden. Insufficient administrative permissions." });
    }
    next();
  };
}

function enforceTenantIsolation(req, res, next) {
  if (req.user.role === "SUPER_ADMIN") {
    req.tenantFacilityId = req.user.facilityId;
    return next();
  }

  const clientHeaderFacilityId = req.headers["x-facility-id"];

  // CRITICAL: Always derive tenant identity strictly from JWT — never from headers
  // If the X-Facility-Id header is present and does NOT match the JWT facility, reject immediately
  if (clientHeaderFacilityId && clientHeaderFacilityId !== req.user.facilityId) {
    logAuditEvent({
      facilityId: req.user.facilityId,
      userId: req.user.userId,
      userEmail: req.user.email,
      action: "SUSPICIOUS_CROSS_TENANT_ATTEMPT",
      details: { attemptedFacilityId: clientHeaderFacilityId, jwtFacilityId: req.user.facilityId },
      req
    });
    return res.status(403).json({
      success: false,
      message: "Security Violation: Tenant identity is derived strictly from your authentication token."
    });
  }

  // Always use JWT facilityId — X-Facility-Id header is ignored for scoping
  req.tenantFacilityId = req.user.facilityId;
  next();
}

// =============================================================================
// Auth & Account Endpoints
// =============================================================================

// 1. Super Admin Authentication
app.post("/api/auth/super-admin/login", authLimiter, async (req, res) => {
  const { email, password } = req.body || {};
  console.log(`🔑 Super Admin Login Attempt: ${email}`);

  if (!email || !password) {
    return res.status(400).json({ success: false, message: "Email and password are required." });
  }

  const normalizedEmail = email.trim().toLowerCase();
  const allowedSuperAdminEmails = Array.from(new Set([
    SUPER_ADMIN_EMAIL.toLowerCase(),
    "superadmin@gahar.gov.eg",
    "admin@gahar-platform.eg",
    "admin@accredigo.eg"
  ])).filter(Boolean);

  let adminUser = null;

  // 1. Check PostgreSQL if connected
  if (checkPg()) {
    try {
      const dbRes = await query(
        "SELECT * FROM users WHERE role = 'SUPER_ADMIN' AND LOWER(email) = $1 LIMIT 1",
        [normalizedEmail]
      );
      if (dbRes && dbRes.rows.length > 0) {
        adminUser = dbRes.rows[0];
      }
    } catch (err) {
      console.warn("Notice querying Super Admin in DB:", err.message);
    }
  }

  // 2. Check memoryDb fallback (non-production only)
  if (!adminUser && !isProduction) {
    adminUser = memoryDb.users.find(u => u.role === 'SUPER_ADMIN' && u.email.toLowerCase() === normalizedEmail);
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Authentication service temporarily unavailable in production." });
  }

  let isValidPassword = false;

  if (adminUser) {
    isValidPassword = bcrypt.compareSync(password, adminUser.password_hash);
  } else if (!isProduction && allowedSuperAdminEmails.includes(normalizedEmail)) {
    // If user not yet seeded in development, check against environment variable
    const expectedPassword = process.env.SUPER_ADMIN_PASSWORD || "SuperAdmin@2026!";
    isValidPassword = password === expectedPassword;
  }

  if (isValidPassword) {
    const adminId = adminUser ? adminUser.id : "00000000-0000-0000-0000-000000000001";
    const token = jwt.sign(
      { 
        userId: adminId, 
        email: normalizedEmail, 
        role: "SUPER_ADMIN", 
        facilityId: null 
      },
      JWT_SECRET,
      { expiresIn: "24h" }
    );

    logAuditEvent({ userEmail: normalizedEmail, action: "SUPER_ADMIN_LOGIN", req });

    return res.json({
      success: true,
      token,
      user: {
        id: adminId,
        email: normalizedEmail,
        fullName: adminUser?.full_name || "GAHAR Super Admin",
        role: "SUPER_ADMIN",
        facilityId: null,
      }
    });
  }

  logAuditEvent({ userEmail: normalizedEmail, action: "SUPER_ADMIN_LOGIN_FAILED", req });
  return res.status(401).json({ success: false, message: "Invalid Super Admin credentials." });
});

// 2. Facility User Login
app.post("/api/auth/login", authLimiter, async (req, res) => {
  const { email, password } = req.body || {};
  console.log(`🔐 Facility Login Attempt: ${email}`);

  if (!email || !password) {
    return res.status(400).json({ success: false, message: "Email and password are required." });
  }

  const normalizedEmail = email.trim().toLowerCase();

  let user = null;
  let facility = null;

  // 1. Query PostgreSQL if connected
  if (checkPg()) {
    try {
      const userRes = await query("SELECT * FROM users WHERE LOWER(email) = $1 LIMIT 1", [normalizedEmail]);
      if (userRes && userRes.rows.length > 0) {
        user = userRes.rows[0];
        if (user.facility_id) {
          const facRes = await query("SELECT * FROM facilities WHERE id = $1 LIMIT 1", [user.facility_id]);
          if (facRes && facRes.rows.length > 0) {
            facility = facRes.rows[0];
          }
        }
      }
    } catch (err) {
      console.warn("Notice querying user in DB:", err.message);
    }
  }

  // 2. Fallback to memoryDb (development only)
  if (!user && !isProduction) {
    user = memoryDb.users.find(u => u.email.toLowerCase() === normalizedEmail);
    if (user && user.facility_id) {
      facility = memoryDb.facilities.find(f => f.id === user.facility_id) || memoryDb.facilities[0];
    }
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Authentication service temporarily unavailable in production." });
  }

  // If user is Super Admin, redirect them to Super Admin portal
  if (user && user.role === 'SUPER_ADMIN') {
    return res.status(400).json({ success: false, message: "Please use Super Admin Portal login." });
  }

  if (!user) {
    logAuditEvent({ userEmail: normalizedEmail, action: "USER_LOGIN_FAILED_NOT_FOUND", req });
    return res.status(401).json({ success: false, message: "Invalid email or password. Please verify your credentials or register your facility." });
  }

  if (!user.is_active) {
    logAuditEvent({ facilityId: user.facility_id, userId: user.id, userEmail: user.email, action: "USER_LOGIN_FAILED_DEACTIVATED", req });
    return res.status(403).json({ success: false, message: "User account is deactivated. Contact your Facility Administrator." });
  }

  const isPasswordValid = bcrypt.compareSync(password, user.password_hash);
  if (!isPasswordValid) {
    logAuditEvent({ facilityId: user.facility_id, userId: user.id, userEmail: user.email, action: "USER_LOGIN_FAILED_INVALID_PASSWORD", req });
    return res.status(401).json({ success: false, message: "Invalid email or password." });
  }

  const facilityId = user.facility_id || facility?.id;
  const token = jwt.sign(
    { 
      userId: user.id, 
      email: user.email, 
      role: user.role, 
      facilityId 
    },
    JWT_SECRET,
    { expiresIn: "24h" }
  );

  logAuditEvent({ facilityId, userId: user.id, userEmail: user.email, action: "USER_LOGIN_SUCCESS", req });

  res.json({
    success: true,
    token,
    user: {
      id: user.id,
      email: user.email,
      fullName: user.full_name,
      role: user.role,
      facilityId,
    },
    facility: facility ? {
      id: facility.id,
      name: facility.name,
      status: facility.status,
      subscriptionPlan: facility.subscription_plan_id,
    } : null
  });
});

// 3. Facility Registration (Production Safe: Persisted to DB + memoryDb, non-blocking emails)
app.post("/api/auth/register-facility", registerLimiter, async (req, res) => {
  const {
    facilityName,
    facilityType,
    governorate,
    bedCapacity,
    address,
    contactPerson,
    workEmail,
    phone,
    password,
    subscriptionPlanId,
    paymentMethod,
    paymentReference
  } = req.body || {};

  if (!facilityName || !workEmail || !contactPerson) {
    return res.status(400).json({ success: false, message: "Facility name, work email, and contact person are required." });
  }

  // Reject missing or weak passwords - NEVER silently substitute default passwords
  if (!password || typeof password !== 'string' || password.length < 8) {
    return res.status(400).json({ success: false, message: "A secure password of at least 8 characters is required." });
  }

  const normalizedEmail = workEmail.trim().toLowerCase();
  console.log(`🏥 New Facility Onboarding Request: ${facilityName} (${normalizedEmail})`);

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Registration service unavailable without persistent database." });
  }

  // Derive plan price from server-side database records
  const selectedPlanId = subscriptionPlanId || "plan_standard";
  let planPrice = 45000;
  if (checkPg()) {
    try {
      const pRes = await query("SELECT price_egp FROM subscription_plans WHERE id = $1", [selectedPlanId]);
      if (pRes && pRes.rows.length > 0) planPrice = Number(pRes.rows[0].price_egp);
    } catch (_) {}
  } else {
    const memPlan = memoryDb.subscription_plans.find(p => p.id === selectedPlanId);
    if (memPlan) planPrice = memPlan.price_egp;
  }

  const facilityId = uuidv4();
  const userId = uuidv4();
  const initialStatus = paymentMethod === "Online Gateway" ? "PENDING_PAYMENT" : "PENDING_REVIEW";
  const passwordHash = bcrypt.hashSync(password, 10);

  const newFacility = {
    id: facilityId,
    name: facilityName,
    type: facilityType || "Hospital",
    governorate: governorate || "Cairo",
    address: address || "",
    bed_capacity: parseInt(bedCapacity || "100", 10),
    contact_person: contactPerson,
    work_email: normalizedEmail,
    phone: phone || "",
    gahar_version: "GAHAR 2025 v2",
    status: initialStatus,
    subscription_plan_id: selectedPlanId,
    created_at: new Date().toISOString()
  };

  const newUser = {
    id: userId,
    email: normalizedEmail,
    password_hash: passwordHash,
    full_name: contactPerson,
    role: "FACILITY_ADMIN",
    facility_id: facilityId,
    is_active: true,
    created_at: new Date().toISOString()
  };

  let newPayment = null;
  if (paymentReference) {
    newPayment = {
      id: uuidv4(),
      facility_id: facilityId,
      plan_id: selectedPlanId,
      amount: planPrice,
      payment_method: paymentMethod || "Bank Transfer",
      status: "PENDING_VERIFICATION",
      transaction_ref: paymentReference,
      created_at: new Date().toISOString()
    };
  }

  // 1. Persist to PostgreSQL if connected using an atomic transaction
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        await client.query(
          `INSERT INTO facilities (id, name, type, governorate, address, bed_capacity, contact_person, work_email, phone, gahar_version, status, subscription_plan_id, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, NOW())`,
          [facilityId, newFacility.name, newFacility.type, newFacility.governorate, newFacility.address, newFacility.bed_capacity, newFacility.contact_person, newFacility.work_email, newFacility.phone, newFacility.gahar_version, newFacility.status, newFacility.subscription_plan_id]
        );

        await client.query(
          `INSERT INTO users (id, email, password_hash, full_name, role, facility_id, is_active, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, true, NOW())`,
          [userId, newUser.email, newUser.password_hash, newUser.full_name, newUser.role, newUser.facility_id]
        );

        if (newPayment) {
          await client.query(
            `INSERT INTO payments (id, facility_id, plan_id, amount, payment_method, status, transaction_ref, created_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())`,
            [newPayment.id, newPayment.facility_id, newPayment.plan_id, newPayment.amount, newPayment.payment_method, newPayment.status, newPayment.transaction_ref]
          );
        }
      });
      console.log(`✅ Facility and Admin user persisted transactionally to PostgreSQL database [${facilityId}].`);
    } catch (dbErr) {
      console.error("❌ Error persisting facility registration transaction to DB:", dbErr.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to persist facility registration in production database." });
      }
    }
  }

  // 2. Add to in-memory store
  memoryDb.facilities.unshift(newFacility);
  memoryDb.users.unshift(newUser);
  if (newPayment) memoryDb.payments.unshift(newPayment);

  // 3. Dispatch automated notification emails asynchronously (non-blocking)
  sendRegistrationWelcomeEmail({
    workEmail: normalizedEmail,
    facilityName,
    contactPerson,
    status: initialStatus,
    subscriptionPlanId: selectedPlanId
  }).catch(e => console.warn("Notice dispatching welcome email:", e.message));

  sendFacilityRegistrationNotification({
    name: facilityName,
    type: facilityType,
    governorate,
    bedCapacity,
    contactPerson,
    workEmail: normalizedEmail,
    phone,
    subscriptionPlanId: selectedPlanId,
    paymentMethod,
    status: initialStatus
  }).catch(e => console.warn("Notice dispatching admin reg email:", e.message));

  logAuditEvent({ facilityId, userId, userEmail: normalizedEmail, action: "FACILITY_REGISTRATION_SUBMITTED", details: { status: initialStatus, paymentMethod }, req });

  const token = jwt.sign(
    { userId, email: normalizedEmail, role: "FACILITY_ADMIN", facilityId },
    JWT_SECRET,
    { expiresIn: "24h" }
  );

  res.status(201).json({
    success: true,
    message: paymentMethod === "Online Gateway" 
      ? "Registration received. Online gateway requires merchant configuration; pending activation."
      : "Facility registration submitted successfully. Super Admin verification in progress.",
    token,
    facility: newFacility,
    user: {
      id: userId,
      email: normalizedEmail,
      fullName: contactPerson,
      role: "FACILITY_ADMIN",
      facilityId
    }
  });
});

// 4. Password Reset - Forgot Password
app.post("/api/auth/forgot-password", passwordResetLimiter, async (req, res) => {
  const { email } = req.body || {};
  if (!email) {
    return res.status(400).json({ success: false, message: "Email is required." });
  }

  const normalizedEmail = email.trim().toLowerCase();
  const rawToken = crypto.randomBytes(32).toString("hex");
  const tokenHash = crypto.createHash("sha256").update(rawToken).digest("hex");
  const expiresAt = new Date(Date.now() + 3600 * 1000); // 1 hour

  const resetRecord = {
    id: uuidv4(),
    email: normalizedEmail,
    token_hash: tokenHash,
    expires_at: expiresAt.toISOString(),
    used: false,
    created_at: new Date().toISOString()
  };

  // Persist to PostgreSQL if connected
  if (checkPg()) {
    try {
      await query(
        `INSERT INTO password_resets (id, email, token_hash, expires_at, used, created_at)
         VALUES ($1, $2, $3, $4, false, NOW())`,
        [resetRecord.id, resetRecord.email, resetRecord.token_hash, resetRecord.expires_at]
      );
    } catch (err) {
      console.warn("Notice persisting password reset to DB:", err.message);
    }
  }

  if (!isProduction) {
    memoryDb.password_resets.push(resetRecord);
  }

  // Send reset email if user exists (checked in DB or memoryDb)
  let userExists = false;
  if (checkPg()) {
    try {
      const uRes = await query("SELECT id FROM users WHERE LOWER(email) = $1 LIMIT 1", [normalizedEmail]);
      if (uRes && uRes.rows.length > 0) userExists = true;
    } catch (_) {}
  }
  if (!userExists && !isProduction) {
    userExists = memoryDb.users.some(u => u.email.toLowerCase() === normalizedEmail);
  }

  if (userExists) {
    sendPasswordResetNotification(normalizedEmail, rawToken)
      .catch(e => console.warn("Notice sending password reset email:", e.message));
    logAuditEvent({ userEmail: normalizedEmail, action: "PASSWORD_RESET_REQUESTED", req });
  }

  // Always return safe generic message to prevent email enumeration
  res.json({
    success: true,
    message: "If an account exists with this email address, a password reset link has been dispatched."
  });
});

// 5. Password Reset - Reset Password
app.post("/api/auth/reset-password", passwordResetLimiter, async (req, res) => {
  const { token, newPassword } = req.body || {};
  if (!token || !newPassword) {
    return res.status(400).json({ success: false, message: "Token and new password are required." });
  }

  if (typeof newPassword !== 'string' || newPassword.length < 8) {
    return res.status(400).json({ success: false, message: "Password must be at least 8 characters long." });
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Password reset service temporarily unavailable." });
  }

  const tokenHash = crypto.createHash("sha256").update(token).digest("hex");
  let record = null;

  // 1. Check PostgreSQL if connected
  if (checkPg()) {
    try {
      const rRes = await query(
        "SELECT * FROM password_resets WHERE token_hash = $1 AND used = false AND expires_at > NOW() LIMIT 1",
        [tokenHash]
      );
      if (rRes && rRes.rows.length > 0) {
        record = rRes.rows[0];
      }
    } catch (err) {
      console.warn("Notice querying password reset from DB:", err.message);
    }
  }

  // 2. Check memoryDb fallback (non-production only)
  if (!record && !isProduction) {
    record = memoryDb.password_resets.find(r => r.token_hash === tokenHash && !r.used && new Date(r.expires_at) >= new Date());
  }

  if (!record) {
    return res.status(400).json({ success: false, message: "Invalid or expired password reset token." });
  }

  const newHash = bcrypt.hashSync(newPassword, 10);

  // Update in PostgreSQL transactionally
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        await client.query("UPDATE users SET password_hash = $1 WHERE LOWER(email) = LOWER($2)", [newHash, record.email]);
        await client.query("UPDATE password_resets SET used = true WHERE id = $1", [record.id]);
      });
    } catch (err) {
      console.error("Error updating password in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to update password in database." });
      }
    }
  }

  // Update in memoryDb
  const memUser = memoryDb.users.find(u => u.email.toLowerCase() === record.email.toLowerCase());
  if (memUser) {
    memUser.password_hash = newHash;
  }
  record.used = true;

  logAuditEvent({ userEmail: record.email, action: "PASSWORD_RESET_COMPLETED", req });

  res.json({
    success: true,
    message: "Your password has been successfully updated. You may now log in with your new password."
  });
});

// 6. Session Refresh Token with Active Status Verification
app.post("/api/auth/refresh-token", authenticateToken, async (req, res) => {
  let isActive = true;
  let currentRole = req.user.role;
  let currentFacilityId = req.user.facilityId;

  if (checkPg()) {
    try {
      const uRes = await query("SELECT id, is_active, role, facility_id FROM users WHERE id = $1 LIMIT 1", [req.user.userId]);
      if (!uRes || uRes.rows.length === 0 || !uRes.rows[0].is_active) {
        isActive = false;
      } else {
        currentRole = uRes.rows[0].role;
        currentFacilityId = uRes.rows[0].facility_id;
      }
    } catch (err) {
      console.warn("Notice checking user active status on token refresh:", err.message);
    }
  } else if (!isProduction) {
    const memUser = memoryDb.users.find(u => u.id === req.user.userId);
    if (!memUser || !memUser.is_active) {
      isActive = false;
    } else {
      currentRole = memUser.role;
      currentFacilityId = memUser.facility_id;
    }
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Token refresh service temporarily unavailable." });
  }

  if (!isActive) {
    logAuditEvent({ facilityId: req.user.facilityId, userId: req.user.userId, userEmail: req.user.email, action: "TOKEN_REFRESH_REJECTED_DEACTIVATED", req });
    return res.status(403).json({ success: false, message: "Account is deactivated or revoked. Please log in again." });
  }

  const refreshedToken = jwt.sign(
    { 
      userId: req.user.userId, 
      email: req.user.email, 
      role: currentRole, 
      facilityId: currentFacilityId 
    },
    JWT_SECRET,
    { expiresIn: "24h" }
  );

  res.json({ success: true, token: refreshedToken });
});

// =============================================================================
// Users Management Module (Tenant-Isolated)
// =============================================================================

// List facility users
app.get("/api/users", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (checkPg()) {
    try {
      const result = await query(
        `SELECT id, email, full_name, role, department, phone, is_active, created_at 
         FROM users 
         WHERE facility_id = $1 
         ORDER BY created_at DESC`,
        [req.tenantFacilityId]
      );
      const mapped = result.rows.map(u => ({
        id: u.id,
        email: u.email,
        fullName: u.full_name,
        role: u.role,
        department: u.department || "General",
        phone: u.phone || "",
        isActive: u.is_active,
        createdAt: u.created_at
      }));
      return res.json({ success: true, users: mapped });
    } catch (err) {
      console.error("Error fetching facility users from DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load facility users." });
      }
    }
  }

  const facilityUsers = memoryDb.users
    .filter(u => u.facility_id === req.tenantFacilityId)
    .map(u => ({
      id: u.id,
      email: u.email,
      fullName: u.full_name,
      role: u.role,
      department: u.department || "General",
      phone: u.phone || "",
      isActive: u.is_active,
      createdAt: u.created_at
    }));

  res.json({ success: true, users: facilityUsers });
});

// Create facility user (Only FACILITY_ADMIN or SUPER_ADMIN)
app.post("/api/users", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  const { email, fullName, role, department, phone, password } = req.body;

  if (!email || !fullName) {
    return res.status(400).json({ success: false, message: "Email and full name are required." });
  }

  const allowedRoles = ["FACILITY_ADMIN", "QUALITY_MANAGER", "STAFF", "EXPERT"];
  const targetRole = allowedRoles.includes(role) ? role : "STAFF";
  const normalizedEmail = email.trim().toLowerCase();

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  const newUserId = uuidv4();
  const passwordHash = bcrypt.hashSync(password || "Staff@2026", 10);
  let savedUser = null;

  if (checkPg()) {
    try {
      const checkRes = await query("SELECT id FROM users WHERE LOWER(email) = $1 LIMIT 1", [normalizedEmail]);
      if (checkRes && checkRes.rows.length > 0) {
        return res.status(400).json({ success: false, message: "A user with this email address already exists." });
      }

      const insertRes = await query(
        `INSERT INTO users (id, email, password_hash, full_name, role, facility_id, department, phone, is_active, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, true, NOW())
         RETURNING id, email, full_name, role, department, phone, is_active, created_at`,
        [newUserId, normalizedEmail, passwordHash, fullName, targetRole, req.tenantFacilityId, department || "General Quality", phone || ""]
      );

      if (insertRes && insertRes.rows.length > 0) {
        const row = insertRes.rows[0];
        savedUser = {
          id: row.id,
          email: row.email,
          fullName: row.full_name,
          role: row.role,
          department: row.department,
          phone: row.phone,
          isActive: row.is_active,
          createdAt: row.created_at
        };
      }
    } catch (err) {
      console.error("Error creating user in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to create user in database." });
      }
    }
  }

  if (!savedUser) {
    const existing = memoryDb.users.find(u => u.email.toLowerCase() === normalizedEmail);
    if (existing) {
      return res.status(400).json({ success: false, message: "A user with this email address already exists." });
    }
    const memUser = {
      id: `usr_${newUserId}`,
      email: normalizedEmail,
      password_hash: passwordHash,
      full_name: fullName,
      role: targetRole,
      facility_id: req.tenantFacilityId,
      department: department || "General Quality",
      phone: phone || "",
      is_active: true,
      created_at: new Date().toISOString()
    };
    memoryDb.users.push(memUser);
    savedUser = {
      id: memUser.id,
      email: memUser.email,
      fullName: memUser.full_name,
      role: memUser.role,
      department: memUser.department,
      phone: memUser.phone,
      isActive: memUser.is_active,
      createdAt: memUser.created_at
    };
  }

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: "FACILITY_USER_CREATED",
    details: { newUserId: savedUser.id, role: targetRole },
    req
  });

  res.status(201).json({
    success: true,
    message: "User created successfully.",
    user: savedUser
  });
});

// Update facility user details (Prevent mass assignment of role or facilityId)
app.put("/api/users/:id", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  const { id } = req.params;
  const { fullName, department, phone } = req.body;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let updatedUser = null;
  if (checkPg()) {
    try {
      const result = await query(
        `UPDATE users 
         SET full_name = COALESCE($3, full_name),
             department = COALESCE($4, department),
             phone = COALESCE($5, phone)
         WHERE id = $1 AND facility_id = $2
         RETURNING id, email, full_name, role, department, phone, is_active, created_at`,
        [id, req.tenantFacilityId, fullName || null, department || null, phone || null]
      );
      if (result && result.rows.length > 0) {
        const u = result.rows[0];
        updatedUser = {
          id: u.id,
          email: u.email,
          fullName: u.full_name,
          role: u.role,
          department: u.department,
          phone: u.phone,
          isActive: u.is_active,
          createdAt: u.created_at
        };
      }
    } catch (err) {
      console.error("Error updating user details in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to update user details." });
      }
    }
  }

  const memUser = memoryDb.users.find(u => u.id === id && u.facility_id === req.tenantFacilityId);
  if (memUser) {
    if (fullName) memUser.full_name = fullName;
    if (department) memUser.department = department;
    if (phone) memUser.phone = phone;
    if (!updatedUser) {
      updatedUser = {
        id: memUser.id,
        email: memUser.email,
        fullName: memUser.full_name,
        role: memUser.role,
        department: memUser.department,
        phone: memUser.phone,
        isActive: memUser.is_active,
        createdAt: memUser.created_at
      };
    }
  }

  if (!updatedUser) {
    return res.status(404).json({ success: false, message: "User not found in your facility." });
  }

  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "FACILITY_USER_UPDATED", details: { targetUserId: id }, req });
  res.json({ success: true, message: "User details updated successfully.", user: updatedUser });
});

// Deactivate / Reactivate facility user (Prevent self-deactivation)
app.put("/api/users/:id/status", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  const { id } = req.params;
  const { isActive } = req.body;

  if (id === req.user.userId) {
    return res.status(400).json({ success: false, message: "You cannot change your own account active status." });
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let updatedUser = null;
  const targetActive = Boolean(isActive);

  if (checkPg()) {
    try {
      const result = await query(
        `UPDATE users 
         SET is_active = $3 
         WHERE id = $1 AND facility_id = $2
         RETURNING id, email, full_name, role, department, phone, is_active, created_at`,
        [id, req.tenantFacilityId, targetActive]
      );
      if (result && result.rows.length > 0) {
        const u = result.rows[0];
        updatedUser = {
          id: u.id,
          email: u.email,
          fullName: u.full_name,
          role: u.role,
          department: u.department,
          phone: u.phone,
          isActive: u.is_active,
          createdAt: u.created_at
        };
      }
    } catch (err) {
      console.error("Error updating user status in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to update user status." });
      }
    }
  }

  const memUser = memoryDb.users.find(u => u.id === id && u.facility_id === req.tenantFacilityId);
  if (memUser) {
    memUser.is_active = targetActive;
    if (!updatedUser) {
      updatedUser = {
        id: memUser.id,
        email: memUser.email,
        fullName: memUser.full_name,
        role: memUser.role,
        department: memUser.department,
        phone: memUser.phone,
        isActive: memUser.is_active,
        createdAt: memUser.created_at
      };
    }
  }

  if (!updatedUser) {
    return res.status(404).json({ success: false, message: "User not found in your facility." });
  }

  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: `USER_${targetActive ? 'ACTIVATED' : 'DEACTIVATED'}`, details: { targetUserId: id }, req });
  res.json({ success: true, message: `User account has been ${targetActive ? 'reactivated' : 'deactivated'}.`, user: updatedUser });
});

// Toggle status alias
app.post("/api/users/:id/toggle-status", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  const { id } = req.params;

  if (id === req.user.userId) {
    return res.status(400).json({ success: false, message: "You cannot change your own account active status." });
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let updatedUser = null;
  if (checkPg()) {
    try {
      const result = await query(
        `UPDATE users 
         SET is_active = NOT is_active 
         WHERE id = $1 AND facility_id = $2
         RETURNING id, email, full_name, role, department, phone, is_active, created_at`,
        [id, req.tenantFacilityId]
      );
      if (result && result.rows.length > 0) {
        const u = result.rows[0];
        updatedUser = {
          id: u.id,
          email: u.email,
          fullName: u.full_name,
          role: u.role,
          department: u.department,
          phone: u.phone,
          isActive: u.is_active,
          createdAt: u.created_at
        };
      }
    } catch (err) {
      console.error("Error toggling user status in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to toggle user status." });
      }
    }
  }

  const memUser = memoryDb.users.find(u => u.id === id && u.facility_id === req.tenantFacilityId);
  if (memUser) {
    memUser.is_active = !memUser.is_active;
    if (!updatedUser) {
      updatedUser = {
        id: memUser.id,
        email: memUser.email,
        fullName: memUser.full_name,
        role: memUser.role,
        department: memUser.department,
        phone: memUser.phone,
        isActive: memUser.is_active,
        createdAt: memUser.created_at
      };
    }
  }

  if (!updatedUser) {
    return res.status(404).json({ success: false, message: "User not found in your facility." });
  }

  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: `USER_${updatedUser.isActive ? 'ACTIVATED' : 'DEACTIVATED'}`, details: { targetUserId: id }, req });
  res.json({ success: true, message: `User account has been ${updatedUser.isActive ? 'reactivated' : 'deactivated'}.`, user: updatedUser });
});

// Change user role (Prevent privilege escalation to SUPER_ADMIN or self-demotion)
app.put("/api/users/:id/role", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  const { id } = req.params;
  const { role } = req.body;

  const allowedRoles = ["FACILITY_ADMIN", "QUALITY_MANAGER", "STAFF", "EXPERT"];
  if (!allowedRoles.includes(role)) {
    return res.status(400).json({ success: false, message: "Invalid role specified." });
  }

  if (id === req.user.userId && role !== req.user.role) {
    return res.status(400).json({ success: false, message: "You cannot change your own role." });
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let updatedUser = null;
  if (checkPg()) {
    try {
      const result = await query(
        `UPDATE users 
         SET role = $3 
         WHERE id = $1 AND facility_id = $2
         RETURNING id, email, full_name, role, department, phone, is_active, created_at`,
        [id, req.tenantFacilityId, role]
      );
      if (result && result.rows.length > 0) {
        const u = result.rows[0];
        updatedUser = {
          id: u.id,
          email: u.email,
          fullName: u.full_name,
          role: u.role,
          department: u.department,
          phone: u.phone,
          isActive: u.is_active,
          createdAt: u.created_at
        };
      }
    } catch (err) {
      console.error("Error updating user role in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to update user role." });
      }
    }
  }

  const memUser = memoryDb.users.find(u => u.id === id && u.facility_id === req.tenantFacilityId);
  if (memUser) {
    memUser.role = role;
    if (!updatedUser) {
      updatedUser = {
        id: memUser.id,
        email: memUser.email,
        fullName: memUser.full_name,
        role: memUser.role,
        department: memUser.department,
        phone: memUser.phone,
        isActive: memUser.is_active,
        createdAt: memUser.created_at
      };
    }
  }

  if (!updatedUser) {
    return res.status(404).json({ success: false, message: "User not found in your facility." });
  }

  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "USER_ROLE_CHANGED", details: { targetUserId: id, newRole: role }, req });
  res.json({ success: true, message: `User role updated to ${role}.`, user: updatedUser });
});

// Delete facility user (Prevent self-deletion)
app.delete("/api/users/:id", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  const { id } = req.params;

  if (id === req.user.userId) {
    return res.status(400).json({ success: false, message: "You cannot delete your own user account." });
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let deleted = false;
  if (checkPg()) {
    try {
      const result = await query(
        `DELETE FROM users WHERE id = $1 AND facility_id = $2 RETURNING id`,
        [id, req.tenantFacilityId]
      );
      if (result && result.rows.length > 0) {
        deleted = true;
      }
    } catch (err) {
      console.error("Error deleting user from DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to delete user." });
      }
    }
  }

  const memIdx = memoryDb.users.findIndex(u => u.id === id && u.facility_id === req.tenantFacilityId);
  if (memIdx !== -1) {
    memoryDb.users.splice(memIdx, 1);
    deleted = true;
  }

  if (!deleted) {
    return res.status(404).json({ success: false, message: "User not found in your facility." });
  }

  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "FACILITY_USER_DELETED", details: { targetUserId: id }, req });
  res.json({ success: true, message: "User deleted successfully." });
});

// =============================================================================
// Super Admin Management Endpoints
// =============================================================================

app.get("/api/admin/facilities", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (checkPg()) {
    try {
      const result = await query(`
        SELECT id, name, name_ar, type, governorate, address, bed_capacity, 
               contact_person, work_email, phone, gahar_version, status, 
               subscription_plan_id, created_at
        FROM facilities 
        ORDER BY created_at DESC
      `);
      return res.json({ success: true, facilities: result.rows });
    } catch (err) {
      console.error("Error fetching admin facilities:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load facilities." });
      }
    }
  }

  res.json({ success: true, facilities: memoryDb.facilities });
});

app.put("/api/admin/facilities/:id/status", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  const { id } = req.params;
  const { status, reason } = req.body;

  if (!status) {
    return res.status(400).json({ success: false, message: "Status is required." });
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let updatedFacility = null;
  if (checkPg()) {
    try {
      const result = await query(
        `UPDATE facilities SET status = $1 WHERE id = $2 RETURNING *`,
        [status, id]
      );
      if (result && result.rows.length > 0) {
        updatedFacility = result.rows[0];
      }
    } catch (err) {
      console.error("Error updating facility status in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to update facility status." });
      }
    }
  }

  const memFac = memoryDb.facilities.find(f => f.id === id);
  if (memFac) {
    memFac.status = status;
  }

  const facility = updatedFacility || memFac;
  if (!facility) {
    return res.status(404).json({ success: false, message: "Facility not found." });
  }

  logAuditEvent({ facilityId: id, userId: req.user.userId, userEmail: req.user.email, action: `FACILITY_STATUS_UPDATED_${status}`, details: { status, reason }, req });

  await sendFacilityStatusNotification(facility.work_email, facility.name, status, reason);

  res.json({ success: true, message: `Facility status updated to ${status}.`, facility });
});

app.get("/api/admin/plans", authenticateToken, async (req, res) => {
  if (checkPg()) {
    try {
      const result = await query(`
        SELECT id, name, price_egp, billing_period, facility_limit, user_limit, features, is_active, created_at 
        FROM subscription_plans 
        ORDER BY price_egp ASC
      `);
      if (result && result.rows.length > 0) {
        return res.json({ success: true, plans: result.rows });
      }
    } catch (err) {
      console.error("Error fetching admin plans:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load subscription plans." });
      }
    }
  }

  res.json({ success: true, plans: memoryDb.subscription_plans });
});

app.post("/api/admin/plans", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  const { id, name, priceEgp, billingPeriod, features } = req.body;
  const planId = id || `plan_${uuidv4()}`;
  const price = priceEgp || 50000;
  const period = billingPeriod || "annual";
  const feat = Array.isArray(features) ? features : [];

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let savedPlan = null;
  if (checkPg()) {
    try {
      const result = await query(`
        INSERT INTO subscription_plans (id, name, price_egp, billing_period, features, is_active)
        VALUES ($1, $2, $3, $4, $5, true)
        ON CONFLICT (id) DO UPDATE SET
          name = COALESCE(EXCLUDED.name, subscription_plans.name),
          price_egp = COALESCE(EXCLUDED.price_egp, subscription_plans.price_egp),
          billing_period = COALESCE(EXCLUDED.billing_period, subscription_plans.billing_period),
          features = COALESCE(EXCLUDED.features, subscription_plans.features)
        RETURNING *;
      `, [planId, name, price, period, JSON.stringify(feat)]);
      if (result && result.rows.length > 0) {
        savedPlan = result.rows[0];
      }
    } catch (err) {
      console.error("Error saving plan to DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to save subscription plan." });
      }
    }
  }

  const existing = memoryDb.subscription_plans.find(p => p.id === planId);
  if (existing) {
    if (name) existing.name = name;
    if (priceEgp) existing.price_egp = priceEgp;
    if (billingPeriod) existing.billing_period = billingPeriod;
    if (features) existing.features = features;
  } else {
    memoryDb.subscription_plans.push({
      id: planId,
      name,
      price_egp: price,
      billing_period: period,
      features: feat,
      is_active: true
    });
  }

  res.status(savedPlan ? 200 : 201).json({
    success: true,
    message: "Subscription plan saved.",
    plan: savedPlan || existing
  });
});

app.get("/api/admin/analytics", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (checkPg()) {
    try {
      const countsRes = await query(`
        SELECT 
          COUNT(*)::int AS total_facilities,
          COUNT(*) FILTER (WHERE status IN ('ACTIVE', 'APPROVED'))::int AS active_subscriptions,
          COUNT(*) FILTER (WHERE status IN ('PENDING_REVIEW', 'PENDING_PAYMENT'))::int AS pending_registrations,
          COUNT(*) FILTER (WHERE status = 'SUSPENDED')::int AS suspended_facilities
        FROM facilities;
      `);
      const arrRes = await query(`
        SELECT COALESCE(SUM(p.price_egp), 0)::numeric AS total_arr
        FROM facilities f
        JOIN subscription_plans p ON f.subscription_plan_id = p.id
        WHERE f.status IN ('ACTIVE', 'APPROVED');
      `);
      const totalFacilities = countsRes.rows[0]?.total_facilities || 0;
      const activeSubscriptions = countsRes.rows[0]?.active_subscriptions || 0;
      const pendingRegistrations = countsRes.rows[0]?.pending_registrations || 0;
      const suspendedFacilities = countsRes.rows[0]?.suspended_facilities || 0;
      const annualArrEgp = Number(arrRes.rows[0]?.total_arr || 0);

      return res.json({
        success: true,
        analytics: {
          totalFacilities,
          activeSubscriptions,
          pendingRegistrations,
          suspendedFacilities,
          monthlyArrEgp: Math.round(annualArrEgp / 12),
          annualArrEgp,
          arrFormula: "ARR = Sum(Active/Approved Facility Subscription Plan Annual Prices)"
        }
      });
    } catch (err) {
      console.error("Error computing admin analytics:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to compute analytics." });
      }
    }
  }

  const totalFacilities = memoryDb.facilities.length;
  const activeSubscriptions = memoryDb.facilities.filter(f => f.status === "ACTIVE" || f.status === "APPROVED").length;
  const pendingRegistrations = memoryDb.facilities.filter(f => f.status === "PENDING_REVIEW" || f.status === "PENDING_PAYMENT").length;
  const suspendedFacilities = memoryDb.facilities.filter(f => f.status === "SUSPENDED").length;

  let totalArrEgp = 0;
  for (const fac of memoryDb.facilities) {
    if (fac.status === "ACTIVE" || fac.status === "APPROVED") {
      const plan = memoryDb.subscription_plans.find(p => p.id === fac.subscription_plan_id);
      totalArrEgp += plan ? Number(plan.price_egp) : 45000;
    }
  }

  res.json({
    success: true,
    analytics: {
      totalFacilities,
      activeSubscriptions,
      pendingRegistrations,
      suspendedFacilities,
      monthlyArrEgp: Math.round(totalArrEgp / 12),
      annualArrEgp: totalArrEgp,
      arrFormula: "ARR = Sum(Active/Approved Facility Subscription Plan Annual Prices)"
    }
  });
});

app.get("/api/admin/audit-logs", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (checkPg()) {
    try {
      const result = await query(`
        SELECT id, facility_id, user_id, user_email, action, entity_type, entity_id, details, ip_address, timestamp 
        FROM audit_logs 
        ORDER BY timestamp DESC 
        LIMIT 200
      `);
      if (result && result.rows) {
        return res.json({ success: true, auditLogs: result.rows });
      }
    } catch (err) {
      console.error("Error querying audit logs:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load audit logs." });
      }
    }
  }

  res.json({ success: true, auditLogs: memoryDb.audit_logs });
});

// =============================================================================
// Payment Endpoints
// =============================================================================

app.post("/api/payments/submit-proof", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { planId, amount, paymentMethod, transactionRef, proofUrl } = req.body;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Payment submission service unavailable without persistent database." });
  }

  const paymentId = uuidv4();
  const payment = {
    id: paymentId,
    facility_id: req.tenantFacilityId,
    plan_id: planId || "plan_standard",
    amount: amount || 45000,
    payment_method: paymentMethod || "Bank Transfer",
    status: "PENDING_VERIFICATION",
    transaction_ref: transactionRef,
    proof_url: proofUrl,
    created_at: new Date().toISOString()
  };

  // 1. Persist to PostgreSQL if connected
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        await client.query(
          `INSERT INTO payments (id, facility_id, plan_id, amount, payment_method, status, transaction_ref, proof_url, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
          [payment.id, payment.facility_id, payment.plan_id, payment.amount, payment.payment_method, payment.status, payment.transaction_ref, payment.proof_url]
        );
        await client.query("UPDATE facilities SET status = 'PENDING_REVIEW' WHERE id = $1", [req.tenantFacilityId]);
      });
    } catch (dbErr) {
      console.error("Error saving payment proof in DB:", dbErr.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to persist payment proof in database." });
      }
    }
  }

  // 2. Keep in memoryDb for in-memory cache and non-production testing
  memoryDb.payments.unshift(payment);

  const facility = memoryDb.facilities.find(f => f.id === req.tenantFacilityId);
  if (facility) {
    facility.status = "PENDING_REVIEW";
    await sendPaymentVerificationNotification(payment, facility.name);
  }

  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "PAYMENT_PROOF_SUBMITTED", details: { transactionRef, amount }, req });

  res.json({ success: true, message: "Payment reference submitted for Super Admin verification.", payment });
});

app.post("/api/payments/verify", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  const { paymentId, approved } = req.body;
  if (!paymentId) {
    return res.status(400).json({ success: false, message: "Payment ID is required." });
  }

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Payment verification service unavailable without persistent database." });
  }

  let payment = null;
  let facility = null;

  // 1. Look up payment in PostgreSQL if connected
  if (checkPg()) {
    try {
      const pRes = await query("SELECT * FROM payments WHERE id = $1 LIMIT 1", [paymentId]);
      if (pRes && pRes.rows.length > 0) {
        payment = pRes.rows[0];
        const fRes = await query("SELECT * FROM facilities WHERE id = $1 LIMIT 1", [payment.facility_id]);
        if (fRes && fRes.rows.length > 0) facility = fRes.rows[0];
      }
    } catch (err) {
      console.warn("Notice querying payment from DB:", err.message);
    }
  }

  // 2. Fallback to memoryDb (development / testing)
  if (!payment && !isProduction) {
    payment = memoryDb.payments.find(p => p.id === paymentId);
    if (payment) {
      facility = memoryDb.facilities.find(f => f.id === payment.facility_id);
    }
  }

  if (!payment) {
    return res.status(404).json({ success: false, message: "Payment record not found." });
  }

  const newStatus = approved ? "VERIFIED" : "REJECTED";
  payment.status = newStatus;

  // 3. Persist update in PostgreSQL transactionally
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        await client.query("UPDATE payments SET status = $1 WHERE id = $2", [newStatus, paymentId]);
        if (payment.facility_id && approved) {
          await client.query("UPDATE facilities SET status = 'APPROVED' WHERE id = $1", [payment.facility_id]);
        }
      });
    } catch (err) {
      console.error("Error updating payment in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to persist payment status update in database." });
      }
    }
  }

  // Also update memoryDb representation
  const memPayment = memoryDb.payments.find(p => p.id === paymentId);
  if (memPayment) memPayment.status = newStatus;
  const memFacility = memoryDb.facilities.find(f => f.id === payment.facility_id);
  if (memFacility && approved) {
    memFacility.status = "APPROVED";
  }

  const targetFacility = facility || memFacility;
  if (targetFacility && approved) {
    const plan = memoryDb.subscription_plans.find(p => p.id === payment.plan_id);
    const planName = plan ? plan.name : "Standard Hospital Plan";
    const expiryDate = new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString();

    sendFacilityStatusNotification(targetFacility.work_email, targetFacility.name, "APPROVED")
      .catch(e => console.warn("Notice sending facility status email:", e.message));
    sendSubscriptionActivatedNotification(targetFacility.work_email, targetFacility.name, planName, expiryDate)
      .catch(e => console.warn("Notice sending subscription activation email:", e.message));
  }

  logAuditEvent({ facilityId: payment.facility_id, userId: req.user.userId, userEmail: req.user.email, action: `PAYMENT_VERIFICATION_${newStatus}`, req });

  res.json({ success: true, payment });
});

// =============================================================================
// Document Storage & Management (PostgreSQL Persisted + In-Memory Fallback)
// =============================================================================

// Helper: Map database document row to response object
function _mapDocumentRow(row) {
  const storagePath = row.storage_path || row.file_path;
  const ext = storagePath ? path.extname(storagePath).toLowerCase() : "";
  const mimeMap = {
    ".pdf": "application/pdf",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".txt": "text/plain",
  };
  return {
    id: row.id,
    facilityId: row.facility_id,
    requirementCode: row.requirement_code || "GAHAR-EOC",
    title: row.title,
    category: row.category || "Clinical Policies",
    storagePath: storagePath,
    storageProvider: row.storage_provider || (storagePath ? "SUPABASE_STORAGE" : "LOCAL_SECURE_STORAGE"),
    fileSize: row.file_size ? parseInt(row.file_size, 10) : null,
    mimeType: row.mime_type || mimeMap[ext] || "application/pdf",
    version: row.version || "v1.0",
    status: row.status || "Active",
    uploadedBy: row.uploaded_by_email || row.deleted_by || row.uploaded_by || null,
    createdAt: row.created_at,
    deleted_at: row.deleted_at || null,
    deleted_by: row.deleted_by || null,
  };
}

// Upload document with file validation, PostgreSQL persistence & strict tenant isolation
app.post("/api/documents/upload", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let storedFile = null;
  try {
    const { title, category, requirementCode, originalName, mimeType, base64Content } = req.body;

    if (!title || !base64Content) {
      return res.status(400).json({ success: false, message: "Document title and base64 file content are required." });
    }

    storedFile = await uploadDocument({
      facilityId: req.tenantFacilityId,
      originalName: originalName || `${title}.pdf`,
      mimeType: mimeType || "application/pdf",
      base64Content
    });

    const docRecord = {
      id: `doc_${uuidv4()}`,
      facilityId: req.tenantFacilityId,
      requirementCode: requirementCode || "GAHAR-EOC",
      title,
      category: category || "Clinical Policies",
      storagePath: storedFile.storagePath,
      storageProvider: storedFile.storageProvider,
      fileSize: storedFile.sizeBytes,
      mimeType: storedFile.mimeType,
      version: "v1.0",
      status: "Active",
      uploadedBy: req.user.email,
      createdAt: new Date().toISOString()
    };

    if (checkPg()) {
      let uploadedByUuid = null;
      if (req.user?.userId && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(req.user.userId)) {
        uploadedByUuid = req.user.userId;
      }

      try {
        await query(
          `INSERT INTO documents (id, facility_id, requirement_code, title, category, file_path, version, status, uploaded_by, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())`,
          [docRecord.id, req.tenantFacilityId, docRecord.requirementCode, docRecord.title, docRecord.category, docRecord.storagePath, docRecord.version, docRecord.status, uploadedByUuid]
        );
      } catch (fkErr) {
        if (fkErr.code === "23503" && uploadedByUuid !== null) {
          // Fallback if foreign key constraint on uploaded_by fails (e.g. unseeded user ID)
          await query(
            `INSERT INTO documents (id, facility_id, requirement_code, title, category, file_path, version, status, uploaded_by, created_at)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULL, NOW())`,
            [docRecord.id, req.tenantFacilityId, docRecord.requirementCode, docRecord.title, docRecord.category, docRecord.storagePath, docRecord.version, docRecord.status]
          );
        } else {
          throw fkErr;
        }
      }
    }

    memoryDb.documents.unshift(docRecord);
    logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "DOCUMENT_UPLOADED", details: { docId: docRecord.id, title }, req });

    res.status(201).json({ success: true, message: "Document securely uploaded.", document: docRecord });
  } catch (err) {
    if (storedFile && storedFile.storagePath) {
      try {
        await deleteDocumentFile({ facilityId: req.tenantFacilityId, storagePath: storedFile.storagePath });
      } catch (_) {}
    }
    console.error("Error uploading document:", err.message);
    if (isProduction && checkPg() === false) {
      return res.status(503).json({ success: false, message: "Database service unavailable in production." });
    }
    res.status(400).json({ success: false, message: err.message });
  }
});

// List tenant documents from PostgreSQL (excludes soft-deleted items)
app.get("/api/documents", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (checkPg()) {
    try {
      const dRes = await query(
        `SELECT * FROM documents WHERE facility_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC`,
        [req.tenantFacilityId]
      );
      if (dRes && dRes.rows) {
        const mapped = dRes.rows.map(_mapDocumentRow);
        return res.json({ success: true, documents: mapped });
      }
    } catch (err) {
      console.error("Error fetching documents from DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load documents from database." });
      }
    }
  }

  const facilityDocs = memoryDb.documents.filter(d => (d.facilityId === req.tenantFacilityId || d.facility_id === req.tenantFacilityId) && !d.deleted_at);
  res.json({ success: true, documents: facilityDocs });
});

// Download tenant document (Short-lived signed URL or binary stream)
app.get("/api/documents/:id/download", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const { id } = req.params;

    let doc = null;
    if (checkPg()) {
      try {
        const dRes = await query(
          `SELECT * FROM documents WHERE id = $1 AND facility_id = $2 AND deleted_at IS NULL`,
          [id, req.tenantFacilityId]
        );
        if (dRes && dRes.rows && dRes.rows.length > 0) {
          doc = _mapDocumentRow(dRes.rows[0]);
        }
      } catch (err) {
        console.error("Error querying document for download from DB:", err.message);
        if (isProduction) {
          return res.status(500).json({ success: false, message: "Failed to query document from database." });
        }
      }
    }

    if (!doc) {
      doc = memoryDb.documents.find(d => d.id === id && (d.facilityId === req.tenantFacilityId || d.facility_id === req.tenantFacilityId) && !d.deleted_at);
    }

    if (!doc) {
      return res.status(404).json({ success: false, message: "Document not found or access denied." });
    }

    const storagePath = doc.storagePath || doc.file_path;

    // Try generating a short-lived signed URL if Supabase Storage is configured
    const signed = await getSignedDownloadUrl({
      facilityId: req.tenantFacilityId,
      storagePath,
      expiresInSeconds: 900 // 15 minutes
    });

    if (signed && signed.signedUrl) {
      if (req.query.format === "json") {
        return res.json({ success: true, signedUrl: signed.signedUrl, expiresIn: signed.expiresInSeconds });
      }
      return res.redirect(signed.signedUrl);
    }

    // Fallback to streaming buffer (for local development storage)
    const buffer = await getDocumentBuffer({
      facilityId: req.tenantFacilityId,
      storagePath
    });

    res.setHeader("Content-Type", doc.mimeType || "application/octet-stream");
    res.setHeader("Content-Disposition", `attachment; filename="${doc.title}.pdf"`);
    res.send(buffer);
  } catch (err) {
    res.status(403).json({ success: false, message: err.message });
  }
});

// Soft-delete document → moves to Trash
app.delete("/api/documents/:id", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { id } = req.params;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let deletedDoc = null;
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        const delRes = await client.query(
          `UPDATE documents SET deleted_at = NOW(), deleted_by = $1
           WHERE id = $2 AND facility_id = $3 AND deleted_at IS NULL
           RETURNING *`,
          [req.user.email, id, req.tenantFacilityId]
        );
        if (delRes && delRes.rows.length > 0) {
          deletedDoc = delRes.rows[0];
          const trashId = `trash_${uuidv4()}`;
          await client.query(
            `INSERT INTO trash (id, item_id, item_type, item_name, module, facility_id, deleted_at, deleted_by, snapshot)
             VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7, $8)`,
            [trashId, deletedDoc.id, "document", deletedDoc.title || deletedDoc.id, "Document Library", req.tenantFacilityId, req.user.email, JSON.stringify(deletedDoc)]
          );
        }
      });
    } catch (err) {
      console.error("Error soft-deleting document in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to delete document in database." });
      }
    }
  }

  const memDoc = memoryDb.documents.find(d => d.id === id && (d.facilityId === req.tenantFacilityId || d.facility_id === req.tenantFacilityId) && !d.deleted_at);
  if (memDoc) {
    memDoc.deleted_at = new Date().toISOString();
    memDoc.deleted_by = req.user.email;
    memoryDb.trash.push({
      id: `trash_${uuidv4()}`,
      item_id: memDoc.id,
      item_type: "document",
      item_name: memDoc.title || memDoc.id,
      module: "Document Library",
      facility_id: req.tenantFacilityId,
      deleted_at: memDoc.deleted_at,
      deleted_by: req.user.email,
      snapshot: { ...memDoc }
    });
  }

  if (!deletedDoc && !memDoc) {
    return res.status(404).json({ success: false, message: "Document not found." });
  }

  const title = (deletedDoc && deletedDoc.title) || (memDoc && memDoc.title) || id;
  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "DOCUMENT_MOVED_TO_TRASH", entityType: "document", entityId: id, details: { title }, req });
  res.json({ success: true, message: "Document moved to Trash." });
});

// Permanent-delete document (called from Trash screen)
app.delete("/api/documents/:id/permanent", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  const { id } = req.params;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let permDoc = null;
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        const dRes = await client.query(
          `SELECT * FROM documents WHERE id = $1 AND facility_id = $2 AND deleted_at IS NOT NULL`,
          [id, req.tenantFacilityId]
        );
        if (dRes && dRes.rows.length > 0) {
          permDoc = dRes.rows[0];
          await client.query(`DELETE FROM documents WHERE id = $1 AND facility_id = $2`, [id, req.tenantFacilityId]);
          await client.query(`DELETE FROM trash WHERE item_id = $1 AND facility_id = $2`, [id, req.tenantFacilityId]);
        }
      });
    } catch (err) {
      console.error("Error permanently deleting document in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to permanently delete document in database." });
      }
    }
  }

  const docIndex = memoryDb.documents.findIndex(d => d.id === id && (d.facilityId === req.tenantFacilityId || d.facility_id === req.tenantFacilityId) && d.deleted_at);
  let memDoc = null;
  if (docIndex !== -1) {
    memDoc = memoryDb.documents[docIndex];
    memoryDb.documents.splice(docIndex, 1);
    const ti = memoryDb.trash.findIndex(t => t.item_id === id && t.facility_id === req.tenantFacilityId);
    if (ti !== -1) memoryDb.trash.splice(ti, 1);
  }

  const doc = permDoc ? _mapDocumentRow(permDoc) : memDoc;
  if (!doc) {
    return res.status(404).json({ success: false, message: "Document not found in Trash." });
  }

  const storagePath = doc.storagePath || doc.file_path;
  if (storagePath) {
    try { await deleteDocumentFile({ facilityId: req.tenantFacilityId, storagePath }); } catch (_) {}
  }

  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "DOCUMENT_PERMANENTLY_DELETED", entityType: "document", entityId: id, details: { title: doc.title }, req });
  res.json({ success: true, message: "Document permanently deleted." });
});

// =============================================================================
// Multi-Tenant Accreditation Endpoints (JWT Derived Tenant)
// =============================================================================

// =============================================================================
// Multi-Tenant Accreditation Endpoints (PostgreSQL Persisted + In-Memory Fallback)
// =============================================================================

// --- GAPS API ---
app.get("/api/gaps", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (checkPg()) {
    try {
      const gRes = await query(
        `SELECT * FROM gaps WHERE facility_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC`,
        [req.tenantFacilityId]
      );
      if (gRes && gRes.rows) {
        const mapped = gRes.rows.map(g => ({
          id: g.id,
          facilityId: g.facility_id,
          standardCode: g.standard_code,
          chapterCode: g.chapter_code,
          gapTitle: g.gap_title || g.title,
          description: g.description,
          severity: g.severity,
          status: g.status,
          responsiblePerson: g.responsible_person,
          dueDate: g.due_date,
          actionPlanId: g.action_plan_id,
          evidenceIds: g.evidence_ids || [],
          createdAt: g.created_at,
          updatedAt: g.updated_at
        }));
        return res.json({ success: true, gaps: mapped });
      }
    } catch (err) {
      console.error("Error fetching gaps from DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load gaps from database." });
      }
    }
  }

  const facilityGaps = memoryDb.gaps.filter(g => (g.facilityId === req.tenantFacilityId || g.facility_id === req.tenantFacilityId) && !g.deleted_at);
  res.json({ success: true, gaps: facilityGaps });
});

app.post("/api/gaps", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  const newGapId = req.body.id || `gap_${uuidv4()}`;
  const standardCode = req.body.standardCode || req.body.standard_code || null;
  const chapterCode = req.body.chapterCode || req.body.chapter_code || (standardCode ? standardCode.split('.')[0] : null);
  const gapTitle = req.body.gapTitle || req.body.gap_title || req.body.title || 'Identified Gap';
  const description = req.body.description || null;
  const severity = req.body.severity || req.body.priority || 'medium';
  const status = req.body.status || 'inProgress';
  const responsiblePerson = req.body.responsiblePerson || req.body.responsible_person || 'Quality Officer';
  const dueDate = req.body.dueDate || req.body.due_date || null;
  const actionPlanId = req.body.actionPlanId || req.body.action_plan_id || null;
  const evidenceIds = req.body.evidenceIds || req.body.evidence_ids || [];

  const newGap = {
    id: newGapId,
    facilityId: req.tenantFacilityId,
    standardCode,
    chapterCode,
    gapTitle,
    title: gapTitle,
    description,
    severity,
    status,
    responsiblePerson,
    dueDate,
    actionPlanId,
    evidenceIds,
    createdAt: new Date().toISOString()
  };

  if (checkPg()) {
    try {
      await query(
        `INSERT INTO gaps (id, facility_id, standard_code, chapter_code, gap_title, title, description, severity, status, responsible_person, due_date, action_plan_id, evidence_ids, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, NOW(), NOW())`,
        [newGap.id, newGap.facilityId, newGap.standardCode, newGap.chapterCode, newGap.gapTitle, newGap.title, newGap.description, newGap.severity, newGap.status, newGap.responsiblePerson, newGap.dueDate, newGap.actionPlanId, newGap.evidenceIds]
      );
    } catch (err) {
      console.error("Error creating gap in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to persist gap in database." });
      }
    }
  }

  memoryDb.gaps.unshift(newGap);
  res.status(201).json({ success: true, gap: newGap });
});

app.delete("/api/gaps/:id", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { id } = req.params;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let deletedGap = null;
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        const delRes = await client.query(
          `UPDATE gaps SET deleted_at = NOW(), deleted_by = $1
           WHERE id = $2 AND facility_id = $3 AND deleted_at IS NULL
           RETURNING *`,
          [req.user.email, id, req.tenantFacilityId]
        );
        if (delRes && delRes.rows.length > 0) {
          deletedGap = delRes.rows[0];
          const trashId = `trash_${uuidv4()}`;
          await client.query(
            `INSERT INTO trash (id, item_id, item_type, item_name, module, facility_id, deleted_at, deleted_by, snapshot)
             VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7, $8)`,
            [trashId, deletedGap.id, 'gap', deletedGap.gap_title || deletedGap.title || deletedGap.id, 'Gap Analysis', req.tenantFacilityId, req.user.email, JSON.stringify(deletedGap)]
          );
        }
      });
    } catch (err) {
      console.error("Error soft-deleting gap in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to delete gap in database." });
      }
    }
  }

  const item = memoryDb.gaps.find(g => g.id === id && (g.facilityId === req.tenantFacilityId || g.facility_id === req.tenantFacilityId) && !g.deleted_at);
  if (item) {
    item.deleted_at = new Date().toISOString();
    item.deleted_by = req.user.email;
    memoryDb.trash.push({
      id: `trash_${uuidv4()}`,
      item_id: item.id,
      item_type: 'gap',
      item_name: item.gapTitle || item.gap_title || item.title || item.standard_code || item.id,
      module: 'Gap Analysis',
      facility_id: req.tenantFacilityId,
      deleted_at: item.deleted_at,
      deleted_by: req.user.email,
      snapshot: { ...item }
    });
  }

  if (!deletedGap && !item) {
    return res.status(404).json({ success: false, message: "Gap item not found." });
  }

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: "GAP_MOVED_TO_TRASH",
    entityType: 'gap',
    entityId: id,
    details: { title: item?.gapTitle || item?.title || deletedGap?.gap_title || deletedGap?.title },
    req
  });

  res.json({ success: true, message: "Gap item moved to Trash." });
});

// --- ACTION PLANS API ---
app.get("/api/action-plans", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (checkPg()) {
    try {
      const pRes = await query(
        `SELECT * FROM action_plans WHERE facility_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC`,
        [req.tenantFacilityId]
      );
      if (pRes && pRes.rows) {
        const mapped = pRes.rows.map(p => ({
          id: p.id,
          facilityId: p.facility_id,
          gapId: p.gap_id,
          title: p.title,
          description: p.description,
          assignedUser: p.assigned_user,
          department: p.department,
          priority: p.priority,
          startDate: p.start_date,
          dueDate: p.due_date,
          status: p.status,
          progress: Number(p.progress || 0),
          notes: p.notes || [],
          completionDate: p.completion_date,
          createdAt: p.created_at,
          updatedAt: p.updated_at
        }));
        return res.json({ success: true, actionPlans: mapped });
      }
    } catch (err) {
      console.error("Error fetching action plans from DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load action plans from database." });
      }
    }
  }

  const facilityPlans = memoryDb.action_plans.filter(p => (p.facilityId === req.tenantFacilityId || p.facility_id === req.tenantFacilityId) && !p.deleted_at);
  res.json({ success: true, actionPlans: facilityPlans });
});

app.post("/api/action-plans", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  const newPlanId = req.body.id || `plan_${uuidv4()}`;
  const gapId = req.body.gapId || req.body.gap_id || null;
  const title = req.body.title || 'Corrective Action Plan';
  const description = req.body.description || null;
  const assignedUser = req.body.assignedUser || req.body.assigned_user || '';
  const department = req.body.department || 'Quality';
  const priority = req.body.priority || 'high';
  const startDate = req.body.startDate || req.body.start_date || null;
  const dueDate = req.body.dueDate || req.body.due_date || null;
  const status = req.body.status || 'In Progress';
  const progress = parseFloat(req.body.progress || 0);
  const notes = req.body.notes || [];

  const newPlan = {
    id: newPlanId,
    facilityId: req.tenantFacilityId,
    gapId,
    title,
    description,
    assignedUser,
    department,
    priority,
    startDate,
    dueDate,
    status,
    progress,
    notes,
    createdAt: new Date().toISOString()
  };

  if (checkPg()) {
    try {
      await query(
        `INSERT INTO action_plans (id, facility_id, gap_id, title, description, assigned_user, department, priority, start_date, due_date, status, progress, notes, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, COALESCE($9, CURRENT_DATE), $10, $11, $12, $13, NOW(), NOW())`,
        [newPlan.id, newPlan.facilityId, newPlan.gapId, newPlan.title, newPlan.description, newPlan.assignedUser, newPlan.department, newPlan.priority, newPlan.startDate, newPlan.dueDate, newPlan.status, newPlan.progress, newPlan.notes]
      );
    } catch (err) {
      console.error("Error creating action plan in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to persist action plan in database." });
      }
    }
  }

  memoryDb.action_plans.unshift(newPlan);
  res.status(201).json({ success: true, actionPlan: newPlan });
});

app.delete("/api/action-plans/:id", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { id } = req.params;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let deletedPlan = null;
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        const delRes = await client.query(
          `UPDATE action_plans SET deleted_at = NOW(), deleted_by = $1
           WHERE id = $2 AND facility_id = $3 AND deleted_at IS NULL
           RETURNING *`,
          [req.user.email, id, req.tenantFacilityId]
        );
        if (delRes && delRes.rows.length > 0) {
          deletedPlan = delRes.rows[0];
          const trashId = `trash_${uuidv4()}`;
          await client.query(
            `INSERT INTO trash (id, item_id, item_type, item_name, module, facility_id, deleted_at, deleted_by, snapshot)
             VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7, $8)`,
            [trashId, deletedPlan.id, 'action_plan', deletedPlan.title || deletedPlan.id, 'Action Plans', req.tenantFacilityId, req.user.email, JSON.stringify(deletedPlan)]
          );
        }
      });
    } catch (err) {
      console.error("Error soft-deleting action plan in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to delete action plan in database." });
      }
    }
  }

  const item = memoryDb.action_plans.find(p => p.id === id && (p.facilityId === req.tenantFacilityId || p.facility_id === req.tenantFacilityId) && !p.deleted_at);
  if (item) {
    item.deleted_at = new Date().toISOString();
    item.deleted_by = req.user.email;
    memoryDb.trash.push({
      id: `trash_${uuidv4()}`,
      item_id: item.id,
      item_type: 'action_plan',
      item_name: item.title || item.id,
      module: 'Action Plans',
      facility_id: req.tenantFacilityId,
      deleted_at: item.deleted_at,
      deleted_by: req.user.email,
      snapshot: { ...item }
    });
  }

  if (!deletedPlan && !item) {
    return res.status(404).json({ success: false, message: "Action Plan not found." });
  }

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: "ACTION_PLAN_MOVED_TO_TRASH",
    entityType: 'action_plan',
    entityId: id,
    details: { title: item?.title || deletedPlan?.title },
    req
  });

  res.json({ success: true, message: "Action Plan moved to Trash." });
});

// --- LICENSES API ---
app.get("/api/licenses", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (checkPg()) {
    try {
      const lRes = await query(
        `SELECT * FROM licenses WHERE facility_id = $1 AND deleted_at IS NULL ORDER BY created_at DESC`,
        [req.tenantFacilityId]
      );
      if (lRes && lRes.rows) {
        const mapped = lRes.rows.map(l => ({
          id: l.id,
          facilityId: l.facility_id,
          licenseName: l.license_name,
          licenseNumber: l.license_number,
          issuingAuthority: l.issuing_authority,
          issueDate: l.issue_date,
          expirationDate: l.expiration_date,
          status: l.status,
          responsiblePerson: l.responsible_person,
          documentUrl: l.document_url,
          notes: l.notes,
          createdAt: l.created_at,
          updatedAt: l.updated_at
        }));
        return res.json({ success: true, licenses: mapped });
      }
    } catch (err) {
      console.error("Error fetching licenses from DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load licenses from database." });
      }
    }
  }

  const facilityLicenses = memoryDb.licenses.filter(l => (l.facilityId === req.tenantFacilityId || l.facility_id === req.tenantFacilityId) && !l.deleted_at);
  res.json({ success: true, licenses: facilityLicenses });
});

app.post("/api/licenses", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  const newLicenseId = req.body.id || `lic_${uuidv4()}`;
  const licenseName = req.body.licenseName || req.body.license_name || 'Operating License';
  const licenseNumber = req.body.licenseNumber || req.body.license_number || '';
  const issuingAuthority = req.body.issuingAuthority || req.body.issuing_authority || 'Ministry of Health';
  const issueDate = req.body.issueDate || req.body.issue_date || null;
  const expirationDate = req.body.expirationDate || req.body.expiration_date || null;
  const status = req.body.status || 'valid';
  const responsiblePerson = req.body.responsiblePerson || req.body.responsible_person || '';
  const documentUrl = req.body.documentUrl || req.body.document_url || null;
  const notes = req.body.notes || null;

  const newLicense = {
    id: newLicenseId,
    facilityId: req.tenantFacilityId,
    licenseName,
    licenseNumber,
    issuingAuthority,
    issueDate,
    expirationDate,
    status,
    responsiblePerson,
    documentUrl,
    notes,
    createdAt: new Date().toISOString()
  };

  if (checkPg()) {
    try {
      await query(
        `INSERT INTO licenses (id, facility_id, license_name, license_number, issuing_authority, issue_date, expiration_date, status, responsible_person, document_url, notes, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, COALESCE($6, CURRENT_DATE), COALESCE($7, CURRENT_DATE + INTERVAL '1 year'), $8, $9, $10, $11, NOW(), NOW())`,
        [newLicense.id, newLicense.facilityId, newLicense.licenseName, newLicense.licenseNumber, newLicense.issuingAuthority, newLicense.issueDate, newLicense.expirationDate, newLicense.status, newLicense.responsiblePerson, newLicense.documentUrl, newLicense.notes]
      );
    } catch (err) {
      console.error("Error creating license in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to persist license in database." });
      }
    }
  }

  memoryDb.licenses.unshift(newLicense);
  res.status(201).json({ success: true, license: newLicense });
});

app.delete("/api/licenses/:id", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { id } = req.params;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let deletedLic = null;
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        const delRes = await client.query(
          `UPDATE licenses SET deleted_at = NOW(), deleted_by = $1
           WHERE id = $2 AND facility_id = $3 AND deleted_at IS NULL
           RETURNING *`,
          [req.user.email, id, req.tenantFacilityId]
        );
        if (delRes && delRes.rows.length > 0) {
          deletedLic = delRes.rows[0];
          const trashId = `trash_${uuidv4()}`;
          await client.query(
            `INSERT INTO trash (id, item_id, item_type, item_name, module, facility_id, deleted_at, deleted_by, snapshot)
             VALUES ($1, $2, $3, $4, $5, $6, NOW(), $7, $8)`,
            [trashId, deletedLic.id, 'license', deletedLic.license_name || deletedLic.licenseName || deletedLic.id, 'Licenses & Basic Requirements', req.tenantFacilityId, req.user.email, JSON.stringify(deletedLic)]
          );
        }
      });
    } catch (err) {
      console.error("Error soft-deleting license in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to delete license in database." });
      }
    }
  }

  const item = memoryDb.licenses.find(l => l.id === id && (l.facilityId === req.tenantFacilityId || l.facility_id === req.tenantFacilityId) && !l.deleted_at);
  if (item) {
    item.deleted_at = new Date().toISOString();
    item.deleted_by = req.user.email;
    memoryDb.trash.push({
      id: `trash_${uuidv4()}`,
      item_id: item.id,
      item_type: 'license',
      item_name: item.licenseName || item.license_name || item.id,
      module: 'Licenses & Basic Requirements',
      facility_id: req.tenantFacilityId,
      deleted_at: item.deleted_at,
      deleted_by: req.user.email,
      snapshot: { ...item }
    });
  }

  if (!deletedLic && !item) {
    return res.status(404).json({ success: false, message: "License not found." });
  }

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: "LICENSE_MOVED_TO_TRASH",
    entityType: 'license',
    entityId: id,
    details: { name: item?.licenseName || deletedLic?.license_name },
    req
  });

  res.json({ success: true, message: "License moved to Trash." });
});

// =============================================================================
// Real Data-Driven Badges & Achievements
// =============================================================================

app.get("/api/facilities/badges", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const facilityId = req.tenantFacilityId;
  let gaps = [], licenses = [], docs = [];

  if (checkPg()) {
    try {
      const gRes = await query("SELECT * FROM gaps WHERE facility_id = $1 AND deleted_at IS NULL", [facilityId]);
      if (gRes && gRes.rows) gaps = gRes.rows;
      const lRes = await query("SELECT * FROM licenses WHERE facility_id = $1 AND deleted_at IS NULL", [facilityId]);
      if (lRes && lRes.rows) licenses = lRes.rows;
      const dRes = await query("SELECT * FROM generated_documents WHERE facility_id = $1", [facilityId]);
      if (dRes && dRes.rows) docs = dRes.rows;
    } catch (_) {}
  }

  if (gaps.length === 0 && !isProduction) gaps = memoryDb.gaps.filter(g => g.facilityId === facilityId);
  if (licenses.length === 0 && !isProduction) licenses = memoryDb.licenses.filter(l => l.facilityId === facilityId);
  if (docs.length === 0 && !isProduction) docs = memoryDb.documents.filter(d => d.facilityId === facilityId);

  let overallScore = 0;
  try {
    let standards = null, scores = null;
    if (checkPg()) {
      const sRes = await query("SELECT * FROM sat_standards WHERE is_active = true");
      const scRes = await query("SELECT * FROM sat_scores WHERE facility_id = $1", [facilityId]);
      if (sRes && sRes.rows) standards = sRes.rows;
      if (scRes && scRes.rows) scores = scRes.rows;
    }
    if (!standards) standards = memoryDb.sat_standards || [];
    if (!scores) scores = (memoryDb.sat_scores || []).filter(s => s.facility_id === facilityId);

    const excluded = await getExcludedStandardsSet(facilityId);
    const chapters = calculateChapterSummary(standards, scores, excluded);
    const totalApplicable = chapters.reduce((sum, c) => sum + c.applicable, 0);
    const totalScoreSum = chapters.reduce((sum, c) => sum + c.score_sum, 0);
    overallScore = totalApplicable > 0 ? Math.round((totalScoreSum / (totalApplicable * 100)) * 100) : 0;
  } catch (e) {
    overallScore = 0;
  }

  // Centralized GAHAR Journey Badges
  // Video 7 mentions 50%, Video 10 mentions 60%. Configurable threshold = 50%
  const SILVER_THRESHOLD = 50;
  const GOLD_THRESHOLD = 80;
  const PLATINUM_THRESHOLD = 90;

  const journeyBadges = [
    {
      id: "badge_silver_initiator",
      stage: "PHASE 1: READINESS",
      title: "Silver / Initiator Badge",
      titleAr: "الشارة الفضية (المبادر)",
      description: "Achieved baseline compliance (≥50%) across applicable GAHAR standards.",
      threshold: `${SILVER_THRESHOLD}%`,
      isUnlocked: overallScore >= SILVER_THRESHOLD,
      currentScore: overallScore,
      icon: "military_tech",
      color: "0xFF94A3B8",
      businessVerificationNote: "Video 7 specifies 50%, Video 10 mentions 60%. Configured default: 50%."
    },
    {
      id: "badge_gold_execution",
      stage: "PHASE 2: EXECUTION",
      title: "Gold Badge",
      titleAr: "الشارة الذهبية",
      description: "Achieved advanced compliance (≥80%) across applicable GAHAR standards.",
      threshold: `${GOLD_THRESHOLD}%`,
      isUnlocked: overallScore >= GOLD_THRESHOLD,
      currentScore: overallScore,
      icon: "workspace_premium",
      color: "0xFFF59E0B",
    },
    {
      id: "badge_platinum_master",
      stage: "PHASE 3: FINAL READINESS",
      title: "Platinum / Master Badge",
      titleAr: "الشارة البلاتينية (الجاهزية التامة)",
      description: "Facility has achieved comprehensive audit readiness (≥90%) for official survey submission.",
      threshold: `${PLATINUM_THRESHOLD}%`,
      isUnlocked: overallScore >= PLATINUM_THRESHOLD,
      currentScore: overallScore,
      icon: "stars",
      color: "0xFF38BDF8",
    }
  ];

  const resolvedGaps = gaps.filter(g => g.status === "compliant" || g.status === "closed").length;
  const validLicenses = licenses.filter(l => l.status === "valid").length;

  res.json({
    success: true,
    overallScore,
    currentBadge: overallScore >= PLATINUM_THRESHOLD ? "PLATINUM" : (overallScore >= GOLD_THRESHOLD ? "GOLD" : (overallScore >= SILVER_THRESHOLD ? "SILVER" : "NONE")),
    badges: journeyBadges,
    summary: { totalGaps: gaps.length, resolvedGaps, validLicenses, documentsCount: docs.length }
  });
});

// =============================================================================
// GAHAR Applicability Engine Endpoints
// =============================================================================

app.get("/api/applicability/questions", authenticateToken, (req, res) => {
  res.json({ success: true, questions: getApplicabilityQuestions() });
});

app.get("/api/applicability/status", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const data = await getFacilityApplicability(req.tenantFacilityId);
    res.json({ success: true, applicability: data });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

app.post("/api/applicability/submit", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const { answers } = req.body;
    const result = await saveFacilityApplicability(req.tenantFacilityId, answers);
    logAuditEvent({
      facilityId: req.tenantFacilityId,
      userId: req.user.userId,
      userEmail: req.user.email,
      action: "APPLICABILITY_ASSESSMENT_SUBMITTED",
      details: { excludedCount: result.excludedCount },
      req,
    });
    res.json({ success: true, applicability: result });
  } catch (e) {
    res.status(400).json({ success: false, message: e.message });
  }
});

// =============================================================================
// GAHAR Document Generation & Version Control Endpoints
// =============================================================================

app.get("/api/documents/catalog", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const catalog = await getCatalogWithApplicability(req.tenantFacilityId);
    res.json({ success: true, catalog });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

app.get("/api/documents/dashboard", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const dashboard = await getDocumentDashboard(req.tenantFacilityId);
    res.json({ success: true, dashboard });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

const handleGenerateDraft = async (req, res) => {
  try {
    const rawDocCode = req.body.docCode || req.body.templateCode;
    const rawAnswers = req.body.wizardAnswers || req.body.customization || {};
    const standardCode = req.body.standardCode || (rawAnswers.standardCode) || (rawAnswers.standard);
    const docCode = rawDocCode || (standardCode ? `GAHAR-POL-${standardCode.replace('.', '-')}` : undefined);

    let facility = null;
    if (checkPg()) {
      const fRes = await query("SELECT name FROM facilities WHERE id = $1", [req.tenantFacilityId]);
      if (fRes && fRes.rows.length > 0) facility = fRes.rows[0];
    }
    if (!facility) facility = memoryDb.facilities.find(f => f.id === req.tenantFacilityId) || { name: 'Healthcare Facility' };

    const facilityName = (rawAnswers.facilityName && rawAnswers.facilityName.trim().length > 0)
      ? rawAnswers.facilityName.trim()
      : facility.name;

    const doc = await generateDocumentDraft({
      facilityId: req.tenantFacilityId,
      facilityName,
      standardCode,
      docCode,
      wizardAnswers: rawAnswers,
      authorUser: req.user,
    });

    logAuditEvent({
      facilityId: req.tenantFacilityId,
      userId: req.user.userId,
      userEmail: req.user.email,
      action: "DOCUMENT_DRAFT_GENERATED",
      details: { docCode: doc.doc_code, title: doc.title },
      req,
    });

    res.status(201).json({ success: true, document: doc, draft: doc });
  } catch (e) {
    res.status(400).json({ success: false, message: e.message });
  }
};

app.post("/api/documents/generate-draft", authenticateToken, enforceTenantIsolation, handleGenerateDraft);
app.post("/api/documents/draft", authenticateToken, enforceTenantIsolation, handleGenerateDraft);

app.post("/api/documents/version", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const { docCode, documentId, id, content, changeSummary } = req.body;
    const targetId = documentId || id || docCode;
    const updated = await saveDocumentVersion({
      documentId: targetId,
      facilityId: req.tenantFacilityId,
      content,
      changeSummary,
      authorUser: req.user,
    });
    res.json({ success: true, document: updated });
  } catch (e) {
    res.status(400).json({ success: false, message: e.message });
  }
});

app.put("/api/documents/:id/version", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const { id } = req.params;
    const { content, changeSummary } = req.body;
    const updated = await saveDocumentVersion({
      documentId: id,
      facilityId: req.tenantFacilityId,
      content,
      changeSummary,
      authorUser: req.user,
    });

    logAuditEvent({
      facilityId: req.tenantFacilityId,
      userId: req.user.userId,
      userEmail: req.user.email,
      action: "DOCUMENT_VERSION_SAVED",
      details: { documentId: id, version: updated.version },
      req,
    });

    res.json({ success: true, document: updated });
  } catch (e) {
    res.status(400).json({ success: false, message: e.message });
  }
});

app.put("/api/documents/:id/approval", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "QUALITY_MANAGER", "SUPER_ADMIN"), async (req, res) => {
  try {
    const { id } = req.params;
    const { status, rejectionReason } = req.body;
    const updated = await updateDocumentApprovalStatus({
      documentId: id,
      facilityId: req.tenantFacilityId,
      status,
      reviewerUser: req.user,
      rejectionReason,
    });

    logAuditEvent({
      facilityId: req.tenantFacilityId,
      userId: req.user.userId,
      userEmail: req.user.email,
      action: "DOCUMENT_STATUS_CHANGED",
      details: { documentId: id, status },
      req,
    });

    res.json({ success: true, document: updated });
  } catch (e) {
    res.status(400).json({ success: false, message: e.message });
  }
});

app.get("/api/documents/:id/versions", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const { id } = req.params;
    const versions = await getDocumentVersions(id, req.tenantFacilityId);
    res.json({ success: true, versions });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// =============================================================================
// GAHAR Phase 3 & 4: Mock Survey Prep, Monitoring & ROI Endpoints
// =============================================================================

app.post("/api/mock-surveys/request", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const record = await createMockSurveyRequest(req.tenantFacilityId, req.body);
    logAuditEvent({
      facilityId: req.tenantFacilityId,
      userId: req.user.userId,
      userEmail: req.user.email,
      action: "MOCK_SURVEY_REQUESTED",
      details: { onsiteDays: record.onsite_days, consultantsCount: record.consultants_count },
      req,
    });
    res.status(201).json({ success: true, mockSurvey: record });
  } catch (e) {
    res.status(400).json({ success: false, message: e.message });
  }
});

app.get("/api/mock-surveys", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const surveys = await getMockSurveysForFacility(req.tenantFacilityId);
    res.json({ success: true, mockSurveys: surveys });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

app.get("/api/monitoring/summary", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const summary = await getMonitoringSummary(req.tenantFacilityId);
    res.json({ success: true, monitoring: summary });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

app.get("/api/roi/analytics", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const roi = await getFacilityRoiAnalytics(req.tenantFacilityId);
    res.json({ success: true, roi });
  } catch (e) {
    res.status(500).json({ success: false, message: e.message });
  }
});

// Facility Settings Change Requests & Pending Approval
app.post("/api/facilities/settings/request-change", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { fieldName, oldValue, newValue, reason } = req.body;
  const requestId = uuidv4();
  const reqObj = {
    id: requestId,
    facility_id: req.tenantFacilityId,
    requested_by: req.user.userId,
    field_name: fieldName,
    old_value: oldValue,
    new_value: newValue,
    reason: reason || '',
    status: 'PENDING_APPROVAL',
    created_at: new Date().toISOString(),
  };

  if (checkPg()) {
    try {
      await query(`
        INSERT INTO facility_settings_requests (id, facility_id, requested_by, field_name, old_value, new_value, reason, status, created_at)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
      `, [requestId, req.tenantFacilityId, req.user.userId, fieldName, String(oldValue), String(newValue), reason, 'PENDING_APPROVAL']);
    } catch (e) {
      console.warn('DB settings change error:', e.message);
    }
  }

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: "FACILITY_SETTINGS_CHANGE_REQUESTED",
    details: { fieldName, newValue },
    req,
  });

  res.status(201).json({ success: true, message: 'Change request submitted for Super Admin review.', request: reqObj });
});

app.get("/api/facilities/settings/pending-requests", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (checkPg()) {
    try {
      const resDb = await query('SELECT * FROM facility_settings_requests WHERE facility_id = $1 ORDER BY created_at DESC', [req.tenantFacilityId]);
      return res.json({ success: true, requests: resDb?.rows || [] });
    } catch (e) {
      console.warn('DB get settings requests error:', e.message);
    }
  }
  res.json({ success: true, requests: [] });
});

// =============================================================================
// Accreditation Experts Hub (Real Consultation Request Flow)
// =============================================================================

app.post("/api/experts/request-consultation", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  const { expertId, expertName, topic, preferredDate, notes } = req.body;
  const requestId = uuidv4();
  const targetTopic = topic || "GAHAR 2025 Mock Audit";
  const targetExpertId = expertId || "exp_01";
  const targetExpertName = expertName || "Accreditation Consultant";
  const targetNotes = notes || "";
  let parsedDate = null;
  if (preferredDate) {
    try {
      const d = new Date(preferredDate);
      if (!isNaN(d.getTime())) parsedDate = d.toISOString().split("T")[0];
    } catch (_) {}
  }

  let facilityName = "Facility";
  let savedRequest = null;

  if (checkPg()) {
    try {
      const fRes = await query("SELECT name FROM facilities WHERE id = $1 LIMIT 1", [req.tenantFacilityId]);
      if (fRes && fRes.rows.length > 0) {
        facilityName = fRes.rows[0].name;
      }

      const insRes = await query(
        `INSERT INTO consultation_requests (id, facility_id, expert_id, expert_name, topic, preferred_date, notes, status, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'PENDING', NOW())
         RETURNING *`,
        [requestId, req.tenantFacilityId, targetExpertId, targetExpertName, targetTopic, parsedDate, targetNotes]
      );
      if (insRes && insRes.rows.length > 0) {
        const row = insRes.rows[0];
        savedRequest = {
          id: row.id,
          facilityId: row.facility_id,
          facilityName,
          expertId: row.expert_id,
          expertName: row.expert_name,
          topic: row.topic,
          preferredDate: row.preferred_date,
          notes: row.notes,
          status: row.status,
          createdAt: row.created_at
        };
      }
    } catch (err) {
      console.error("Error creating consultation request in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to persist consultation request in database." });
      }
    }
  }

  if (!savedRequest) {
    const memFac = memoryDb.facilities.find(f => f.id === req.tenantFacilityId);
    if (memFac) facilityName = memFac.name;

    savedRequest = {
      id: requestId,
      facilityId: req.tenantFacilityId,
      facilityName,
      expertId: targetExpertId,
      expertName: targetExpertName,
      topic: targetTopic,
      preferredDate: parsedDate || new Date().toISOString(),
      notes: targetNotes,
      status: "PENDING",
      createdAt: new Date().toISOString()
    };
  }

  memoryDb.consultation_requests.unshift(savedRequest);
  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "CONSULTATION_REQUEST_SUBMITTED", details: { expertId: targetExpertId, topic: targetTopic }, req });

  res.status(201).json({ success: true, message: "Consultation request recorded. An advisor will contact your quality team.", request: savedRequest });
});

app.get("/api/experts/my-requests", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (checkPg()) {
    try {
      const result = await query(
        `SELECT c.id, c.facility_id, f.name AS facility_name, c.expert_id, c.expert_name, 
                c.topic, c.preferred_date, c.notes, c.status, c.created_at
         FROM consultation_requests c
         LEFT JOIN facilities f ON c.facility_id = f.id
         WHERE c.facility_id = $1
         ORDER BY c.created_at DESC`,
        [req.tenantFacilityId]
      );
      if (result && result.rows) {
        const mapped = result.rows.map(r => ({
          id: r.id,
          facilityId: r.facility_id,
          facilityName: r.facility_name || "Facility",
          expertId: r.expert_id,
          expertName: r.expert_name,
          topic: r.topic,
          preferredDate: r.preferred_date,
          notes: r.notes,
          status: r.status,
          createdAt: r.created_at
        }));
        return res.json({ success: true, requests: mapped });
      }
    } catch (err) {
      console.error("Error fetching consultation requests from DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load consultation requests from database." });
      }
    }
  }

  const requests = memoryDb.consultation_requests.filter(r => r.facilityId === req.tenantFacilityId);
  res.json({ success: true, requests });
});

// =============================================================================
// Subscriptions Current Lifecycle Endpoint (PostgreSQL Persisted + In-Memory Fallback)
// =============================================================================

app.get("/api/subscriptions/current", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let facility = null;
  let plan = null;

  if (checkPg()) {
    try {
      const fRes = await query(
        `SELECT f.id, f.name, f.status, f.created_at, f.subscription_plan_id,
                p.id AS plan_id, p.name AS plan_name, p.price_egp, p.billing_period, p.features
         FROM facilities f
         LEFT JOIN subscription_plans p ON f.subscription_plan_id = p.id
         WHERE f.id = $1`,
        [req.tenantFacilityId]
      );
      if (fRes && fRes.rows && fRes.rows.length > 0) {
        const row = fRes.rows[0];
        facility = {
          id: row.id,
          name: row.name,
          status: row.status,
          created_at: row.created_at,
          subscription_plan_id: row.subscription_plan_id,
        };
        plan = {
          id: row.plan_id || row.subscription_plan_id || "plan_standard",
          name: row.plan_name || "Standard Hospital Plan",
          price_egp: row.price_egp || 45000,
          billing_period: row.billing_period || "annual",
          features: row.features || [
            "Full GAHAR 2025 Standards Access",
            "Unlimited Gap Assessments",
            "Document Storage (15MB per file)",
            "AI Copilot Audit Preparation Assistant"
          ]
        };
      }
    } catch (err) {
      console.error("Error fetching current subscription from DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load subscription data from database." });
      }
    }
  }

  // Fallback to memoryDb (development / testing)
  if (!facility) {
    facility = memoryDb.facilities.find(f => f.id === req.tenantFacilityId);
    if (facility) {
      plan = memoryDb.subscription_plans.find(p => p.id === facility.subscription_plan_id) || memoryDb.subscription_plans[0];
    }
  }

  if (!facility) {
    return res.status(404).json({ success: false, message: "Facility record not found." });
  }

  if (!plan) {
    plan = memoryDb.subscription_plans[0] || {
      id: "plan_standard",
      name: "Standard Hospital Plan",
      price_egp: 45000,
      billing_period: "annual",
      features: []
    };
  }

  // Calculate expiration (1 year from facility creation)
  const createdDate = new Date(facility.created_at || Date.now());
  const expirationDate = new Date(createdDate.getTime() + 365 * 24 * 3600 * 1000);
  const now = new Date();
  const diffDays = Math.ceil((expirationDate - now) / (1000 * 60 * 60 * 24));

  res.json({
    success: true,
    subscription: {
      facilityId: facility.id,
      facilityName: facility.name,
      planId: plan.id,
      planName: plan.name,
      priceEgp: plan.price_egp,
      billingPeriod: plan.billing_period,
      status: facility.status === "APPROVED" || facility.status === "ACTIVE" ? "ACTIVE" : facility.status,
      startDate: createdDate.toISOString(),
      expirationDate: expirationDate.toISOString(),
      daysRemaining: Math.max(0, diffDays),
      isExpiringSoon: diffDays <= 30 && diffDays > 0,
      features: plan.features
    }
  });
});

// =============================================================================
// AI Copilot Endpoint (Proxy Server - Zero Client Keys Exposed)
// =============================================================================

let cachedBylawsLines = null;
let cachedSatData = null;

function getExactStandardGrounding(code) {
  const normCode = code.toUpperCase().replace('-', '.');
  const fs = require('fs');

  // Load sat_full_dataset.json
  if (!cachedSatData) {
    try {
      const p = path.join(__dirname, 'sat_full_dataset.json');
      if (fs.existsSync(p)) {
        cachedSatData = JSON.parse(fs.readFileSync(p, 'utf8'));
      }
    } catch (e) {
      console.warn('Failed to load sat_full_dataset.json:', e.message);
    }
  }

  // Load bylaws_extracted.txt
  if (!cachedBylawsLines) {
    try {
      const p = path.join(__dirname, 'bylaws_extracted.txt');
      if (fs.existsSync(p)) {
        cachedBylawsLines = fs.readFileSync(p, 'utf8').split('\n');
      } else {
        cachedBylawsLines = [];
      }
    } catch (e) {
      console.warn('Failed to load bylaws_extracted.txt:', e.message);
      cachedBylawsLines = [];
    }
  }

  const standard = cachedSatData?.standards?.find(s => s.standard_code === normCode);
  const subEvidences = cachedSatData?.subEvidence?.filter(s => s.standard_code === normCode) || [];
  const bylawMatches = (cachedBylawsLines || []).filter(line => line.includes(normCode));

  // If standard is not found anywhere in official dataset, return null
  if (!standard && subEvidences.length === 0 && bylawMatches.length === 0) {
    return null;
  }

  const sections = [];
  if (standard) {
    sections.push(`### Standard Code: ${standard.standard_code}`);
    sections.push(`**Title:** ${standard.standard_title || 'N/A'}`);
    sections.push(`**Chapter:** ${standard.chapter_title || standard.chapter_code || 'General'}`);
    if (standard.is_essential) sections.push(`**Classification:** ⭐ ESSENTIAL SAFETY REQUIREMENT (معيار أمان حرج)`);
  } else {
    sections.push(`### Standard Code: ${normCode}`);
  }

  if (subEvidences.length > 0) {
    sections.push(`\n**Evidence of Compliance (EOC) Requirements / متطلبات أدلة الامتثال:**`);
    subEvidences.forEach(se => {
      let line = `- **[${se.id}]** ${se.requirement_text}`;
      const reqs = [];
      if (se.documents_required) reqs.push(`Docs: ${se.documents_required}`);
      if (se.interview_required) reqs.push(`Interview: ${se.interview_required}`);
      if (se.observation_required) reqs.push(`Observation: ${se.observation_required}`);
      if (reqs.length > 0) line += ` *(${reqs.join(' | ')})*`;
      sections.push(line);
    });
  }

  if (bylawMatches.length > 0) {
    sections.push(`\n**Accreditation Handbook Context / نص المعيار من الدليل:**`);
    const cleanMatches = bylawMatches.slice(0, 4).map(m => m.trim()).filter(Boolean);
    sections.push(cleanMatches.join('\n\n'));
  }

  return sections.join('\n');
}

app.post("/api/ai/copilot", authenticateToken, async (req, res) => {
  const { prompt, message, query, screenContext, entityData, conversationHistory } = req.body;

  // 1. Determine clean current user query strictly from client message, query or [USER QUESTION] block
  let userQuery = (message || query || '').trim();
  if (!userQuery && prompt) {
    if (prompt.includes('[USER QUESTION]:')) {
      const parts = prompt.split('[USER QUESTION]:');
      userQuery = parts[1].split('[GAHAR STANDARDS CONTEXT]:')[0].trim();
    } else {
      userQuery = prompt.trim();
    }
  }

  console.log(`🤖 AI Copilot Query [${screenContext || 'General'}] User: ${req.user.email} | Query: "${userQuery.substring(0, 60)}"`);

  // 2. Extract standard code from the CURRENT user query ONLY (never from prompt template boilerplate)
  const standardMatch = userQuery.match(/\b([A-Za-z]{2,4}[.\-]\d{2})\b/);
  let standardCode = null;
  let standardGrounding = null;

  if (standardMatch) {
    standardCode = standardMatch[1].toUpperCase().replace('-', '.');
    standardGrounding = getExactStandardGrounding(standardCode);

    // If a specific standard code was requested by the user, but does not exist in authoritative GAHAR dataset:
    if (!standardGrounding) {
      const isAr = /[\u0600-\u06FF]/.test(userQuery);
      const notFoundReply = isAr
        ? `عذراً، المعيار (**${standardCode}**) غير موجود في دليل معايير جهار الرسمية للمستشفيات 2025 (GAHAR 2025 Standards).\n\nيرجى التأكد من كود المعيار ومراجعته في الدليل الرسمي للهيئة العامة للاعتماد والرقابة الصحية.`
        : `The standard (**${standardCode}**) was not found in the authoritative GAHAR 2025 Hospital Standards handbook.\n\nPlease verify the standard code against the official GAHAR accreditation dataset.`;
      return res.json({ success: true, reply: notFoundReply, standardFound: false, standardCode });
    }
  } else {
    // Check if user is explicitly referencing the immediate preceding standard (e.g. "this standard", "المعيار ده")
    const isContextualRef = /\b(this standard|the standard|the previous standard|same standard)\b/i.test(userQuery) ||
                            /(هذا المعيار|المعيار ده|نفس المعيار|المعيار السابق)/.test(userQuery);
    if (isContextualRef && Array.isArray(conversationHistory) && conversationHistory.length > 0) {
      for (let i = conversationHistory.length - 1; i >= 0; i--) {
        const prev = conversationHistory[i];
        if (prev.role === 'user' && prev.content) {
          const m = prev.content.match(/\b([A-Za-z]{2,4}[.\-]\d{2})\b/);
          if (m) {
            standardCode = m[1].toUpperCase().replace('-', '.');
            standardGrounding = getExactStandardGrounding(standardCode);
            break;
          }
        }
      }
    }
  }

  const isArabic = /[\u0600-\u06FF]/.test(userQuery);
  let systemPrompt = `You are the official GAHAR AI Copilot for Healthcare Accreditation in Egypt.
Current Screen/Context: "${screenContext || 'GAHAR Accreditation'}".
Entity Data: ${JSON.stringify(entityData || {})}.
Language Instruction: Respond in ${isArabic ? 'Arabic (اللغة العربية)' : 'English'}, matching the user inquiry.
Do NOT invent non-existent standard codes. Do NOT claim standards from other chapters unless directly related.`;

  if (standardCode && standardGrounding) {
    systemPrompt += `\n\nAUTHORITATIVE GAHAR 2025 OFFICIAL REFERENCE FOR STANDARD ${standardCode}:
${standardGrounding}

CRITICAL ACCREDITATION RETRIEVAL INSTRUCTIONS:
- Ground your answer strictly and exclusively in standard ${standardCode}.
- List the specific requirements and Evidence of Compliance (EOC) required for ${standardCode} as given in the official GAHAR reference above.
- Do NOT bring in unrelated standards from other chapters unless explicitly requested.
- Do NOT fabricate requirements or evidence.`;
  } else {
    systemPrompt += `\n\nGENERAL GAHAR ACCREDITATION INSTRUCTIONS:
- The user is asking a general accreditation question or asking for guidance without specifying a single standard code.
- Answer their specific question accurately using official GAHAR 2025 principles.
- Do NOT arbitrarily force, assume, or default to GSR.01 unless specifically asked by the user.`;
  }

  // Multi-provider execution: Groq -> Gemini -> OpenAI with timeouts and fallback
  const aiResult = await generateCopilotReply({
    systemPrompt,
    userMessage: userQuery || prompt,
    standardCode,
    standardGrounding,
    isArabic
  });

  if (aiResult.success) {
    return res.json({
      success: true,
      reply: aiResult.reply,
      provider: aiResult.provider,
      model: aiResult.model,
      standardCode: standardCode || null
    });
  }

  // All AI providers failed:
  // If user requested an authoritative standard code, return official handbook grounding with clear disclaimer
  if (standardCode && standardGrounding) {
    const disclaimer = isArabic
      ? `*(تنبيه: خدمة المساعد الذكي غير متاحة حالياً بسبب انشغال مزودي الخدمة السحابية. تم استرجاع نص المعيار المعتمد مباشرة من دليل جهار 2025 الرسمي)*\n\n`
      : `*(Notice: Generative AI copilot is currently unavailable. Displaying verified authoritative text directly from the official GAHAR 2025 Handbook)*\n\n`;
    
    return res.json({
      success: true,
      reply: `${disclaimer}**GAHAR 2025 Official Reference — Standard ${standardCode}**\n\n${standardGrounding}`,
      isAuthoritativeFallback: true,
      standardCode
    });
  }

  // General query failed with no AI provider available: return safe HTTP 503 error
  return res.status(503).json({
    success: false,
    error: aiResult.error || "AI_ALL_PROVIDERS_UNAVAILABLE",
    message: aiResult.message || "AI Copilot service is temporarily unavailable. All configured AI providers failed. Please try again shortly.",
    providerErrors: aiResult.providerErrors,
    standardCode: null
  });
});

// =============================================================================
// SAT (Self-Assessment Tool) Endpoints
// Source: Hospital Full Accreditation SAT 2025 Excel Workbook
// =============================================================================

// Scoring map: confirmed from Excel workbook (N/A default, % bar chart)
const SAT_SCORE_WEIGHTS = {
  FULLY_MET:      100,
  PARTIALLY_MET:  50,
  NOT_MET:        0,
  NOT_APPLICABLE: null, // excluded from denominator
  NOT_ASSESSED:   null, // pending — excluded from calculations
};

function satScoreToPercentage(scoreValue) {
  return SAT_SCORE_WEIGHTS[scoreValue] ?? null;
}

// Helper: calculate chapter summary from a list of sat scores + standards
function calculateChapterSummary(standards, scores, excludedStandards = new Set()) {
  const scoreMap = {};
  for (const s of scores) {
    scoreMap[s.standard_code] = s;
  }

  const categoryMap = {};
  for (const std of standards) {
    const cat = std.category;
    if (!categoryMap[cat]) {
      categoryMap[cat] = {
        category: cat,
        category_ar: std.category_ar,
        chapter_code: std.chapter_code,
        total: 0,
        assessed: 0,
        applicable: 0,
        score_sum: 0,
        percentage: 0,
        items: [],
      };
    }
    const sc = scoreMap[std.standard_code];
    let sv = sc?.score_value || 'NOT_ASSESSED';
    if (excludedStandards && excludedStandards.has(std.standard_code)) {
      sv = 'NOT_APPLICABLE';
    }
    const pct = SAT_SCORE_WEIGHTS[sv];
    const entry = { ...std, score_value: sv, score_percentage: pct, notes: sc?.notes || '', is_applicable: sv !== 'NOT_APPLICABLE' };
    categoryMap[cat].items.push(entry);
    categoryMap[cat].total++;
    if (sv !== 'NOT_APPLICABLE' && sv !== 'NOT_ASSESSED') {
      categoryMap[cat].applicable++;
      categoryMap[cat].assessed++;
      categoryMap[cat].score_sum += pct;
    } else if (sv === 'NOT_ASSESSED') {
      // counted but not yet assessed
    }
  }

  const chapters = Object.values(categoryMap).map(ch => ({
    ...ch,
    percentage: ch.applicable > 0
      ? Math.round((ch.score_sum / (ch.applicable * 100)) * 100)
      : 0,
  }));

  return chapters;
}


// GET /api/sat/standards — list all active SAT standards (auth required)
app.get("/api/sat/standards", authenticateToken, async (req, res) => {
  try {
    const chapterFilter = req.query.chapter; // optional ?chapter=GSR
    let standards = [];
    if (checkPg()) {
      const sql = chapterFilter
        ? "SELECT * FROM sat_standards WHERE is_active = true AND chapter_code = $1 ORDER BY sort_order"
        : "SELECT * FROM sat_standards WHERE is_active = true ORDER BY sort_order";
      const params = chapterFilter ? [chapterFilter.toUpperCase()] : [];
      const result = await query(sql, params);
      if (result && result.rows) {
        standards = result.rows;
      }
    }
    
    if (!standards || standards.length === 0) {
      standards = memoryDb.sat_standards || [];
      if (chapterFilter) {
        standards = standards.filter(s => s.chapter_code === chapterFilter.toUpperCase());
      }
    }

    res.json({ success: true, standards, total: standards.length });
  } catch (e) {
    console.error("SAT standards error:", e);
    res.status(500).json({ success: false, message: "Failed to load SAT standards." });
  }
});

// GET /api/sat/scores — get this facility's SAT scores
app.get("/api/sat/scores", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const facilityId = req.user.facilityId;
  try {
    let rows = null;
    if (checkPg()) {
      const result = await query(
        "SELECT * FROM sat_scores WHERE facility_id = $1 ORDER BY standard_code",
        [facilityId]
      );
      if (result && result.rows) {
        rows = result.rows;
      }
    }
    
    if (!rows) {
      rows = (memoryDb.sat_scores || []).filter(s => s.facility_id === facilityId);
    }

    const mapped = rows.map(s => ({
      id: s.id,
      facility_id: s.facility_id,
      standard_code: s.standard_code,
      score_status: s.score_value || s.score_status,
      score_value: s.score_value || s.score_status,
      numeric_score: s.score_percentage ?? s.numeric_score,
      notes: s.notes || '',
      updated_by: s.assessed_by || s.updated_by,
      updated_at: s.updated_at,
      created_at: s.created_at,
    }));

    res.json({ success: true, scores: mapped, total: mapped.length });
  } catch (e) {
    console.error("SAT scores fetch error:", e);
    res.status(500).json({ success: false, message: "Failed to load SAT scores." });
  }
});

// PUT /api/sat/scores/:standardCode — update a single score
app.put("/api/sat/scores/:standardCode", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const facilityId = req.user.facilityId;
  const { standardCode } = req.params;
  const score_value = req.body.score_value || req.body.score_status;
  const { notes } = req.body;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  const allowedValues = Object.keys(SAT_SCORE_WEIGHTS);
  if (!allowedValues.includes(score_value)) {
    return res.status(400).json({
      success: false,
      message: `Invalid score value. Allowed: ${allowedValues.join(', ')}`,
    });
  }

  const scorePercentage = req.body.numeric_score ?? satScoreToPercentage(score_value);
  const now = new Date().toISOString();

  try {
    let savedInPg = false;
    if (checkPg()) {
      const result = await query(
        `INSERT INTO sat_scores
           (facility_id, standard_code, score_value, score_percentage, notes, assessed_by, assessed_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
         ON CONFLICT (facility_id, standard_code)
         DO UPDATE SET
           score_value = EXCLUDED.score_value,
           score_percentage = EXCLUDED.score_percentage,
           notes = EXCLUDED.notes,
           assessed_by = EXCLUDED.assessed_by,
           assessed_at = EXCLUDED.assessed_at,
           updated_at = EXCLUDED.updated_at`,
        [facilityId, standardCode, score_value, scorePercentage, notes || '', req.user.email, now]
      );
      if (result) savedInPg = true;
    }

    if (!savedInPg) {
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to persist score in production database." });
      }
      memoryDb.sat_scores = memoryDb.sat_scores || [];
      const idx = memoryDb.sat_scores.findIndex(
        s => s.facility_id === facilityId && s.standard_code === standardCode
      );
      const entry = {
        id: idx >= 0 ? memoryDb.sat_scores[idx].id : require('crypto').randomUUID(),
        facility_id: facilityId, standard_code: standardCode,
        score_value, score_status: score_value,
        score_percentage: scorePercentage, numeric_score: scorePercentage,
        notes: notes || '', assessed_by: req.user.email,
        assessed_at: now, updated_at: now,
        created_at: idx >= 0 ? memoryDb.sat_scores[idx].created_at : now,
      };
      if (idx >= 0) memoryDb.sat_scores[idx] = entry;
      else memoryDb.sat_scores.push(entry);
    }

    logAuditEvent({
      facilityId, userId: req.user.userId, userEmail: req.user.email,
      action: "SAT_SCORE_UPDATED",
      details: { standardCode, score_value },
      req,
    });

    res.json({ success: true, message: "Score saved successfully." });
  } catch (e) {
    console.error("SAT score update error:", e);
    res.status(500).json({ success: false, message: "Failed to save score." });
  }
});

// POST /api/sat/scores/bulk — batch save multiple scores
app.post("/api/sat/scores/bulk", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const facilityId = req.user.facilityId;
  const { scores } = req.body;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (!Array.isArray(scores) || scores.length === 0) {
    return res.status(400).json({ success: false, message: "scores array is required." });
  }

  const allowedValues = Object.keys(SAT_SCORE_WEIGHTS);
  const now = new Date().toISOString();
  const errors = [];
  const saved = [];

  for (const item of scores) {
    const sv = item.score_value || item.score_status;
    if (!item.standard_code || !allowedValues.includes(sv)) {
      errors.push({ standard_code: item.standard_code, error: "Invalid entry" });
      continue;
    }
    const scorePercentage = item.numeric_score ?? satScoreToPercentage(sv);
    try {
      let savedInPg = false;
      if (checkPg()) {
        const result = await query(
          `INSERT INTO sat_scores
             (facility_id, standard_code, score_value, score_percentage, notes, assessed_by, assessed_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
           ON CONFLICT (facility_id, standard_code)
           DO UPDATE SET
             score_value = EXCLUDED.score_value,
             score_percentage = EXCLUDED.score_percentage,
             notes = EXCLUDED.notes,
             assessed_by = EXCLUDED.assessed_by,
             assessed_at = EXCLUDED.assessed_at,
             updated_at = EXCLUDED.updated_at`,
          [facilityId, item.standard_code, sv, scorePercentage, item.notes || '', req.user.email, now]
        );
        if (result) savedInPg = true;
      }

      if (!savedInPg) {
        if (isProduction) {
          errors.push({ standard_code: item.standard_code, error: "Database unavailable in production" });
          continue;
        }
        memoryDb.sat_scores = memoryDb.sat_scores || [];
        const idx = memoryDb.sat_scores.findIndex(
          s => s.facility_id === facilityId && s.standard_code === item.standard_code
        );
        const entry = {
          id: idx >= 0 ? memoryDb.sat_scores[idx].id : require('crypto').randomUUID(),
          facility_id: facilityId, standard_code: item.standard_code,
          score_value: sv, score_status: sv,
          score_percentage: scorePercentage, numeric_score: scorePercentage,
          notes: item.notes || '', assessed_by: req.user.email,
          assessed_at: now, updated_at: now,
          created_at: idx >= 0 ? memoryDb.sat_scores[idx].created_at : now,
        };
        if (idx >= 0) memoryDb.sat_scores[idx] = entry;
        else memoryDb.sat_scores.push(entry);
      }
      saved.push(item.standard_code);
    } catch (e) {
      errors.push({ standard_code: item.standard_code, error: e.message });
    }
  }

  logAuditEvent({
    facilityId, userId: req.user.userId, userEmail: req.user.email,
    action: "SAT_BULK_SCORES_SAVED",
    details: { savedCount: saved.length, errorCount: errors.length },
    req,
  });

  res.json({ success: true, count: saved.length, saved: saved.length, errors, message: `${saved.length} scores saved.` });
});

// GET /api/sat/summary — chapter-level aggregated scores for this facility
app.get("/api/sat/summary", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const facilityId = req.user.facilityId;
  try {
    let standards = null, scores = null;
    if (checkPg()) {
      const sRes = await query("SELECT * FROM sat_standards WHERE is_active = true ORDER BY sort_order");
      const scRes = await query("SELECT * FROM sat_scores WHERE facility_id = $1", [facilityId]);
      if (sRes && sRes.rows) standards = sRes.rows;
      if (scRes && scRes.rows) scores = scRes.rows;
    }
    
    if (!standards) standards = memoryDb.sat_standards || [];
    if (!scores) scores = (memoryDb.sat_scores || []).filter(s => s.facility_id === facilityId);

    const excluded = await getExcludedStandardsSet(facilityId);
    const chapters = calculateChapterSummary(standards, scores, excluded);
    const totalApplicable = chapters.reduce((sum, c) => sum + c.applicable, 0);
    const totalScoreSum = chapters.reduce((sum, c) => sum + c.score_sum, 0);
    const overallPercentage = totalApplicable > 0
      ? Math.round((totalScoreSum / (totalApplicable * 100)) * 100)
      : 0;
    const totalAssessed = chapters.reduce((sum, c) => sum + c.assessed, 0);
    const totalStandards = standards.length;

    const chapterSummaries = chapters.map(c => ({
      chapter_code: c.chapter_code,
      chapter_title: c.category,
      total_standards: c.total,
      assessed_standards: c.assessed,
      fully_met: c.items.filter(i => (i.score_value || i.score_status) === 'FULLY_MET').length,
      partially_met: c.items.filter(i => (i.score_value || i.score_status) === 'PARTIALLY_MET').length,
      not_met: c.items.filter(i => (i.score_value || i.score_status) === 'NOT_MET').length,
      not_applicable: c.items.filter(i => (i.score_value || i.score_status) === 'NOT_APPLICABLE').length,
      score_percentage: c.percentage,
    }));

    res.json({
      success: true,
      summary: chapterSummaries,
      overall_percentage: overallPercentage,
      total_standards: totalStandards,
      total_assessed: totalAssessed,
      total_applicable: totalApplicable,
      total_not_assessed: totalStandards - totalAssessed,
      chapters,
    });
  } catch (e) {
    console.error("SAT summary error:", e);
    res.status(500).json({ success: false, message: "Failed to generate SAT summary." });
  }
});

// GET /api/sat/report — full SAT report data (for PDF generation)
app.get("/api/sat/report", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const facilityId = req.user.facilityId;
  try {
    let facility = null, standards = null, scores = null;
    if (checkPg()) {
      const fRes = await query("SELECT * FROM facilities WHERE id = $1", [facilityId]);
      const sRes = await query("SELECT * FROM sat_standards WHERE is_active = true ORDER BY sort_order");
      const scRes = await query("SELECT * FROM sat_scores WHERE facility_id = $1 ORDER BY standard_code", [facilityId]);
      if (fRes && fRes.rows) facility = fRes.rows[0];
      if (sRes && sRes.rows) standards = sRes.rows;
      if (scRes && scRes.rows) scores = scRes.rows;
    }
    
    if (!facility) facility = (memoryDb.facilities || []).find(f => f.id === facilityId) || {};
    if (!standards) standards = memoryDb.sat_standards || [];
    if (!scores) scores = (memoryDb.sat_scores || []).filter(s => s.facility_id === facilityId);

    const excluded = await getExcludedStandardsSet(facilityId);
    const chapters = calculateChapterSummary(standards, scores, excluded);
    const totalApplicable = chapters.reduce((sum, c) => sum + c.applicable, 0);
    const totalScoreSum = chapters.reduce((sum, c) => sum + c.score_sum, 0);
    const overallPercentage = totalApplicable > 0
      ? Math.round((totalScoreSum / (totalApplicable * 100)) * 100)
      : 0;
    const totalAssessed = chapters.reduce((sum, c) => sum + c.assessed, 0);

    const chapterSummaries = chapters.map(c => ({
      chapter_code: c.chapter_code,
      chapter_title: c.category,
      total_standards: c.total,
      assessed_standards: c.assessed,
      fully_met: c.items.filter(i => (i.score_value || i.score_status) === 'FULLY_MET').length,
      partially_met: c.items.filter(i => (i.score_value || i.score_status) === 'PARTIALLY_MET').length,
      not_met: c.items.filter(i => (i.score_value || i.score_status) === 'NOT_MET').length,
      not_applicable: c.items.filter(i => (i.score_value || i.score_status) === 'NOT_APPLICABLE').length,
      score_percentage: c.percentage,
    }));

    res.json({
      success: true,
      report: {
        facility_id: facility.id || facilityId,
        facility_name: facility.name || 'Healthcare Facility',
        facility_type: facility.type || '',
        governorate: facility.governorate || '',
        assessment_date: new Date().toISOString(),
        overall_score: overallPercentage,
        overall_percentage: overallPercentage,
        total_standards: standards.length,
        assessed_standards: totalAssessed,
        completion_rate: standards.length > 0 ? (totalAssessed / standards.length) * 100 : 0,
        chapter_summaries: chapterSummaries,
        status_distribution: {
          FULLY_MET: scores.filter(s => (s.score_value || s.score_status) === 'FULLY_MET').length,
          PARTIALLY_MET: scores.filter(s => (s.score_value || s.score_status) === 'PARTIALLY_MET').length,
          NOT_MET: scores.filter(s => (s.score_value || s.score_status) === 'NOT_MET').length,
          NOT_APPLICABLE: scores.filter(s => (s.score_value || s.score_status) === 'NOT_APPLICABLE').length,
          NOT_ASSESSED: standards.length - totalAssessed,
        },
      },
    });
  } catch (e) {
    console.error("SAT report error:", e);
    res.status(500).json({ success: false, message: "Failed to generate SAT report." });
  }
});

// GET /api/admin/sat/platform-summary — Super Admin: aggregated SAT across all facilities
app.get("/api/admin/sat/platform-summary",
  authenticateToken,
  authorizeRoles("SUPER_ADMIN"),
  async (req, res) => {
    try {
      let facilitySummaries = [];
      let totalAssessedRecords = 0;
      let totalFullyMet = 0;
      let totalPartiallyMet = 0;
      let totalNotMet = 0;

      for (const f of (memoryDb.facilities || [])) {
        const fScores = (memoryDb.sat_scores || []).filter(s => s.facility_id === f.id);
        const applicable = fScores.filter(s => !['NOT_APPLICABLE','NOT_ASSESSED'].includes(s.score_value || s.score_status));
        const scoreSum = applicable.reduce((sum, s) => sum + (SAT_SCORE_WEIGHTS[s.score_value || s.score_status] || 0), 0);
        
        totalAssessedRecords += fScores.length;
        totalFullyMet += fScores.filter(s => (s.score_value || s.score_status) === 'FULLY_MET').length;
        totalPartiallyMet += fScores.filter(s => (s.score_value || s.score_status) === 'PARTIALLY_MET').length;
        totalNotMet += fScores.filter(s => (s.score_value || s.score_status) === 'NOT_MET').length;

        facilitySummaries.push({
          facility_id: f.id,
          facility_name: f.name,
          facility_type: f.type,
          governorate: f.governorate,
          assessed_count: fScores.length,
          total_standards: (memoryDb.sat_standards || []).length,
          avg_percentage: applicable.length > 0
            ? Math.round(scoreSum / applicable.length)
            : 0,
        });
      }

      const totalFacilitiesWithSAT = facilitySummaries.filter(f => f.assessed_count > 0).length;
      const platformAvg = facilitySummaries.length > 0
        ? Math.round(facilitySummaries.reduce((sum, f) => sum + (f.avg_percentage || 0), 0) / facilitySummaries.length)
        : 0;

      res.json({
        success: true,
        summary: {
          total_facilities: facilitySummaries.length,
          total_facilities_with_sat: totalFacilitiesWithSAT,
          total_sat_scores_recorded: totalAssessedRecords,
          fully_met_count: totalFullyMet,
          partially_met_count: totalPartiallyMet,
          not_met_count: totalNotMet,
          platform_average_percentage: platformAvg,
          total_standards: (memoryDb.sat_standards || []).length || 29,
          facilities: facilitySummaries,
        },
        platform_summary: {
          total_facilities: facilitySummaries.length,
          facilities_using_sat: totalFacilitiesWithSAT,
          platform_average_percentage: platformAvg,
          facilities: facilitySummaries,
        },
      });
    } catch (e) {
      console.error("Admin SAT platform-summary error:", e);
      res.status(500).json({ success: false, message: "Failed to load platform SAT summary." });
    }
  }
);

// =============================================================================
// SAT Sub-Evidence / Row-Level Scoring Endpoints
// Implements the actual Excel scoring model: 0 / 1 / 2 per evidence row
// Standard Score = SUM(scores) / (COUNT(scored_items) * 2)
// Rating: >= 80% = MET, >= 50% = PARTIAL MET, < 50% = NOT MET, all N/A = N/A
// =============================================================================

// GET /api/sat/sub-evidence/:standardCode — list all evidence rows for a standard
app.get("/api/sat/sub-evidence/:standardCode", authenticateToken, async (req, res) => {
  const { standardCode } = req.params;
  const upperCode = (standardCode || "").trim().toUpperCase();

  try {
    let items = [];
    if (checkPg()) {
      const result = await query(
        `SELECT * 
         FROM sat_sub_evidence 
         WHERE standard_code = $1 
            OR standard_code = (SELECT book_reference_code FROM sat_standards WHERE standard_code = $1 LIMIT 1)
         ORDER BY item_number, sort_order`,
        [upperCode]
      );
      if (result && result.rows) items = result.rows;
    }

    if (!items.length && !isProduction) {
      const gsrMapping = (memoryDb.sat_standards || []).find(s => s.standard_code === upperCode)?.book_reference_code;
      items = (memoryDb.sat_sub_evidence || []).filter(
        e => e.standard_code === upperCode || (gsrMapping && e.standard_code === gsrMapping)
      );
    }

    res.json({ success: true, standard_code: standardCode, evidence_items: items, count: items.length });
  } catch (e) {
    console.error("SAT sub-evidence fetch error:", e);
    res.status(500).json({ success: false, message: "Failed to load sub-evidence items." });
  }
});

// GET /api/sat/sub-scores/:standardCode — get facility's sub-scores for a standard
app.get("/api/sat/sub-scores/:standardCode", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { standardCode } = req.params;
  const facilityId = req.tenantFacilityId;
  try {
    let scores = [];
    if (checkPg()) {
      const result = await query(
        "SELECT * FROM sat_sub_scores WHERE facility_id = $1 AND standard_code = $2 ORDER BY evidence_id",
        [facilityId, standardCode.toUpperCase()]
      );
      if (result && result.rows) scores = result.rows;
    }
    if (!scores.length) {
      scores = (memoryDb.sat_sub_scores || []).filter(
        s => s.facility_id === facilityId && s.standard_code === standardCode.toUpperCase()
      );
    }

    // Calculate standard score from sub-scores using Excel formula
    const calculated = calculateSubEvidenceScore(scores);

    res.json({
      success: true,
      standard_code: standardCode,
      sub_scores: scores,
      calculated_score: calculated,
    });
  } catch (e) {
    console.error("SAT sub-scores fetch error:", e);
    res.status(500).json({ success: false, message: "Failed to load sub-scores." });
  }
});

// PUT /api/sat/sub-scores/:evidenceId — save/update a single sub-evidence score (0/1/2/N/A)
app.put("/api/sat/sub-scores/:evidenceId", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { evidenceId } = req.params;
  const facilityId = req.tenantFacilityId;
  const { score_value, standard_code, notes } = req.body;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (!['0', '1', '2', 'N/A'].includes(String(score_value))) {
    return res.status(400).json({ success: false, message: "score_value must be '0', '1', '2', or 'N/A'." });
  }
  if (!standard_code) {
    return res.status(400).json({ success: false, message: "standard_code is required." });
  }

  try {
    if (checkPg()) {
      await query(`
        INSERT INTO sat_sub_scores (facility_id, evidence_id, standard_code, score_value, notes, updated_at)
        VALUES ($1, $2, $3, $4, $5, NOW())
        ON CONFLICT (facility_id, evidence_id)
        DO UPDATE SET score_value = $4, notes = $5, updated_at = NOW();
      `, [facilityId, evidenceId, standard_code.toUpperCase(), String(score_value), notes || null]);
    } else {
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Database service unavailable in production." });
      }
      if (!memoryDb.sat_sub_scores) memoryDb.sat_sub_scores = [];
      const existingIdx = memoryDb.sat_sub_scores.findIndex(
        s => s.facility_id === facilityId && s.evidence_id === evidenceId
      );
      const record = { facility_id: facilityId, evidence_id: evidenceId, standard_code: standard_code.toUpperCase(), score_value: String(score_value), notes: notes || null, updated_at: new Date().toISOString() };
      if (existingIdx >= 0) {
        memoryDb.sat_sub_scores[existingIdx] = record;
      } else {
        memoryDb.sat_sub_scores.push(record);
      }
    }

    logAuditEvent({ facilityId, userId: req.user.userId, userEmail: req.user.email, action: "SAT_SUB_SCORE_SAVED", details: { evidenceId, score_value, standard_code }, req });
    res.json({ success: true, evidence_id: evidenceId, score_value, message: "Sub-evidence score saved." });
  } catch (e) {
    console.error("SAT sub-score save error:", e);
    res.status(500).json({ success: false, message: "Failed to save sub-evidence score." });
  }
});

// POST /api/sat/sub-scores/bulk — bulk save multiple sub-evidence scores
app.post("/api/sat/sub-scores/bulk", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const facilityId = req.tenantFacilityId;
  const { scores } = req.body;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  if (!Array.isArray(scores) || scores.length === 0) {
    return res.status(400).json({ success: false, message: "scores must be a non-empty array." });
  }

  const saved = [];
  const errors = [];

  for (const item of scores) {
    const { evidence_id, standard_code, score_value, notes } = item;
    if (!['0', '1', '2', 'N/A'].includes(String(score_value)) || !evidence_id || !standard_code) {
      errors.push({ evidence_id, error: "Invalid score_value or missing fields." });
      continue;
    }
    try {
      if (checkPg()) {
        await query(`
          INSERT INTO sat_sub_scores (facility_id, evidence_id, standard_code, score_value, notes, updated_at)
          VALUES ($1, $2, $3, $4, $5, NOW())
          ON CONFLICT (facility_id, evidence_id)
          DO UPDATE SET score_value = $4, notes = $5, updated_at = NOW();
        `, [facilityId, evidence_id, standard_code.toUpperCase(), String(score_value), notes || null]);
      } else {
        if (isProduction) {
          errors.push({ evidence_id, error: "Database unavailable in production" });
          continue;
        }
        if (!memoryDb.sat_sub_scores) memoryDb.sat_sub_scores = [];
        const idx = memoryDb.sat_sub_scores.findIndex(s => s.facility_id === facilityId && s.evidence_id === evidence_id);
        const record = { facility_id: facilityId, evidence_id, standard_code: standard_code.toUpperCase(), score_value: String(score_value), notes: notes || null, updated_at: new Date().toISOString() };
        if (idx >= 0) memoryDb.sat_sub_scores[idx] = record;
        else memoryDb.sat_sub_scores.push(record);
      }
      saved.push(evidence_id);
    } catch (e) {
      errors.push({ evidence_id, error: e.message });
    }
  }

  logAuditEvent({ facilityId, userId: req.user.userId, userEmail: req.user.email, action: "SAT_SUB_SCORES_BULK_SAVED", details: { saved: saved.length, errors: errors.length }, req });
  res.json({ success: true, saved: saved.length, errors, message: `${saved.length} sub-scores saved.` });
});

// GET /api/sat/sub-scores/standard-calculation/:standardCode — calculate a standard's score from its sub-evidence
app.get("/api/sat/sub-scores/standard-calculation/:standardCode", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { standardCode } = req.params;
  const facilityId = req.tenantFacilityId;
  try {
    let scores = [];
    if (checkPg()) {
      const result = await query(
        "SELECT * FROM sat_sub_scores WHERE facility_id = $1 AND standard_code = $2",
        [facilityId, standardCode.toUpperCase()]
      );
      if (result && result.rows) scores = result.rows;
    } else {
      scores = (memoryDb.sat_sub_scores || []).filter(
        s => s.facility_id === facilityId && s.standard_code === standardCode.toUpperCase()
      );
    }
    const calculated = calculateSubEvidenceScore(scores);
    res.json({ success: true, standard_code: standardCode, ...calculated });
  } catch (e) {
    console.error("Standard calculation error:", e);
    res.status(500).json({ success: false, message: "Failed to calculate standard score." });
  }
});

// Helper: Calculate standard score from sub-evidence scores (exact Excel formula)
// Score = SUM(scores) / (COUNT(scored_items) * 2)
// N/A items excluded from denominator
// Rating: >= 0.80 = MET, >= 0.50 = PARTIAL MET, < 0.50 = NOT MET
function calculateSubEvidenceScore(subScores) {
  const scorable = subScores.filter(s => s.score_value !== 'N/A');
  if (scorable.length === 0) {
    return { percentage: null, percentage_display: 'N/A', rating: 'N/A', scored_items: 0, total_items: subScores.length };
  }
  const total = scorable.reduce((sum, s) => sum + parseInt(s.score_value || 0, 10), 0);
  const maxPossible = scorable.length * 2;
  const percentage = maxPossible > 0 ? total / maxPossible : 0;
  const percentageRounded = Math.round(percentage * 100);
  let rating;
  if (percentage >= 0.80) rating = 'MET';
  else if (percentage >= 0.50) rating = 'PARTIAL MET';
  else rating = 'NOT MET';

  return {
    percentage: percentageRounded,
    percentage_display: `${percentageRounded}%`,
    rating,
    scored_items: scorable.length,
    total_items: subScores.length,
    sum_scores: total,
    max_possible: maxPossible,
  };
}

// =============================================================================
// Trash / Recycle Bin API (Tenant-Isolated, RBAC-Enforced)
// =============================================================================

// Helper: resolve the backing array for a trash entry
function _trashBackingArray(itemType) {
  switch (itemType) {
    case 'document':    return memoryDb.documents;
    case 'gap':         return memoryDb.gaps;
    case 'action_plan': return memoryDb.action_plans;
    case 'license':     return memoryDb.licenses;
    default:            return null;
  }
}

// GET /api/trash — list all trashed items for the authenticated tenant
app.get("/api/trash", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  const { type, search, from, to } = req.query;

  if (checkPg()) {
    try {
      let sql = 'SELECT * FROM trash WHERE facility_id = $1';
      const params = [req.tenantFacilityId];

      if (type) {
        params.push(type);
        sql += ` AND item_type = $${params.length}`;
      }
      if (search) {
        params.push(`%${search.toLowerCase()}%`);
        sql += ` AND LOWER(item_name) LIKE $${params.length}`;
      }
      if (from) {
        params.push(from);
        sql += ` AND deleted_at >= $${params.length}`;
      }
      if (to) {
        params.push(to);
        sql += ` AND deleted_at <= $${params.length}`;
      }

      sql += ' ORDER BY deleted_at DESC';
      const tRes = await query(sql, params);
      if (tRes && tRes.rows) {
        return res.json({ success: true, trash: tRes.rows, total: tRes.rows.length });
      }
    } catch (err) {
      console.error("Error querying trash from DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to load trash items from database." });
      }
    }
  }

  let items = memoryDb.trash.filter(t => t.facility_id === req.tenantFacilityId);

  if (type) items = items.filter(t => t.item_type === type);
  if (search) {
    const q = search.toLowerCase();
    items = items.filter(t => (t.item_name || '').toLowerCase().includes(q));
  }
  if (from) items = items.filter(t => new Date(t.deleted_at) >= new Date(from));
  if (to)   items = items.filter(t => new Date(t.deleted_at) <= new Date(to));

  items = [...items].sort((a, b) => new Date(b.deleted_at) - new Date(a.deleted_at));
  res.json({ success: true, trash: items, total: items.length });
});

// POST /api/trash/:id/restore — restore a trashed item back to its module
app.post("/api/trash/:id/restore", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { id } = req.params;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let restoredEntry = null;

  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        const tRes = await client.query('SELECT * FROM trash WHERE id = $1 AND facility_id = $2', [id, req.tenantFacilityId]);
        if (tRes.rows.length === 0) return;
        restoredEntry = tRes.rows[0];

        switch (restoredEntry.item_type) {
          case 'gap':
            await client.query('UPDATE gaps SET deleted_at = NULL, deleted_by = NULL WHERE id = $1 AND facility_id = $2', [restoredEntry.item_id, req.tenantFacilityId]);
            break;
          case 'action_plan':
            await client.query('UPDATE action_plans SET deleted_at = NULL, deleted_by = NULL WHERE id = $1 AND facility_id = $2', [restoredEntry.item_id, req.tenantFacilityId]);
            break;
          case 'license':
            await client.query('UPDATE licenses SET deleted_at = NULL, deleted_by = NULL WHERE id = $1 AND facility_id = $2', [restoredEntry.item_id, req.tenantFacilityId]);
            break;
          case 'document':
            await client.query('UPDATE documents SET deleted_at = NULL, deleted_by = NULL WHERE id = $1 AND facility_id = $2', [restoredEntry.item_id, req.tenantFacilityId]);
            break;
        }

        await client.query('DELETE FROM trash WHERE id = $1 AND facility_id = $2', [id, req.tenantFacilityId]);
      });
    } catch (err) {
      console.error("Error restoring trash item in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to restore item in database." });
      }
    }
  }

  const trashIndex = memoryDb.trash.findIndex(t => t.id === id && t.facility_id === req.tenantFacilityId);
  let memTrashEntry = null;
  if (trashIndex !== -1) {
    memTrashEntry = memoryDb.trash[trashIndex];
    const backingArray = _trashBackingArray(memTrashEntry.item_type);
    if (backingArray) {
      const record = backingArray.find(r => r.id === memTrashEntry.item_id && (r.facility_id === req.tenantFacilityId || r.facilityId === req.tenantFacilityId));
      if (record) {
        delete record.deleted_at;
        delete record.deleted_by;
      }
    }
    memoryDb.trash.splice(trashIndex, 1);
  }

  const entry = restoredEntry || memTrashEntry;
  if (!entry) {
    return res.status(404).json({ success: false, message: "Trash item not found or already restored." });
  }

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: `${entry.item_type.toUpperCase()}_RESTORED_FROM_TRASH`,
    entityType: entry.item_type,
    entityId: entry.item_id,
    details: { name: entry.item_name },
    req
  });

  res.json({ success: true, message: `${entry.item_name} restored successfully.`, itemType: entry.item_type, module: entry.module });
});

// POST /api/trash/restore-all — restore all trashed items for this facility
app.post("/api/trash/restore-all", authenticateToken, enforceTenantIsolation, async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let dbRestoredCount = 0;
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        const tRes = await client.query('SELECT * FROM trash WHERE facility_id = $1', [req.tenantFacilityId]);
        for (const item of tRes.rows) {
          switch (item.item_type) {
            case 'gap':
              await client.query('UPDATE gaps SET deleted_at = NULL, deleted_by = NULL WHERE id = $1 AND facility_id = $2', [item.item_id, req.tenantFacilityId]);
              break;
            case 'action_plan':
              await client.query('UPDATE action_plans SET deleted_at = NULL, deleted_by = NULL WHERE id = $1 AND facility_id = $2', [item.item_id, req.tenantFacilityId]);
              break;
            case 'license':
              await client.query('UPDATE licenses SET deleted_at = NULL, deleted_by = NULL WHERE id = $1 AND facility_id = $2', [item.item_id, req.tenantFacilityId]);
              break;
            case 'document':
              await client.query('UPDATE documents SET deleted_at = NULL, deleted_by = NULL WHERE id = $1 AND facility_id = $2', [item.item_id, req.tenantFacilityId]);
              break;
          }
          dbRestoredCount++;
        }
        await client.query('DELETE FROM trash WHERE facility_id = $1', [req.tenantFacilityId]);
      });
    } catch (err) {
      console.error("Error restoring all trash in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to restore all items in database." });
      }
    }
  }

  const facilityTrash = memoryDb.trash.filter(t => t.facility_id === req.tenantFacilityId);
  let memRestoredCount = 0;
  for (const trashEntry of facilityTrash) {
    const backingArray = _trashBackingArray(trashEntry.item_type);
    if (backingArray) {
      const record = backingArray.find(r => r.id === trashEntry.item_id && (r.facility_id === req.tenantFacilityId || r.facilityId === req.tenantFacilityId));
      if (record) {
        delete record.deleted_at;
        delete record.deleted_by;
      }
    }
    memRestoredCount++;
  }
  memoryDb.trash = memoryDb.trash.filter(t => t.facility_id !== req.tenantFacilityId);

  const restoredCount = checkPg() ? dbRestoredCount : memRestoredCount;
  if (restoredCount === 0 && !checkPg() && facilityTrash.length === 0) {
    return res.json({ success: true, message: "Trash is already empty.", restoredCount: 0 });
  }

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: "ALL_ITEMS_RESTORED_FROM_TRASH",
    details: { restoredCount },
    req
  });

  res.json({ success: true, message: `${restoredCount} item(s) restored successfully.`, restoredCount });
});

// DELETE /api/trash/:id/permanent — permanently delete a single trash item
app.delete("/api/trash/:id/permanent", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  const { id } = req.params;

  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let permEntry = null;
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        const tRes = await client.query('SELECT * FROM trash WHERE id = $1 AND facility_id = $2', [id, req.tenantFacilityId]);
        if (tRes.rows.length === 0) return;
        permEntry = tRes.rows[0];

        switch (permEntry.item_type) {
          case 'gap':
            await client.query('DELETE FROM gaps WHERE id = $1 AND facility_id = $2', [permEntry.item_id, req.tenantFacilityId]);
            break;
          case 'action_plan':
            await client.query('DELETE FROM action_plans WHERE id = $1 AND facility_id = $2', [permEntry.item_id, req.tenantFacilityId]);
            break;
          case 'license':
            await client.query('DELETE FROM licenses WHERE id = $1 AND facility_id = $2', [permEntry.item_id, req.tenantFacilityId]);
            break;
          case 'document': {
            const dRow = await client.query('SELECT * FROM documents WHERE id = $1 AND facility_id = $2', [permEntry.item_id, req.tenantFacilityId]);
            if (dRow && dRow.rows.length > 0) {
              const sPath = dRow.rows[0].storage_path || dRow.rows[0].file_path;
              if (sPath) {
                try { await deleteDocumentFile({ facilityId: req.tenantFacilityId, storagePath: sPath }); } catch (_) {}
              }
            }
            await client.query('DELETE FROM documents WHERE id = $1 AND facility_id = $2', [permEntry.item_id, req.tenantFacilityId]);
            break;
          }
        }

        await client.query('DELETE FROM trash WHERE id = $1 AND facility_id = $2', [id, req.tenantFacilityId]);
      });
    } catch (err) {
      console.error("Error permanently deleting trash item in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to permanently delete item in database." });
      }
    }
  }

  const trashIndex = memoryDb.trash.findIndex(t => t.id === id && t.facility_id === req.tenantFacilityId);
  let memTrashEntry = null;
  if (trashIndex !== -1) {
    memTrashEntry = memoryDb.trash[trashIndex];
    const backingArray = _trashBackingArray(memTrashEntry.item_type);
    if (backingArray) {
      const recIdx = backingArray.findIndex(r => r.id === memTrashEntry.item_id);
      if (recIdx !== -1) {
        const rec = backingArray[recIdx];
        if (memTrashEntry.item_type === 'document' && (rec.storagePath || rec.file_path)) {
          try { await deleteDocumentFile({ facilityId: req.tenantFacilityId, storagePath: rec.storagePath || rec.file_path }); } catch (_) {}
        }
        backingArray.splice(recIdx, 1);
      }
    }
    memoryDb.trash.splice(trashIndex, 1);
  }

  const entry = permEntry || memTrashEntry;
  if (!entry) {
    return res.status(404).json({ success: false, message: "Trash item not found." });
  }

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: `${entry.item_type.toUpperCase()}_PERMANENTLY_DELETED`,
    entityType: entry.item_type,
    entityId: entry.item_id,
    details: { name: entry.item_name },
    req
  });

  res.json({ success: true, message: `${entry.item_name} permanently deleted.` });
});

// DELETE /api/trash/empty — permanently delete all trash for this facility
app.delete("/api/trash/empty", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  if (isProduction && !checkPg()) {
    return res.status(503).json({ success: false, message: "Database service unavailable in production." });
  }

  let dbDeletedCount = 0;
  if (checkPg()) {
    try {
      await withTransaction(async (client) => {
        const tRes = await client.query('SELECT * FROM trash WHERE facility_id = $1', [req.tenantFacilityId]);
        for (const item of tRes.rows) {
          switch (item.item_type) {
            case 'gap':
              await client.query('DELETE FROM gaps WHERE id = $1 AND facility_id = $2', [item.item_id, req.tenantFacilityId]);
              break;
            case 'action_plan':
              await client.query('DELETE FROM action_plans WHERE id = $1 AND facility_id = $2', [item.item_id, req.tenantFacilityId]);
              break;
            case 'license':
              await client.query('DELETE FROM licenses WHERE id = $1 AND facility_id = $2', [item.item_id, req.tenantFacilityId]);
              break;
            case 'document': {
              const dRow = await client.query('SELECT * FROM documents WHERE id = $1 AND facility_id = $2', [item.item_id, req.tenantFacilityId]);
              if (dRow && dRow.rows.length > 0) {
                const sPath = dRow.rows[0].storage_path || dRow.rows[0].file_path;
                if (sPath) {
                  try { await deleteDocumentFile({ facilityId: req.tenantFacilityId, storagePath: sPath }); } catch (_) {}
                }
              }
              await client.query('DELETE FROM documents WHERE id = $1 AND facility_id = $2', [item.item_id, req.tenantFacilityId]);
              break;
            }
          }
          dbDeletedCount++;
        }
        await client.query('DELETE FROM trash WHERE facility_id = $1', [req.tenantFacilityId]);
      });
    } catch (err) {
      console.error("Error emptying trash in DB:", err.message);
      if (isProduction) {
        return res.status(500).json({ success: false, message: "Failed to empty trash in database." });
      }
    }
  }

  const facilityTrash = memoryDb.trash.filter(t => t.facility_id === req.tenantFacilityId);
  let memDeletedCount = 0;
  for (const trashEntry of facilityTrash) {
    const backingArray = _trashBackingArray(trashEntry.item_type);
    if (backingArray) {
      const recIdx = backingArray.findIndex(r => r.id === trashEntry.item_id);
      if (recIdx !== -1) {
        const rec = backingArray[recIdx];
        if (trashEntry.item_type === 'document' && rec.storagePath) {
          try { await deleteDocumentFile({ facilityId: req.tenantFacilityId, storagePath: rec.storagePath }); } catch (_) {}
        }
        backingArray.splice(recIdx, 1);
      }
    }
    memDeletedCount++;
  }
  memoryDb.trash = memoryDb.trash.filter(t => t.facility_id !== req.tenantFacilityId);

  const deletedCount = checkPg() ? dbDeletedCount : memDeletedCount;
  if (deletedCount === 0 && !checkPg() && facilityTrash.length === 0) {
    return res.json({ success: true, message: "Trash is already empty.", deletedCount: 0 });
  }

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: "TRASH_EMPTIED",
    details: { deletedCount },
    req
  });

  res.json({ success: true, message: `Trash emptied — ${deletedCount} item(s) permanently deleted.`, deletedCount });
});


// =============================================================================
// API Catch-All 404 and Error Middleware (Strict JSON - Never HTML)
// =============================================================================

app.use("/api/*", (req, res) => {
  res.status(404).json({
    success: false,
    error: "NOT_FOUND",
    message: `API endpoint ${req.method} ${req.originalUrl} not found.`,
    code: 404,
  });
});

app.use((err, req, res, next) => {
  console.error("Unhandled API Error:", err);
  if (res.headersSent) return next(err);
  const status = err.status || err.statusCode || 500;
  res.status(status).json({
    success: false,
    error: err.name || "SERVER_ERROR",
    message: err.message || "An unexpected server error occurred.",
    code: status,
  });
});

// =============================================================================
// Start Backend Server & Graceful Shutdown
const rawPort = process.env.PORT;
const PORT = (rawPort && rawPort.trim() !== "") ? parseInt(rawPort.trim(), 10) : (isProduction ? 10000 : 3000);

let server = null;
if (require.main === module) {
  (async () => {
    try {
      console.log("⏳ Initializing database connection...");
      const dbInitResult = await initializeDatabase();

      if (isProduction && (!dbInitResult || !dbInitResult.connected || !isDbConnected())) {
        console.error("❌ FATAL: Database initialization failed in production mode. Refusing to start server in memory fallback mode.");
        process.exit(1);
      }

      server = app.listen(PORT, "0.0.0.0", async () => {
        console.log(`🚀 GAHAR Healthcare Accreditation Platform — Backend Server running on port ${PORT}`);
        
        // Asynchronous non-blocking startup checks
        try {
          await ensureSuperAdminProvisioned();
        } catch (err) {
          console.warn("⚠️ Super Admin startup provisioning check error:", err.message);
        }

        try {
          await verifySmtpConnection();
        } catch (err) {
          console.warn("⚠️ SMTP startup verification error:", err.message);
        }
      });
    } catch (err) {
      const sanitized = (err && err.message) ? err.message.replace(/:\/\/[^:]+:[^@]+@/, "://***:***@") : "Unknown database error";
      console.error("❌ FATAL: Startup database initialization encountered an error:", sanitized);
      if (isProduction) {
        process.exit(1);
      } else {
        console.warn("⚠️ Proceeding with in-memory store in development mode.");
        server = app.listen(PORT, "0.0.0.0", async () => {
          console.log(`🚀 GAHAR Healthcare Accreditation Platform — Backend Server running on port ${PORT} (dev fallback)`);
        });
      }
    }
  })();

  function handleShutdown(signal) {
    console.log(`\n🛑 Received ${signal}. Starting graceful shutdown...`);
    if (server) {
      server.close(async () => {
        try {
          if (pool) {
            await pool.end();
            console.log("🔌 PostgreSQL connection pool terminated cleanly.");
          }
        } catch (err) {
          console.error("Error closing PostgreSQL pool:", err.message);
        }
        console.log("👋 GAHAR Backend Server terminated gracefully.");
        process.exit(0);
      });
    } else {
      process.exit(0);
    }

    // Force close if graceful shutdown hangs
    setTimeout(() => {
      console.error("⚠️ Forcefully terminating server after shutdown timeout.");
      process.exit(1);
    }, 10000);
  }

  process.on("SIGTERM", () => handleShutdown("SIGTERM"));
  process.on("SIGINT", () => handleShutdown("SIGINT"));
}

// Export app directly for Vercel serverless functions, while preserving named properties for test harnesses
module.exports = app;
module.exports.app = app;
module.exports.server = server;
module.exports.initializeDatabase = initializeDatabase;