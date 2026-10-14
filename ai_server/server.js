const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const fs = require("fs");
const crypto = require("crypto");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcryptjs");
const { v4: uuidv4 } = require("uuid");
require("dotenv").config();

const { query, memoryDb, isPgConnected, isProduction } = require("./db");
const { 
  sendFacilityRegistrationNotification, 
  sendRegistrationReceivedNotification,
  sendPaymentVerificationNotification, 
  sendFacilityStatusNotification,
  sendSubscriptionActivatedNotification,
  sendSubscriptionExpirationReminder,
  sendPasswordResetNotification
} = require("./email_service");
const { logAuditEvent } = require("./audit_service");
const {
  uploadDocument,
  getDocumentBuffer,
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

const { OpenAI } = require("openai");
const openai = process.env.OPENAI_API_KEY ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY }) : null;

const { GoogleGenerativeAI } = require("@google/generative-ai");
const genAI = process.env.GEMINI_API_KEY ? new GoogleGenerativeAI(process.env.GEMINI_API_KEY) : null;

const Groq = require("groq-sdk");
const groq = process.env.GROQ_API_KEY ? new Groq({ apiKey: process.env.GROQ_API_KEY }) : null;

const app = express();
app.use(helmet({
  crossOriginResourcePolicy: { policy: "cross-origin" },
}));
app.use(cors({
  origin: true, // Allow all origins in dev; restrict to gahar-platform.eg in production
  methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization", "X-Facility-Id"],
  credentials: true,
}));
app.use(express.json({ limit: "20mb" }));

// =============================================================================
// Health Check Endpoint (Platform liveness and readiness probe)
// =============================================================================
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "ok",
    timestamp: new Date().toISOString(),
    service: "GAHAR Accreditation Platform API",
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
    return res.status(401).json({ success: false, message: "Authentication token required." });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ success: false, message: "Invalid or expired session token." });
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
app.post("/api/auth/super-admin/login", async (req, res) => {
  const { email, password } = req.body || {};
  console.log(`🔑 Super Admin Login Attempt: ${email}`);

  if (!email || !password) {
    return res.status(400).json({ success: false, message: "Email and password are required." });
  }

  const isSuperAdminEmail = email && (
    email.toLowerCase() === SUPER_ADMIN_EMAIL.toLowerCase() || 
    email.toLowerCase() === 'superadmin@gahar.gov.eg' || 
    email.toLowerCase() === 'admin@gahar-platform.eg' ||
    email.toLowerCase() === 'admin@accredigo.eg' ||
    email.toLowerCase() === 'gahar2005@gmail.com' ||
    email.toLowerCase().includes('superadmin') ||
    email.toLowerCase().includes('gahar')
  );

  const expectedSuperAdminPassword = process.env.SUPER_ADMIN_PASSWORD || (isProduction ? null : "SuperAdmin@2026!");
  const isValidSuperAdminPassword = expectedSuperAdminPassword ? password === expectedSuperAdminPassword : false;

  if (isSuperAdminEmail && isValidSuperAdminPassword) {
    const token = jwt.sign(
      { 
        userId: "00000000-0000-0000-0000-000000000001", 
        email, 
        role: "SUPER_ADMIN", 
        facilityId: null 
      },
      JWT_SECRET,
      { expiresIn: "24h" }
    );

    logAuditEvent({ userEmail: email, action: "SUPER_ADMIN_LOGIN", req });

    return res.json({
      success: true,
      token,
      user: {
        id: "00000000-0000-0000-0000-000000000001",
        email,
        fullName: "Platform Super Admin",
        role: "SUPER_ADMIN",
        facilityId: null,
      }
    });
  }

  logAuditEvent({ userEmail: email, action: "SUPER_ADMIN_LOGIN_FAILED", req });
  return res.status(401).json({ success: false, message: "Invalid Super Admin credentials." });
});

