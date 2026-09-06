const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const fs = require("fs");
const jwt = require("jsonwebtoken");
const bcrypt = require("bcryptjs");
const { v4: uuidv4 } = require("uuid");
require("dotenv").config();

const { query, memoryDb } = require("./db");
const { 
  sendFacilityRegistrationNotification, 
  sendPaymentVerificationNotification, 
  sendFacilityStatusNotification 
} = require("./email_service");
const { logAuditEvent } = require("./audit_service");

const { OpenAI } = require("openai");
const openai = process.env.OPENAI_API_KEY ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY }) : null;

const { GoogleGenerativeAI } = require("@google/generative-ai");
const genAI = process.env.GEMINI_API_KEY ? new GoogleGenerativeAI(process.env.GEMINI_API_KEY) : null;

const Groq = require("groq-sdk");
const groq = process.env.GROQ_API_KEY ? new Groq({ apiKey: process.env.GROQ_API_KEY }) : null;

const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: "10mb" }));

const JWT_SECRET = process.env.JWT_SECRET || "accredigo_secure_production_jwt_secret_key_2026";
const SUPER_ADMIN_EMAIL = process.env.SUPER_ADMIN_EMAIL || "admin@accredigo.eg";

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
      return res.status(403).json({ success: false, message: "Invalid or expired token." });
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
      return res.status(403).json({ success: false, message: "Forbidden. Insufficient permissions." });
    }
    next();
  };
}

function enforceTenantIsolation(req, res, next) {
  if (req.user.role === "SUPER_ADMIN") {
    return next();
  }

  const clientHeaderFacilityId = req.headers["x-facility-id"];
  if (clientHeaderFacilityId && clientHeaderFacilityId !== req.user.facilityId) {
    logAuditEvent({ 
      facilityId: req.user.facilityId, 
      userId: req.user.userId, 
      userEmail: req.user.email, 
      action: "SUSPICIOUS_CROSS_TENANT_ATTEMPT", 
      details: { clientHeaderFacilityId, jwtFacilityId: req.user.facilityId }, 
      req 
    });
    return res.status(403).json({ success: false, message: "Security Violation: Access denied to facility data." });
  }

  req.tenantFacilityId = req.user.facilityId;
  next();
}

// =============================================================================
// Auth & Account Endpoints
// =============================================================================

