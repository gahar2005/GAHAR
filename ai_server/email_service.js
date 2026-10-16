// =============================================================================
// GAHAR SMTP Email Delivery Service
// Supports: SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM
// Features: Startup verification, TLS handling, non-blocking delivery,
//           idempotent de-duplication, professional Egyptian healthcare templates.
// =============================================================================

const nodemailer = require('nodemailer');
const crypto = require('crypto');

const SUPER_ADMIN_EMAIL = process.env.SUPER_ADMIN_EMAIL || process.env.ADMIN_EMAIL || 'superadmin@gahar.gov.eg';
const SMTP_FROM = process.env.SMTP_FROM || '"AccrediGo / GAHAR Platform" <no-reply@gahar-platform.eg>';

// Initialize transporter safely if SMTP credentials are provided
let transporter = null;
const isSmtpConfigured = !!(process.env.SMTP_HOST && process.env.SMTP_USER);

if (isSmtpConfigured) {
  const port = parseInt(process.env.SMTP_PORT || '587', 10);
  const secure = process.env.SMTP_SECURE 
    ? process.env.SMTP_SECURE === 'true' 
    : (port === 465);

  transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port,
    secure,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS || '',
    },
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 15000,
  });
}

// In-memory de-duplication cache (prevents duplicate emails upon request retries within 2 minutes)
const emailDeduplicationCache = new Map();
const DEDUPLICATION_WINDOW_MS = 120 * 1000; // 2 minutes

function cleanupDeduplicationCache() {
  const now = Date.now();
  for (const [key, timestamp] of emailDeduplicationCache.entries()) {
    if (now - timestamp > DEDUPLICATION_WINDOW_MS) {
      emailDeduplicationCache.delete(key);
    }
  }
}

/**
 * Verify SMTP connection at startup (non-fatal; logs diagnostic info)
 */
async function verifySmtpConnection() {
  if (!transporter) {
    console.log('ℹ️ SMTP is not configured (SMTP_HOST/SMTP_USER missing). Outgoing emails will be logged safely in development/mock mode.');
    return { configured: false, verified: false };
  }

  try {
    await transporter.verify();
    console.log(`✅ SMTP Connection verified successfully with host: ${process.env.SMTP_HOST}:${process.env.SMTP_PORT || 587}`);
    return { configured: true, verified: true };
  } catch (err) {
    // Never crash the application on startup if optional SMTP provider fails
    console.warn(`⚠️ SMTP Connection verification failed (${process.env.SMTP_HOST}): ${err.message}. Emails will be skipped safely.`);
    return { configured: true, verified: false, error: err.message };
  }
}

/**
 * Core sendEmail function with error safety, de-duplication, and non-blocking delivery
 */
async function sendEmail({ to, subject, html, text, deduplicationKey }) {
  if (!to) {
    return { success: false, delivered: false, error: "Recipient email address is required" };
  }

  // Idempotency check
  cleanupDeduplicationCache();
  const hashKey = deduplicationKey || crypto.createHash('md5').update(`${to}:${subject}`).digest('hex');
  if (emailDeduplicationCache.has(hashKey)) {
    console.log(`ℹ️ Duplicate email suppressed within 2-minute window: [${to}] ${subject}`);
    return { success: true, delivered: false, duplicateSuppressed: true };
  }
  emailDeduplicationCache.set(hashKey, Date.now());

  // If SMTP is not configured, record event safely without claiming delivery
  if (!transporter) {
    console.log(`✉️ [SMTP NOT CONFIGURED - MOCK DISPATCH] To: ${to} | Subject: "${subject}"`);
    return { success: false, delivered: false, skipped: true, reason: "SMTP_NOT_CONFIGURED" };
  }

  try {
    const info = await transporter.sendMail({
      from: SMTP_FROM,
      to,
      subject,
      text: text || subject,
      html,
    });

    console.log(`✅ Email delivered to ${to} | MessageId: ${info.messageId}`);
    return { success: true, delivered: true, messageId: info.messageId };
  } catch (error) {
    // Never log passwords or auth tokens
    console.error(`❌ SMTP delivery failure to ${to}:`, error.message);
    return { success: false, delivered: false, error: error.message };
  }
}