// 2. Facility User Login
app.post("/api/auth/login", async (req, res) => {
  const { email, password } = req.body || {};
  console.log(`🔐 Facility Login Attempt: ${email}`);

  if (!email || !password) {
    return res.status(400).json({ success: false, message: "Email and password are required." });
  }

  const isSuperAdminEmail = email && (
    email.toLowerCase() === SUPER_ADMIN_EMAIL.toLowerCase() || 
    email.toLowerCase() === 'superadmin@gahar.gov.eg' || 
    email.toLowerCase() === 'admin@gahar-platform.eg' ||
    email.toLowerCase() === 'admin@accredigo.eg'
  );

  let user = memoryDb.users.find(u => u.email.toLowerCase() === email.toLowerCase());

  if (!user && isSuperAdminEmail) {
    return res.status(400).json({ success: false, message: "Please use Super Admin Portal login." });
  }

  if (!user) {
    logAuditEvent({ userEmail: email, action: "USER_LOGIN_FAILED_NOT_FOUND", req });
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

  let facility = memoryDb.facilities.find(f => f.id === user.facility_id);
  if (!facility) {
    facility = memoryDb.facilities[0];
  }

  const token = jwt.sign(
    { 
      userId: user.id, 
      email: user.email, 
      role: user.role, 
      facilityId: user.facility_id 
    },
    JWT_SECRET,
    { expiresIn: "24h" }
  );

  logAuditEvent({ facilityId: user.facility_id, userId: user.id, userEmail: user.email, action: "USER_LOGIN_SUCCESS", req });

  res.json({
    success: true,
    token,
    user: {
      id: user.id,
      email: user.email,
      fullName: user.full_name,
      role: user.role,
      facilityId: user.facility_id,
    },
    facility: {
      id: facility.id,
      name: facility.name,
      status: facility.status,
      subscriptionPlan: facility.subscription_plan_id,
    }
  });
});

// 3. Facility Registration (Production Safe: No false auto-activation)
app.post("/api/auth/register-facility", async (req, res) => {
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
  } = req.body;

  console.log(`🏥 New Facility Onboarding Request: ${facilityName} (${workEmail})`);

  const facilityId = `fac_${uuidv4()}`;
  const userId = `usr_${uuidv4()}`;

  // Production requirement: Online Gateway without verified merchant webhook CANNOT auto-activate
  const initialStatus = paymentMethod === "Online Gateway" ? "PENDING_PAYMENT" : "PENDING_REVIEW";

  const newFacility = {
    id: facilityId,
    name: facilityName,
    type: facilityType || "Hospital",
    governorate: governorate || "Cairo",
    address: address || "",
    bed_capacity: parseInt(bedCapacity || "100", 10),
    contact_person: contactPerson,
    work_email: workEmail,
    phone: phone,
    gahar_version: "GAHAR 2025 v2",
    status: initialStatus,
    subscription_plan_id: subscriptionPlanId || "plan_standard",
    created_at: new Date().toISOString()
  };

  const newUser = {
    id: userId,
    email: workEmail,
    password_hash: bcrypt.hashSync(password || "Hospital@2026", 10),
    full_name: contactPerson,
    role: "FACILITY_ADMIN",
    facility_id: facilityId,
    is_active: true,
    created_at: new Date().toISOString()
  };

  memoryDb.facilities.unshift(newFacility);
  memoryDb.users.unshift(newUser);

  if (paymentReference) {
    memoryDb.payments.unshift({
      id: `pay_${uuidv4()}`,
      facility_id: facilityId,
      plan_id: subscriptionPlanId,
      amount: subscriptionPlanId === "plan_enterprise" ? 120000 : 45000,
      payment_method: paymentMethod,
      status: "PENDING_VERIFICATION",
      transaction_ref: paymentReference,
      created_at: new Date().toISOString()
    });
  }

  // Automated notification emails
  await sendFacilityRegistrationNotification({
    name: facilityName,
    type: facilityType,
    governorate,
    bedCapacity,
    contactPerson,
    workEmail,
    phone,
    subscriptionPlanId,
    paymentMethod,
    status: initialStatus
  });

  await sendRegistrationReceivedNotification(workEmail, facilityName);

  logAuditEvent({ facilityId, userId, userEmail: workEmail, action: "FACILITY_REGISTRATION_SUBMITTED", details: { status: initialStatus, paymentMethod }, req });

  const token = jwt.sign(
    { userId, email: workEmail, role: "FACILITY_ADMIN", facilityId },
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
      email: workEmail,
      fullName: contactPerson,
      role: "FACILITY_ADMIN",
      facilityId
    }
  });
});

// 4. Password Reset - Forgot Password
app.post("/api/auth/forgot-password", async (req, res) => {
  const { email } = req.body;
  if (!email) {
    return res.status(400).json({ success: false, message: "Email is required." });
  }

  const rawToken = crypto.randomBytes(32).toString("hex");
  const tokenHash = crypto.createHash("sha256").update(rawToken).digest("hex");
  const expiresAt = new Date(Date.now() + 3600 * 1000); // 1 hour

  const resetRecord = {
    id: uuidv4(),
    email: email.toLowerCase(),
    token_hash: tokenHash,
    expires_at: expiresAt.toISOString(),
    used: false,
    created_at: new Date().toISOString()
  };

  memoryDb.password_resets.push(resetRecord);

  // Send reset email if user exists
  const user = memoryDb.users.find(u => u.email.toLowerCase() === email.toLowerCase());
  if (user) {
    await sendPasswordResetNotification(email, rawToken);
    logAuditEvent({ userEmail: email, action: "PASSWORD_RESET_REQUESTED", req });
  }

  // Always return safe generic message to prevent email enumeration
  res.json({
    success: true,
    message: "If an account exists with this email address, a password reset link has been dispatched."
  });
});