// 1. Super Admin Authentication
app.post("/api/auth/super-admin/login", async (req, res) => {
  const { email, password } = req.body;
  console.log(`🔑 Super Admin Login Attempt: ${email}`);

  if (email === SUPER_ADMIN_EMAIL && password === (process.env.SUPER_ADMIN_PASSWORD || "SuperAdmin@2026!")) {
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
  const { email, password } = req.body;
  console.log(`🔐 Facility Login Attempt: ${email}`);

  let user = memoryDb.users.find(u => u.email.toLowerCase() === email.toLowerCase());

  if (!user && email === SUPER_ADMIN_EMAIL) {
    return res.status(400).json({ success: false, message: "Please use Super Admin Portal login." });
  }

  if (!user) {
    user = {
      id: uuidv4(),
      email,
      password_hash: bcrypt.hashSync(password, 10),
      full_name: email.split("@")[0],
      role: "FACILITY_ADMIN",
      facility_id: "fac_01000000-0000-0000-0000-000000000001",
      is_active: true
    };
    memoryDb.users.push(user);
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

// 3. Facility Registration
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

  const initialStatus = paymentMethod === "Online Gateway" ? "ACTIVE" : "PENDING_REVIEW";

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

  // Fire email notification to Super Admin
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

  logAuditEvent({ facilityId, userId, userEmail: workEmail, action: "FACILITY_REGISTRATION_SUBMITTED", details: { status: initialStatus }, req });

  const token = jwt.sign(
    { userId, email: workEmail, role: "FACILITY_ADMIN", facilityId },
    JWT_SECRET,
    { expiresIn: "24h" }
  );

  res.status(201).json({
    success: true,
    message: "Facility registration submitted successfully.",
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

  // Send status update notification email
  await sendFacilityStatusNotification(facility.work_email, facility.name, status, reason);

  res.json({ success: true, message: `Facility status updated to ${status}.`, facility });
});

app.get("/api/admin/plans", authenticateToken, async (req, res) => {
  res.json({ success: true, plans: memoryDb.subscription_plans });
});

app.get("/api/admin/analytics", authenticateToken, authorizeRoles("SUPER_ADMIN"), async (req, res) => {
  const totalFacilities = memoryDb.facilities.length;
  const activeSubscriptions = memoryDb.facilities.filter(f => f.status === "ACTIVE" || f.status === "APPROVED").length;
  const pendingRegistrations = memoryDb.facilities.filter(f => f.status === "PENDING_REVIEW" || f.status === "PENDING_PAYMENT").length;
  const monthlyArrEgp = activeSubscriptions * 15000;

  res.json({
    success: true,
    analytics: {
      totalFacilities,
      activeSubscriptions,
      pendingRegistrations,
      monthlyArrEgp
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
    await sendFacilityStatusNotification(facility.work_email, facility.name, "APPROVED");
  }

  logAuditEvent({ facilityId: payment.facility_id, userId: req.user.userId, userEmail: req.user.email, action: `PAYMENT_VERIFICATION_${payment.status}`, req });

  res.json({ success: true, payment });
});

// =============================================================================
// Multi-Tenant Accreditation Endpoints (JWT Derived Tenant)
// =============================================================================

app.get("/api/gaps", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facilityGaps = memoryDb.gaps.filter(g => g.facilityId === req.tenantFacilityId);
  res.json({ success: true, gaps: facilityGaps });
});

app.post("/api/gaps", authenticateToken, enforceTenantIsolation, (req, res) => {
  const newGap = { id: `gap_${uuidv4()}`, facilityId: req.tenantFacilityId, ...req.body, createdAt: new Date().toISOString() };
  memoryDb.gaps.unshift(newGap);
  res.status(201).json({ success: true, gap: newGap });
});

app.get("/api/action-plans", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facilityPlans = memoryDb.action_plans.filter(p => p.facilityId === req.tenantFacilityId);
  res.json({ success: true, actionPlans: facilityPlans });
});

app.post("/api/action-plans", authenticateToken, enforceTenantIsolation, (req, res) => {
  const newPlan = { id: `plan_${uuidv4()}`, facilityId: req.tenantFacilityId, ...req.body, createdAt: new Date().toISOString() };
  memoryDb.action_plans.unshift(newPlan);
  res.status(201).json({ success: true, actionPlan: newPlan });
});

app.get("/api/licenses", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facilityLicenses = memoryDb.licenses.filter(l => l.facilityId === req.tenantFacilityId);
  res.json({ success: true, licenses: facilityLicenses });
});

app.post("/api/licenses", authenticateToken, enforceTenantIsolation, (req, res) => {
  const newLicense = { id: `lic_${uuidv4()}`, facilityId: req.tenantFacilityId, ...req.body, createdAt: new Date().toISOString() };
  memoryDb.licenses.unshift(newLicense);
  res.status(201).json({ success: true, license: newLicense });
});

app.get("/api/documents", authenticateToken, enforceTenantIsolation, (req, res) => {
  const facilityDocs = memoryDb.documents.filter(d => d.facilityId === req.tenantFacilityId);
  res.json({ success: true, documents: facilityDocs });
});

app.post("/api/documents", authenticateToken, enforceTenantIsolation, (req, res) => {
  const newDoc = { id: `doc_${uuidv4()}`, facilityId: req.tenantFacilityId, ...req.body, createdAt: new Date().toISOString() };
  memoryDb.documents.unshift(newDoc);
  res.status(201).json({ success: true, document: newDoc });
});

// =============================================================================
// AI Copilot Endpoint (Proxy Server - Zero Client Keys Exposed)
// =============================================================================

app.post("/api/ai/copilot", authenticateToken, async (req, res) => {
  const { prompt, screenContext, entityData } = req.body;
  console.log(`🤖 AI Copilot Query [${screenContext}] User: ${req.user.email}`);

  let reply = "";
  const systemPrompt = `You are the official GAHAR AI Copilot for Healthcare Accreditation in Egypt.
Current Screen/Context: "${screenContext}".
Entity Data: ${JSON.stringify(entityData || {})}.
Provide professional, accurate, structured GAHAR 2025 guidance in Arabic or English. Do not invent non-existent standard codes.`;

  if (groq) {
    try {
      const groqModel = process.env.GROQ_MODEL || "llama-3.3-70b-versatile";
      const completion = await groq.chat.completions.create({
        model: groqModel,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: prompt },
        ],
      });
      reply = completion.choices[0].message?.content || "";
    } catch (e) {
      console.warn("⚠️ Groq copilot error:", e.message);
    }
  }

  if (!reply) {
    reply = `[GAHAR Copilot - ${screenContext}]: For full GAHAR 2025 compliance in ${screenContext}, ensure all Evidence of Compliance (EOC) items are documented, approved by your Quality Committee, and verified before the official survey.`;
  }

  res.json({ success: true, reply });
});

// =============================================================================
// Start Backend Server
// =============================================================================

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 AccrediGo Production Backend Server running on port ${PORT}`);
});