// -----------------------------------------------------------------------------
// WORKFLOW A: Hospital Registration
// 1. Welcome email to Hospital Work Email
// 2. Administrative notification to GAHAR Super Admin
// -----------------------------------------------------------------------------

async function sendRegistrationWelcomeEmail({
  workEmail,
  facilityName,
  contactPerson,
  status,
  subscriptionPlanId
}) {
  const isPendingApproval = status === 'PENDING_REVIEW';
  const isPendingPayment = status === 'PENDING_PAYMENT';
  
  const planDisplay = subscriptionPlanId === 'plan_enterprise' 
    ? 'Enterprise Multi-Branch (المستشفيات الكبرى والمجموعات)'
    : subscriptionPlanId === 'plan_lab'
      ? 'Specialized Center / Lab (المراكز المتخصصة والمعامل)'
      : 'Standard Hospital (المستشفيات العامة والمركزية)';

  const subject = `[AccrediGo / GAHAR] مرحباً بكم — تم استلام طلب تسجيل ${facilityName}`;
  
  const html = `
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head><meta charset="utf-8"></head>
    <body style="font-family: Arial, sans-serif; background-color: #f7fafc; padding: 20px; color: #2d3748; line-height: 1.6;">
      <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 8px; border: 1px solid #e2e8f0; overflow: hidden;">
        <div style="background: #0f5257; padding: 24px; text-align: center; color: #ffffff;">
          <h1 style="margin: 0; font-size: 22px;">منصة اعتمادي جو — معايير جهار 2025</h1>
          <p style="margin: 6px 0 0; font-size: 14px; opacity: 0.9;">AccrediGo Healthcare Accreditation Platform</p>
        </div>
        <div style="padding: 24px;">
          <h2 style="color: #0f5257; font-size: 18px;">مرحباً د. ${contactPerson || 'مدير المنشأة'}،</h2>
          <p>يسعدنا إبلاغكم بأنه تم استلام طلب تسجيل منشأتكم <strong>(${facilityName})</strong> بنجاح في المنصة الوطنية للجاهزية للاعتماد الصحي (GAHAR 2025).</p>
          
          <div style="background: #edf2f7; border-right: 4px solid #0f5257; padding: 14px; border-radius: 4px; margin: 18px 0;">
            <p style="margin: 4px 0;"><strong>اسم المنشأة:</strong> ${facilityName}</p>
            <p style="margin: 4px 0;"><strong>خطة الاشتراك:</strong> ${planDisplay}</p>
            <p style="margin: 4px 0;"><strong>حالة الحساب:</strong> <span style="color: ${isPendingPayment ? '#c53030' : '#d69e2e'}; font-weight: bold;">${status}</span></p>
          </div>

          ${isPendingApproval ? `
            <p><strong>الخطوة القادمة:</strong> يقوم فريق المراجعة والاعتماد حالياً بالتحقق من بيانات المنشأة ومطابقتها. سيتم تفعيل حسابكم وإرسال إشعار الدخول فور الانتهاء خلال 24 ساعة عمل.</p>
          ` : isPendingPayment ? `
            <p><strong>الخطوة القادمة:</strong> يرجى استكمال عملية سداد رسوم الاشتراك عبر التحويل البنكي أو بوابة الدفع الإلكتروني ورفع إشعار السداد في لوحة التحكم لبدء مراجعة التفعيل.</p>
          ` : `
            <p>حساب منشأتكم جاهز للاستخدام ومتابعة معايير جهار 2025 وتقييم الفجوات ومكتبة الوثائق المعتمدة.</p>
          `}

          <p style="margin-top: 24px; font-size: 13px; color: #718096; border-top: 1px solid #e2e8f0; padding-top: 14px;">
            الهيئة العامة للاعتماد والرقابة الصحية — جمهورية مصر العربية<br/>
            لأي استفسارات، يمكنكم التواصل مع الدعم الفني: support@gahar-platform.eg
          </p>
        </div>
      </div>
    </body>
    </html>
  `;

  return sendEmail({
    to: workEmail,
    subject,
    html,
    deduplicationKey: `welcome:${workEmail}:${facilityName}`
  });
}