// 5. Password Reset - Reset Password
app.post("/api/auth/reset-password", async (req, res) => {
  const { token, newPassword } = req.body;
  if (!token || !newPassword) {
    return res.status(400).json({ success: false, message: "Token and new password are required." });
  }

  if (newPassword.length < 8) {
    return res.status(400).json({ success: false, message: "Password must be at least 8 characters long." });
  }

  const tokenHash = crypto.createHash("sha256").update(token).digest("hex");
  const record = memoryDb.password_resets.find(r => r.token_hash === tokenHash && !r.used);

  if (!record || new Date(record.expires_at) < new Date()) {
    return res.status(400).json({ success: false, message: "Invalid or expired password reset token." });
  }

  const user = memoryDb.users.find(u => u.email.toLowerCase() === record.email.toLowerCase());
  if (!user) {
    return res.status(404).json({ success: false, message: "User account associated with this token was not found." });
  }

  user.password_hash = bcrypt.hashSync(newPassword, 10);
  record.used = true;

  logAuditEvent({ userId: user.id, userEmail: user.email, action: "PASSWORD_RESET_COMPLETED", req });

  res.json({
    success: true,
    message: "Your password has been successfully updated. You may now log in with your new password."
  });
});

// 6. Session Refresh Token
app.post("/api/auth/refresh-token", authenticateToken, (req, res) => {
  const refreshedToken = jwt.sign(
    { 
      userId: req.user.userId, 
      email: req.user.email, 
      role: req.user.role, 
      facilityId: req.user.facilityId 
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
app.get("/api/users", authenticateToken, enforceTenantIsolation, (req, res) => {
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
app.post("/api/users", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), (req, res) => {
  const { email, fullName, role, department, phone, password } = req.body;

  if (!email || !fullName) {
    return res.status(400).json({ success: false, message: "Email and full name are required." });
  }

  const allowedRoles = ["FACILITY_ADMIN", "QUALITY_MANAGER", "STAFF", "EXPERT"];
  const targetRole = allowedRoles.includes(role) ? role : "STAFF";

  const existing = memoryDb.users.find(u => u.email.toLowerCase() === email.toLowerCase());
  if (existing) {
    return res.status(400).json({ success: false, message: "A user with this email address already exists." });
  }

  const newUser = {
    id: `usr_${uuidv4()}`,
    email: email.toLowerCase(),
    password_hash: bcrypt.hashSync(password || "Staff@2026", 10),
    full_name: fullName,
    role: targetRole,
    facility_id: req.tenantFacilityId,
    department: department || "General Quality",
    phone: phone || "",
    is_active: true,
    created_at: new Date().toISOString()
  };

  memoryDb.users.push(newUser);
  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "FACILITY_USER_CREATED", details: { newUserId: newUser.id, role: targetRole }, req });

  res.status(201).json({
    success: true,
    message: "User created successfully.",
    user: {
      id: newUser.id,
      email: newUser.email,
      fullName: newUser.full_name,
      role: newUser.role,
      department: newUser.department,
      isActive: newUser.is_active
    }
  });
});

// Update facility user details
app.put("/api/users/:id", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), (req, res) => {
  const { id } = req.params;
  const { fullName, department, phone } = req.body;

  const user = memoryDb.users.find(u => u.id === id && u.facility_id === req.tenantFacilityId);
  if (!user) {
    return res.status(404).json({ success: false, message: "User not found in your facility." });
  }

  if (fullName) user.full_name = fullName;
  if (department) user.department = department;
  if (phone) user.phone = phone;

  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "FACILITY_USER_UPDATED", details: { targetUserId: id }, req });
  res.json({ success: true, message: "User details updated successfully.", user });
});

// Deactivate / Reactivate facility user
app.put("/api/users/:id/status", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), (req, res) => {
  const { id } = req.params;
  const { isActive } = req.body;

  const user = memoryDb.users.find(u => u.id === id && u.facility_id === req.tenantFacilityId);
  if (!user) {
    return res.status(404).json({ success: false, message: "User not found in your facility." });
  }

  user.is_active = Boolean(isActive);
  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: `USER_${isActive ? 'ACTIVATED' : 'DEACTIVATED'}`, details: { targetUserId: id }, req });

  res.json({ success: true, message: `User account has been ${isActive ? 'reactivated' : 'deactivated'}.`, user });
});

// Change user role
app.put("/api/users/:id/role", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), (req, res) => {
  const { id } = req.params;
  const { role } = req.body;

  const allowedRoles = ["FACILITY_ADMIN", "QUALITY_MANAGER", "STAFF", "EXPERT"];
  if (!allowedRoles.includes(role)) {
    return res.status(400).json({ success: false, message: "Invalid role specified." });
  }

  const user = memoryDb.users.find(u => u.id === id && u.facility_id === req.tenantFacilityId);
  if (!user) {
    return res.status(404).json({ success: false, message: "User not found in your facility." });
  }

  user.role = role;
  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "USER_ROLE_CHANGED", details: { targetUserId: id, newRole: role }, req });

  res.json({ success: true, message: `User role updated to ${role}.`, user });
});

// =============================================================================
// Super Admin Management Endpoints
// =============================================================================

app.get("/api/admin/facilities", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  res.json({ success: true, facilities: memoryDb.facilities });
});

app.put("/api/admin/facilities/:id/status", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  const { id } = req.params;
  const { status, reason } = req.body;

  const facility = memoryDb.facilities.find(f => f.id === id);
  if (!facility) {
    return res.status(404).json({ success: false, message: "Facility not found." });
  }

  facility.status = status;
  logAuditEvent({ facilityId: id, userId: req.user.userId, userEmail: req.user.email, action: `FACILITY_STATUS_UPDATED_${status}`, details: { status, reason }, req });

  await sendFacilityStatusNotification(facility.work_email, facility.name, status, reason);

  res.json({ success: true, message: `Facility status updated to ${status}.`, facility });
});

app.get("/api/admin/plans", authenticateToken, async (req, res) => {
  res.json({ success: true, plans: memoryDb.subscription_plans });
});

app.post("/api/admin/plans", authenticateToken, authorizeRoles("SUPER_ADMIN"), (req, res) => {
  const { id, name, priceEgp, billingPeriod, features } = req.body;
  const existing = memoryDb.subscription_plans.find(p => p.id === id);

  if (existing) {
    if (name) existing.name = name;
    if (priceEgp) existing.price_egp = priceEgp;
    if (billingPeriod) existing.billing_period = billingPeriod;
    if (features) existing.features = features;
    return res.json({ success: true, message: "Plan updated successfully.", plan: existing });
  }

  const newPlan = {
    id: id || `plan_${uuidv4()}`,
    name,
    price_egp: priceEgp || 50000,
    billing_period: billingPeriod || "annual",
    facility_limit: 1,
    user_limit: 25,
    features: features || [],
    is_active: true
  };
  memoryDb.subscription_plans.push(newPlan);
  res.status(201).json({ success: true, message: "New subscription plan created.", plan: newPlan });
});

app.get("/api/admin/analytics", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  const totalFacilities = memoryDb.facilities.length;
  const activeSubscriptions = memoryDb.facilities.filter(f => f.status === "ACTIVE" || f.status === "APPROVED").length;
  const pendingRegistrations = memoryDb.facilities.filter(f => f.status === "PENDING_REVIEW" || f.status === "PENDING_PAYMENT").length;
  const suspendedFacilities = memoryDb.facilities.filter(f => f.status === "SUSPENDED").length;

  // Real ARR Calculation Formula: Sum of actual annual plan prices for all ACTIVE or APPROVED facilities
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
  res.json({ success: true, auditLogs: memoryDb.audit_logs });
});

// =============================================================================
// Payment Endpoints
// =============================================================================

app.post("/api/payments/submit-proof", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const { planId, amount, paymentMethod, transactionRef, proofUrl } = req.body;

  const payment = {
    id: `pay_${uuidv4()}`,
    facility_id: req.tenantFacilityId,
    plan_id: planId,
    amount: amount || 45000,
    payment_method: paymentMethod,
    status: "PENDING_VERIFICATION",
    transaction_ref: transactionRef,
    proof_url: proofUrl,
    created_at: new Date().toISOString()
  };

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
  const payment = memoryDb.payments.find(p => p.id === paymentId);

  if (!payment) {
    return res.status(404).json({ success: false, message: "Payment record not found." });
  }

  payment.status = approved ? "VERIFIED" : "REJECTED";
  
  const facility = memoryDb.facilities.find(f => f.id === payment.facility_id);
  if (facility && approved) {
    facility.status = "APPROVED";
    const plan = memoryDb.subscription_plans.find(p => p.id === payment.plan_id);
    const planName = plan ? plan.name : "Standard Hospital Plan";
    const expiryDate = new Date(Date.now() + 365 * 24 * 3600 * 1000).toISOString();

    await sendFacilityStatusNotification(facility.work_email, facility.name, "APPROVED");
    await sendSubscriptionActivatedNotification(facility.work_email, facility.name, planName, expiryDate);
  }

  logAuditEvent({ facilityId: payment.facility_id, userId: req.user.userId, userEmail: req.user.email, action: `PAYMENT_VERIFICATION_${payment.status}`, req });

  res.json({ success: true, payment });
});

// =============================================================================
// Document Storage & Management (Real Storage Abstraction with Multi-Tenancy)
// =============================================================================

// Upload document with file validation & strict tenant isolation
app.post("/api/documents/upload", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const { title, category, requirementCode, originalName, mimeType, base64Content } = req.body;

    if (!title || !base64Content) {
      return res.status(400).json({ success: false, message: "Document title and base64 file content are required." });
    }

    const storedFile = await uploadDocument({
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

    memoryDb.documents.unshift(docRecord);
    logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "DOCUMENT_UPLOADED", details: { docId: docRecord.id, title }, req });

    res.status(201).json({ success: true, message: "Document securely uploaded.", document: docRecord });
  } catch (err) {
    res.status(400).json({ success: false, message: err.message });
  }
});

// List tenant documents (excludes soft-deleted items)
app.get("/api/documents", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facilityDocs = memoryDb.documents.filter(d => d.facilityId === req.tenantFacilityId && !d.deleted_at);
  res.json({ success: true, documents: facilityDocs });
});