async function sendFacilityRegistrationNotification(facilityData) {
  const subject = `[GAHAR Super Admin] طلب تسجيل منشأة جديدة: ${facilityData.name}`;
  const html = `
    <h2>New Healthcare Facility Registration Request</h2>
    <p>A new facility has requested onboarding on the GAHAR Platform:</p>
    <ul>
      <li><strong>Facility Name:</strong> ${facilityData.name}</li>
      <li><strong>Facility Type:</strong> ${facilityData.type}</li>
      <li><strong>Governorate:</strong> ${facilityData.governorate}</li>
      <li><strong>Bed Capacity:</strong> ${facilityData.bedCapacity}</li>
      <li><strong>Contact Admin:</strong> ${facilityData.contactPerson}</li>
      <li><strong>Official Email:</strong> ${facilityData.workEmail}</li>
      <li><strong>Phone:</strong> ${facilityData.phone}</li>
      <li><strong>Plan Selected:</strong> ${facilityData.subscriptionPlanId}</li>
      <li><strong>Payment Method:</strong> ${facilityData.paymentMethod || 'Pending'}</li>
      <li><strong>Status:</strong> ${facilityData.status}</li>
    </ul>
    <p>Please log in to the GAHAR Super Admin Portal to review, verify documents, and activate the facility.</p>
  `;

  return sendEmail({
    to: SUPER_ADMIN_EMAIL,
    subject,
    html,
    deduplicationKey: `admin_reg:${facilityData.workEmail}`
  });
}

// -----------------------------------------------------------------------------
// WORKFLOW B: Subscription Payment Approval & Activation
// Sent ONLY after Super Admin verifies payment and subscription is activated
// -----------------------------------------------------------------------------

async function sendSubscriptionActivatedNotification(email, facilityName, planName, expiryDate) {
  const formattedExpiry = expiryDate 
    ? new Date(expiryDate).toLocaleDateString('ar-EG', { year: 'numeric', month: 'long', day: 'numeric' })
    : 'سنة كاملة من تاريخ التفعيل';

  const subject = `[GAHAR] تم تفعيل اشتراك الاعتماد بنجاح — ${facilityName}`;
  const html = `
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head><meta charset="utf-8"></head>
    <body style="font-family: Arial, sans-serif; background-color: #f7fafc; padding: 20px; color: #2d3748; line-height: 1.6;">
      <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 8px; border: 1px solid #e2e8f0; overflow: hidden;">
        <div style="background: #2b6cb0; padding: 24px; text-align: center; color: #ffffff;">
          <h1 style="margin: 0; font-size: 22px;">تم اعتماد الاشتراك وتفعيل الحساب</h1>
          <p style="margin: 6px 0 0; font-size: 14px; opacity: 0.9;">Accreditation Subscription Activated</p>
        </div>
        <div style="padding: 24px;">
          <h2 style="color: #2b6cb0; font-size: 18px;">تهانينا لإدارة ${facilityName}،</h2>
          <p>قام المسؤول الإداري بالتحقق من سداد الرسوم وتم <strong>تفعيل اشتراك منشأتكم</strong> بالكامل على منصة اعتمادي جو.</p>
          
          <div style="background: #ebf8ff; border-right: 4px solid #3182ce; padding: 14px; border-radius: 4px; margin: 18px 0;">
            <p style="margin: 4px 0;"><strong>اسم المنشأة:</strong> ${facilityName}</p>
            <p style="margin: 4px 0;"><strong>الباقة المفعلة:</strong> ${planName}</p>
            <p style="margin: 4px 0;"><strong>تاريخ انتهاء الصلاحية:</strong> ${formattedExpiry}</p>
            <p style="margin: 4px 0;"><strong>الحالة:</strong> <span style="color: #2b6cb0; font-weight: bold;">نشط (ACTIVE / APPROVED)</span></p>
          </div>

          <p><strong>المزايا المتاحة الآن لمنشأتكم:</strong></p>
          <ul>
            <li>الوصول الكامل لكافة معايير جهار 2025 v2 وقوائم التدقيق.</li>
            <li>المساعد الذكي (AI Copilot) لتوليد السياسات ومراجعة الامتثال.</li>
            <li>أداة التقييم الذاتي (SAT) ومصفوفة الأدلة والمطابقة.</li>
            <li>إدارة الفجوات وخطط العمل وتتبع التراخيص الطبية.</li>
          </ul>

          <p style="margin-top: 24px; text-align: center;">
            <a href="https://gahar-platform.eg/login" style="background: #2b6cb0; color: #ffffff; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: bold; display: inline-block;">
              تسجيل الدخول إلى لوحة التحكم
            </a>
          </p>

          <p style="margin-top: 28px; font-size: 13px; color: #718096; border-top: 1px solid #e2e8f0; padding-top: 14px;">
            الهيئة العامة للاعتماد والرقابة الصحية — جمهورية مصر العربية
          </p>
        </div>
      </div>
    </body>
    </html>
  `;

  return sendEmail({
    to: email,
    subject,
    html,
    deduplicationKey: `subscription_activated:${email}:${facilityName}`
  });
}