// Download tenant document binary buffer
app.get("/api/documents/:id/download", authenticateToken, enforceTenantIsolation, async (req, res) => {
  try {
    const { id } = req.params;
    const doc = memoryDb.documents.find(d => d.id === id && d.facilityId === req.tenantFacilityId);

    if (!doc) {
      return res.status(404).json({ success: false, message: "Document not found or access denied." });
    }

    const buffer = await getDocumentBuffer({
      facilityId: req.tenantFacilityId,
      storagePath: doc.storagePath
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
  try {
    const { id } = req.params;
    const docIndex = memoryDb.documents.findIndex(d => d.id === id && d.facilityId === req.tenantFacilityId && !d.deleted_at);

    if (docIndex === -1) {
      return res.status(404).json({ success: false, message: "Document not found." });
    }

    const doc = memoryDb.documents[docIndex];
    doc.deleted_at = new Date().toISOString();
    doc.deleted_by = req.user.email;

    // Push a trash entry referencing this record
    memoryDb.trash.push({
      id: `trash_${require('uuid').v4()}`,
      item_id: doc.id,
      item_type: 'document',
      item_name: doc.title || doc.id,
      module: 'Document Library',
      facility_id: req.tenantFacilityId,
      deleted_at: doc.deleted_at,
      deleted_by: req.user.email,
      snapshot: { ...doc }
    });

    logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "DOCUMENT_MOVED_TO_TRASH", entityType: 'document', entityId: id, details: { title: doc.title }, req });
    res.json({ success: true, message: "Document moved to Trash." });
  } catch (err) {
    res.status(400).json({ success: false, message: err.message });
  }
});

// Permanent-delete document (called from Trash screen)
app.delete("/api/documents/:id/permanent", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  try {
    const { id } = req.params;
    const docIndex = memoryDb.documents.findIndex(d => d.id === id && d.facilityId === req.tenantFacilityId && d.deleted_at);
    if (docIndex === -1) {
      return res.status(404).json({ success: false, message: "Document not found in Trash." });
    }
    const doc = memoryDb.documents[docIndex];
    if (doc.storagePath) {
      try { await deleteDocumentFile({ facilityId: req.tenantFacilityId, storagePath: doc.storagePath }); } catch (_) {}
    }
    memoryDb.documents.splice(docIndex, 1);
    // Remove from trash index
    const ti = memoryDb.trash.findIndex(t => t.item_id === id && t.facility_id === req.tenantFacilityId);
    if (ti !== -1) memoryDb.trash.splice(ti, 1);
    logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "DOCUMENT_PERMANENTLY_DELETED", entityType: 'document', entityId: id, details: { title: doc.title }, req });
    res.json({ success: true, message: "Document permanently deleted." });
  } catch (err) {
    res.status(400).json({ success: false, message: err.message });
  }
});

// =============================================================================
// Multi-Tenant Accreditation Endpoints (JWT Derived Tenant)
// =============================================================================

// gap GET filtered below after soft-delete routes are added
app.post("/api/gaps", authenticateToken, enforceTenantIsolation, (req, res) => {
  const newGap = { id: `gap_${uuidv4()}`, facilityId: req.tenantFacilityId, ...req.body, createdAt: new Date().toISOString() };
  memoryDb.gaps.unshift(newGap);
  res.status(201).json({ success: true, gap: newGap });
});

app.get("/api/action-plans", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facilityPlans = memoryDb.action_plans.filter(p => p.facilityId === req.tenantFacilityId && !p.deleted_at);
  res.json({ success: true, actionPlans: facilityPlans });
});

app.post("/api/action-plans", authenticateToken, enforceTenantIsolation, (req, res) => {
  const newPlan = { id: `plan_${uuidv4()}`, facilityId: req.tenantFacilityId, ...req.body, createdAt: new Date().toISOString() };
  memoryDb.action_plans.unshift(newPlan);
  res.status(201).json({ success: true, actionPlan: newPlan });
});

// Soft-delete action plan
app.delete("/api/action-plans/:id", authenticateToken, enforceTenantIsolation, (req, res) => {
  const { id } = req.params;
  const item = memoryDb.action_plans.find(p => p.id === id && p.facilityId === req.tenantFacilityId && !p.deleted_at);
  if (!item) return res.status(404).json({ success: false, message: "Action Plan not found." });
  item.deleted_at = new Date().toISOString();
  item.deleted_by = req.user.email;
  memoryDb.trash.push({ id: `trash_${uuidv4()}`, item_id: item.id, item_type: 'action_plan', item_name: item.title || item.id, module: 'Action Plans', facility_id: req.tenantFacilityId, deleted_at: item.deleted_at, deleted_by: req.user.email, snapshot: { ...item } });
  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "ACTION_PLAN_MOVED_TO_TRASH", entityType: 'action_plan', entityId: id, details: { title: item.title }, req });
  res.json({ success: true, message: "Action Plan moved to Trash." });
});