// -----------------------------------------------------------------------------
// WORKFLOW C: Secure Password Reset
// Single-use token, expires in 1 hour, never sends passwords
// -----------------------------------------------------------------------------

async function sendPasswordResetNotification(email, rawToken) {
  const resetUrl = `${process.env.APP_BASE_URL || 'https://gahar-platform.eg'}/reset-password?token=${rawToken}`;
  const subject = `[GAHAR] رابط إعادة تعيين كلمة المرور`;
  
  const html = `
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head><meta charset="utf-8"></head>
    <body style="font-family: Arial, sans-serif; background-color: #f7fafc; padding: 20px; color: #2d3748; line-height: 1.6;">
      <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 8px; border: 1px solid #e2e8f0; overflow: hidden;">
        <div style="background: #2d3748; padding: 20px; text-align: center; color: #ffffff;">
          <h2 style="margin: 0; font-size: 20px;">إعادة تعيين كلمة المرور</h2>
          <p style="margin: 4px 0 0; font-size: 13px; opacity: 0.9;">AccrediGo Security</p>
        </div>
        <div style="padding: 24px;">
          <p>تلقينا طلباً لإعادة تعيين كلمة المرور الخاصة بحسابكم على منصة اعتمادي جو.</p>
          <p>اضغط على الزر التالي لتعيين كلمة مرور جديدة آمنة:</p>
          
          <div style="text-align: center; margin: 24px 0;">
            <a href="${resetUrl}" style="background: #0f5257; color: #ffffff; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: bold; display: inline-block;">
              إعادة تعيين كلمة المرور
            </a>
          </div>

          <p style="font-size: 13px; color: #718096;">
            أو يمكنك نسخ الرابط التالي ولصقه في المتصفح مباشرة:<br/>
            <code style="word-break: break-all; color: #0f5257;">${resetUrl}</code>
          </p>

          <p style="background: #fffaf0; border: 1px solid #feebc8; padding: 10px; border-radius: 4px; font-size: 13px; color: #7b341e;">
            🔒 تنبيه أمني: هذا الرابط صالح للاستخدام مرة واحدة فقط وينتهي بعد 60 دقيقة. إذا لم تطلب إعادة تعيين كلمة المرور، يرجى تجاهل هذا البريد. لن تطلب الهيئة كلمة مرورك أبداً.
          </p>
        </div>
      </div>
    </body>
    </html>
  `;

  return sendEmail({
    to: email,
    subject,
    html,
    deduplicationKey: `pwd_reset:${email}:${rawToken.slice(0, 10)}`
  });
}