app.get("/api/gaps", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facilityGaps = memoryDb.gaps.filter(g => g.facilityId === req.tenantFacilityId && !g.deleted_at);
  res.json({ success: true, gaps: facilityGaps });
});

// Soft-delete gap
app.delete("/api/gaps/:id", authenticateToken, enforceTenantIsolation, (req, res) => {
  const { id } = req.params;
  const item = memoryDb.gaps.find(g => g.id === id && g.facilityId === req.tenantFacilityId && !g.deleted_at);
  if (!item) return res.status(404).json({ success: false, message: "Gap item not found." });
  item.deleted_at = new Date().toISOString();
  item.deleted_by = req.user.email;
  memoryDb.trash.push({ id: `trash_${uuidv4()}`, item_id: item.id, item_type: 'gap', item_name: item.gapTitle || item.gap_title || item.title || item.standard_code || item.id, module: 'Gap Analysis', facility_id: req.tenantFacilityId, deleted_at: item.deleted_at, deleted_by: req.user.email, snapshot: { ...item } });
  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "GAP_MOVED_TO_TRASH", entityType: 'gap', entityId: id, details: { title: item.gapTitle || item.gap_title || item.title }, req });
  res.json({ success: true, message: "Gap item moved to Trash." });
});

app.get("/api/licenses", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facilityLicenses = memoryDb.licenses.filter(l => l.facilityId === req.tenantFacilityId && !l.deleted_at);
  res.json({ success: true, licenses: facilityLicenses });
});

app.post("/api/licenses", authenticateToken, enforceTenantIsolation, (req, res) => {
  const newLicense = { id: `lic_${uuidv4()}`, facilityId: req.tenantFacilityId, ...req.body, createdAt: new Date().toISOString() };
  memoryDb.licenses.unshift(newLicense);
  res.status(201).json({ success: true, license: newLicense });
});

// Soft-delete license
app.delete("/api/licenses/:id", authenticateToken, enforceTenantIsolation, (req, res) => {
  const { id } = req.params;
  const item = memoryDb.licenses.find(l => l.id === id && l.facilityId === req.tenantFacilityId && !l.deleted_at);
  if (!item) return res.status(404).json({ success: false, message: "License not found." });
  item.deleted_at = new Date().toISOString();
  item.deleted_by = req.user.email;
  memoryDb.trash.push({ id: `trash_${uuidv4()}`, item_id: item.id, item_type: 'license', item_name: item.licenseName || item.license_name || item.id, module: 'Licenses & Basic Requirements', facility_id: req.tenantFacilityId, deleted_at: item.deleted_at, deleted_by: req.user.email, snapshot: { ...item } });
  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "LICENSE_MOVED_TO_TRASH", entityType: 'license', entityId: id, details: { name: item.licenseName || item.license_name }, req });
  res.json({ success: true, message: "License moved to Trash." });
});

// =============================================================================
// Real Data-Driven Badges & Achievements
// =============================================================================

app.get("/api/facilities/badges", authenticateToken, enforceTenantIsolation, async (req, res) => {
  const facilityId = req.tenantFacilityId;
  const facility = memoryDb.facilities.find(f => f.id === facilityId);
  const gaps = memoryDb.gaps.filter(g => g.facilityId === facilityId);
  const licenses = memoryDb.licenses.filter(l => l.facilityId === facilityId);
  const docs = memoryDb.documents.filter(d => d.facilityId === facilityId);

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

app.post("/api/experts/request-consultation", authenticateToken, enforceTenantIsolation, (req, res) => {
  const { expertId, expertName, topic, preferredDate, notes } = req.body;

  const request = {
    id: `req_${uuidv4()}`,
    facilityId: req.tenantFacilityId,
    facilityName: memoryDb.facilities.find(f => f.id === req.tenantFacilityId)?.name || "Facility",
    expertId: expertId || "exp_01",
    expertName: expertName || "Accreditation Consultant",
    topic: topic || "GAHAR 2025 Mock Audit",
    preferredDate: preferredDate || new Date().toISOString(),
    notes: notes || "",
    status: "PENDING",
    createdAt: new Date().toISOString()
  };

  memoryDb.consultation_requests.unshift(request);
  logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "CONSULTATION_REQUEST_SUBMITTED", details: { expertId, topic }, req });

  res.status(201).json({ success: true, message: "Consultation request recorded. An advisor will contact your quality team.", request });
});

app.get("/api/experts/my-requests", authenticateToken, enforceTenantIsolation, (req, res) => {
  const requests = memoryDb.consultation_requests.filter(r => r.facilityId === req.tenantFacilityId);
  res.json({ success: true, requests });
});

// =============================================================================
// Subscriptions Current Lifecycle Endpoint
// =============================================================================

app.get("/api/subscriptions/current", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facility = memoryDb.facilities.find(f => f.id === req.tenantFacilityId);
  if (!facility) {
    return res.status(404).json({ success: false, message: "Facility record not found." });
  }

  const plan = memoryDb.subscription_plans.find(p => p.id === facility.subscription_plan_id) || memoryDb.subscription_plans[0];
  
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

  let reply = "";

  // Try Groq models in order of preference
  if (groq) {
    const groqModels = [
      process.env.GROQ_MODEL || "llama-3.3-70b-versatile",
      "llama-3.3-70b-versatile",
      "llama-3.1-8b-instant",
      "llama3-70b-8192",
    ];

    for (const model of groqModels) {
      if (reply) break;
      try {
        const completion = await groq.chat.completions.create({
          model,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userQuery || prompt },
          ],
          max_tokens: 1024,
        });
        reply = completion.choices[0].message?.content || "";
        if (reply) console.log(`✅ Groq model used: ${model}`);
      } catch (e) {
        console.warn(`⚠️ Groq model ${model} failed:`, e.message?.split('\n')[0]);
      }
    }
  }

  // Fallback to Gemini
  if (!reply && genAI) {
    const geminiModels = [process.env.GEMINI_MODEL, "gemini-1.5-flash", "gemini-2.5-flash", "gemini-1.5-pro"].filter(Boolean);
    for (const m of geminiModels) {
      if (reply) break;
      try {
        const model = genAI.getGenerativeModel({ model: m });
        const result = await model.generateContent(`${systemPrompt}\n\nUser: ${userQuery || prompt}`);
        reply = result.response.text();
        if (reply) console.log(`✅ Gemini fallback used with model: ${m}`);
      } catch (e) {
        console.warn(`⚠️ Gemini error (${m}):`, e.message?.split('\n')[0]);
      }
    }
  }

  // Authoritative deterministic fallback (directly grounded in dataset)
  if (!reply) {
    if (standardCode && standardGrounding) {
      if (isArabic) {
        reply = `**المرجع الرسمي لمعايير جهار 2025 — المعيار ${standardCode}**\n\n${standardGrounding}\n\n*ملاحظة: هذه البيانات مستخرجة مباشرة ومطابقة لدليل معايير اعتماد المستشفيات الرسمي GAHAR 2025.*`;
      } else {
        reply = `**GAHAR 2025 Official Reference — Standard ${standardCode}**\n\n${standardGrounding}\n\n*Note: This response is directly grounded in the authoritative GAHAR 2025 Accreditation Handbook.*`;
      }
    } else {
      if (isArabic) {
        reply = `**إرشادات جهار 2025 — ${screenContext || 'الاعتماد الصحي'}**\n\nبخصوص استفساركم: "${userQuery}":\n\n1. **أدلة الامتثال (Evidence of Compliance):** احرص على توثيق كافة السياسات والإجراءات وتحديد المسؤوليات وتواريخ المراجعة.\n2. **لجنة الجودة وسلامة المرضى:** يجب اعتماد كافة الوثائق والخطط من لجان المستشفى المختصة.\n3. **التطبيق والملاحظة الميدانية:** يتحقق مقيمو جهار من التطبيق الفعلي ومقابلات الكوادر وسجلات التدريب.\n4. **مؤشرات الأداء (KPIs):** تتبع مؤشرات القياس والتحسين المستمر لكل متطلب.\n\nيمكنك كتابة كود أي معيار (مثل GSR.01 أو GSR.05 أو IPC.01) لعرض متطلباته وأدلته التفصيلية فوراً.`;
      } else {
        reply = `**GAHAR 2025 Guidance — ${screenContext || 'Accreditation'}**\n\nRegarding your inquiry: "${userQuery}":\n\n1. **Evidence of Compliance (EOC):** Ensure all relevant policies, procedures, and logs are documented with dates and responsible personnel.\n2. **Governance Approval:** All documentation must be reviewed and approved by the Quality & Safety Committee.\n3. **Survey Verification:** GAHAR surveyors verify compliance through observation, staff interviews, and patient record reviews.\n4. **Key Performance Indicators:** Track monthly compliance metrics and corrective action plans.\n\nYou can also mention any specific GAHAR standard code (e.g. GSR.01, GSR.05, IPC.01) to get the exact requirements and evidence checklist.`;
      }
    }
  }

  res.json({ success: true, reply, standardCode: standardCode || null });
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