async function sendFacilityStatusNotification(email, facilityName, status, reason = '') {
  const isApproved = status === 'APPROVED' || status === 'ACTIVE';
  const subject = isApproved 
    ? `[GAHAR] تم اعتماد وتفعيل منشأة: ${facilityName}`
    : `[GAHAR] تحديث حالة التسجيل — ${facilityName}`;
  
  const html = `
    <h2>Account Status Update: ${facilityName}</h2>
    <p>Dear Administrator,</p>
    <p>Your registration status for <strong>${facilityName}</strong> has been updated to: <strong>${status}</strong>.</p>
    ${reason ? `<p><strong>Details / Reason:</strong> ${reason}</p>` : ''}
    <p>If you have any questions, please contact GAHAR support at support@gahar-platform.eg.</p>
  `;
  
  return sendEmail({
    to: email,
    subject,
    html,
    deduplicationKey: `status:${email}:${status}`
  });
}

// -----------------------------------------------------------------------------
// WORKFLOW E: Payment Proof Submitted — Super Admin Alert
// Notifies the super admin that a facility has submitted a payment for review.
// -----------------------------------------------------------------------------
async function sendPaymentVerificationNotification(payment, facilityName) {
  const superAdminEmail = process.env.SUPER_ADMIN_EMAIL || 'superadmin@gahar.gov.eg';
  const subject = `[GAHAR] طلب تحقق من دفع جديد — ${facilityName}`;
  const html = `
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head><meta charset="utf-8"></head>
    <body style="font-family: Arial, sans-serif; background-color: #f7fafc; padding: 20px; color: #2d3748; line-height: 1.6;">
      <div style="max-width: 600px; margin: 0 auto; background: #ffffff; border-radius: 8px; border: 1px solid #e2e8f0; overflow: hidden;">
        <div style="background: #744210; padding: 20px; text-align: center; color: #ffffff;">
          <h2 style="margin: 0; font-size: 20px;">إشعار: طلب تحقق من دفع</h2>
          <p style="margin: 4px 0 0; font-size: 13px; opacity: 0.9;">Payment Verification Required</p>
        </div>
        <div style="padding: 24px;">
          <p>مرحباً Super Admin،</p>
          <p>قامت منشأة <strong>${facilityName}</strong> بتقديم إثبات دفع وتطلب التحقق منه.</p>
          <div style="background: #fffaf0; border-right: 4px solid #dd6b20; padding: 14px; border-radius: 4px; margin: 18px 0;">
            <p style="margin: 4px 0;"><strong>رقم المرجع:</strong> ${payment.id}</p>
            <p style="margin: 4px 0;"><strong>المبلغ:</strong> ${payment.amount?.toLocaleString() || 'N/A'} جنيه مصري</p>
            <p style="margin: 4px 0;"><strong>طريقة الدفع:</strong> ${payment.payment_method || 'N/A'}</p>
            <p style="margin: 4px 0;"><strong>رقم العملية:</strong> ${payment.transaction_ref || 'غير محدد'}</p>
            <p style="margin: 4px 0;"><strong>تاريخ التقديم:</strong> ${new Date(payment.created_at).toLocaleString('ar-EG')}</p>
          </div>
          <p>يرجى مراجعة لوحة تحكم المسؤول للموافقة أو رفض طلب الدفع.</p>
          <p style="margin-top: 24px; font-size: 13px; color: #718096; border-top: 1px solid #e2e8f0; padding-top: 14px;">
            الهيئة العامة للاعتماد والرقابة الصحية — جمهورية مصر العربية
          </p>
        </div>
      </div>
    </body>
    </html>
  `;

  return sendEmail({
    to: superAdminEmail,
    subject,
    html,
    deduplicationKey: `payment_verify:${payment.id}`
  });
}

module.exports = {
  sendEmail,
  verifySmtpConnection,
  sendRegistrationWelcomeEmail,
  sendFacilityRegistrationNotification,
  sendSubscriptionActivatedNotification,
  sendPasswordResetNotification,
  sendFacilityStatusNotification,
  sendPaymentVerificationNotification,
};