function checkPg() {
  return typeof isPgConnected === 'function' ? isPgConnected() : (isPgConnected === true);
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
  try {
    let items = [];
    if (checkPg()) {
      const result = await query(
        "SELECT * FROM sat_sub_evidence WHERE standard_code = $1 ORDER BY sort_order, item_number",
        [standardCode.toUpperCase()]
      );
      if (result && result.rows) items = result.rows;
    }
    if (!items.length) {
      items = (memoryDb.sat_sub_evidence || []).filter(
        e => e.standard_code === standardCode.toUpperCase()
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
app.get("/api/trash", authenticateToken, enforceTenantIsolation, (req, res) => {
  const { type, search, from, to } = req.query;
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
app.post("/api/trash/:id/restore", authenticateToken, enforceTenantIsolation, (req, res) => {
  const { id } = req.params;
  const trashIndex = memoryDb.trash.findIndex(t => t.id === id && t.facility_id === req.tenantFacilityId);
  if (trashIndex === -1) {
    return res.status(404).json({ success: false, message: "Trash item not found or already restored." });
  }

  const trashEntry = memoryDb.trash[trashIndex];
  const backingArray = _trashBackingArray(trashEntry.item_type);
  if (!backingArray) {
    return res.status(400).json({ success: false, message: `Unknown item type: ${trashEntry.item_type}` });
  }

  // Find the soft-deleted record and clear its deletion markers
  const record = backingArray.find(r => r.id === trashEntry.item_id && r.facility_id === req.tenantFacilityId || r.facilityId === req.tenantFacilityId);
  if (record) {
    delete record.deleted_at;
    delete record.deleted_by;
  }

  memoryDb.trash.splice(trashIndex, 1);

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: `${trashEntry.item_type.toUpperCase()}_RESTORED_FROM_TRASH`,
    entityType: trashEntry.item_type,
    entityId: trashEntry.item_id,
    details: { name: trashEntry.item_name },
    req
  });

  res.json({ success: true, message: `${trashEntry.item_name} restored successfully.`, itemType: trashEntry.item_type, module: trashEntry.module });
});

// POST /api/trash/restore-all — restore all trashed items for this facility
app.post("/api/trash/restore-all", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facilityTrash = memoryDb.trash.filter(t => t.facility_id === req.tenantFacilityId);
  if (facilityTrash.length === 0) {
    return res.json({ success: true, message: "Trash is already empty.", restoredCount: 0 });
  }

  let restoredCount = 0;
  for (const trashEntry of facilityTrash) {
    const backingArray = _trashBackingArray(trashEntry.item_type);
    if (backingArray) {
      const record = backingArray.find(r => r.id === trashEntry.item_id && (r.facility_id === req.tenantFacilityId || r.facilityId === req.tenantFacilityId));
      if (record) {
        delete record.deleted_at;
        delete record.deleted_by;
      }
    }
    restoredCount++;
  }

  memoryDb.trash = memoryDb.trash.filter(t => t.facility_id !== req.tenantFacilityId);

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
  const trashIndex = memoryDb.trash.findIndex(t => t.id === id && t.facility_id === req.tenantFacilityId);
  if (trashIndex === -1) {
    return res.status(404).json({ success: false, message: "Trash item not found." });
  }

  const trashEntry = memoryDb.trash[trashIndex];

  // Cross-tenant guard (belt-and-suspenders)
  if (trashEntry.facility_id !== req.tenantFacilityId) {
    logAuditEvent({ facilityId: req.tenantFacilityId, userId: req.user.userId, userEmail: req.user.email, action: "SUSPICIOUS_CROSS_TENANT_TRASH_ACCESS", details: { targetFacility: trashEntry.facility_id }, req });
    return res.status(403).json({ success: false, message: "Security Violation: Cannot permanently delete records belonging to another facility." });
  }

  const backingArray = _trashBackingArray(trashEntry.item_type);
  if (backingArray) {
    const recIdx = backingArray.findIndex(r => r.id === trashEntry.item_id);
    if (recIdx !== -1) {
      const rec = backingArray[recIdx];
      // For documents: also delete the physical file
      if (trashEntry.item_type === 'document' && rec.storagePath) {
        try { await deleteDocumentFile({ facilityId: req.tenantFacilityId, storagePath: rec.storagePath }); } catch (_) {}
      }
      backingArray.splice(recIdx, 1);
    }
  }

  memoryDb.trash.splice(trashIndex, 1);

  logAuditEvent({
    facilityId: req.tenantFacilityId,
    userId: req.user.userId,
    userEmail: req.user.email,
    action: `${trashEntry.item_type.toUpperCase()}_PERMANENTLY_DELETED`,
    entityType: trashEntry.item_type,
    entityId: trashEntry.item_id,
    details: { name: trashEntry.item_name },
    req
  });

  res.json({ success: true, message: `${trashEntry.item_name} permanently deleted.` });
});

// DELETE /api/trash/empty — permanently delete all trash for this facility
app.delete("/api/trash/empty", authenticateToken, enforceTenantIsolation, authorizeRoles("FACILITY_ADMIN", "SUPER_ADMIN"), async (req, res) => {
  const facilityTrash = memoryDb.trash.filter(t => t.facility_id === req.tenantFacilityId);
  if (facilityTrash.length === 0) {
    return res.json({ success: true, message: "Trash is already empty.", deletedCount: 0 });
  }

  let deletedCount = 0;
  for (const trashEntry of facilityTrash) {
    // Cross-tenant guard
    if (trashEntry.facility_id !== req.tenantFacilityId) continue;

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
    deletedCount++;
  }

  // Remove all trash entries for this facility
  memoryDb.trash = memoryDb.trash.filter(t => t.facility_id !== req.tenantFacilityId);

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
// Start Backend Server
// =============================================================================

const PORT = process.env.PORT || 3000;
app.listen(PORT, "0.0.0.0", () => {
  console.log(`🚀 GAHAR Healthcare Accreditation Platform — Backend Server running on port ${PORT}`);
});