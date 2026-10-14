const nodemailer = require('nodemailer');

const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@gahar-platform.eg';

// Transporter setup using environment variables
const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST || 'smtp.mailtrap.io',
  port: parseInt(process.env.SMTP_PORT || '2525', 10),
  secure: process.env.SMTP_SECURE === 'true',
  auth: {
    user: process.env.SMTP_USER || '',
    pass: process.env.SMTP_PASS || '',
  },
});

async function sendEmail({ to, subject, html, text }) {
  try {
    if (!process.env.SMTP_USER) {
      console.log(`✉️ [EMAIL DISPATCHED (Mock Log)] To: ${to} | Subject: ${subject}`);
      return { success: true, mock: true };
    }
    const info = await transporter.sendMail({
      from: `"GAHAR Healthcare Platform" <${process.env.SMTP_FROM || 'no-reply@gahar-platform.eg'}>`,
      to,
      subject,
      text: text || subject,
      html,
    });
    console.log(`✅ Email sent to ${to}: ${info.messageId}`);
    return { success: true, messageId: info.messageId };
  } catch (error) {
    console.error(`❌ Failed to send email to ${to}:`, error.message);
    return { success: false, error: error.message };
  }
}

async function sendFacilityRegistrationNotification(facilityData) {
  const subject = `[GAHAR] New Facility Registration: ${facilityData.name}`;
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
    <p>Please log into your GAHAR Super Admin Portal to review and approve/reject this request.</p>
  `;
  return sendEmail({ to: ADMIN_EMAIL, subject, html });
}

async function sendPaymentVerificationNotification(paymentData, facilityName) {
  const subject = `[GAHAR] Payment Proof Submitted: ${facilityName}`;
  const html = `
    <h2>Payment Verification Required</h2>
    <p>Facility <strong>${facilityName}</strong> submitted payment proof for verification:</p>
    <ul>
      <li><strong>Amount:</strong> EGP ${paymentData.amount}</li>
      <li><strong>Payment Method:</strong> ${paymentData.payment_method}</li>
      <li><strong>Transaction Ref:</strong> ${paymentData.transaction_ref || 'N/A'}</li>
      <li><strong>Proof URL:</strong> ${paymentData.proof_url || 'N/A'}</li>
    </ul>
    <p>Log in to GAHAR Super Admin Portal to verify and activate subscription.</p>
  `;
  return sendEmail({ to: ADMIN_EMAIL, subject, html });
}

async function sendRegistrationReceivedNotification(email, facilityName) {
  const subject = `[GAHAR] Registration Received — ${facilityName}`;
  const html = `
    <h2>Healthcare Facility Registration Received</h2>
    <p>Dear Administrator,</p>
    <p>We have successfully received the onboarding request for <strong>${facilityName}</strong> on the GAHAR Healthcare Accreditation Platform.</p>
    <p>Our compliance review team is currently verifying your submitted facility details and payment reference.</p>
    <p>You will receive an official activation confirmation within 24 business hours.</p>
    <br/>
    <p>Best regards,<br/>The GAHAR Egyptian Healthcare Accreditation Team</p>
  `;
  return sendEmail({ to: email, subject, html });
}

async function sendSubscriptionActivatedNotification(email, facilityName, planName, expiryDate) {
  const subject = `[GAHAR] Subscription Activated — ${facilityName}`;
  const html = `
    <h2>Your GAHAR Subscription is Active</h2>
    <p>Dear Administrator of <strong>${facilityName}</strong>,</p>
    <p>Your subscription to the <strong>${planName}</strong> plan has been activated.</p>
    <p><strong>Valid Until:</strong> ${new Date(expiryDate).toLocaleDateString('en-GB')}</p>
    <p>Your facility now has full access to GAHAR 2025 v2 checklists, AI Copilot, Gap Analysis, Document Library, and Mock Survey tools.</p>
    <br/>
    <p>Best regards,<br/>The GAHAR Team</p>
  `;
  return sendEmail({ to: email, subject, html });
}

async function sendSubscriptionExpirationReminder(email, facilityName, daysRemaining) {
  const subject = `[GAHAR Alert] Subscription Expiring in ${daysRemaining} Days — ${facilityName}`;
  const html = `
    <h2>Accreditation Subscription Renewal Notice</h2>
    <p>Dear Administrator,</p>
    <p>Your subscription for <strong>${facilityName}</strong> will expire in <strong>${daysRemaining} days</strong>.</p>
    <p>To avoid disruption of your GAHAR accreditation audit preparation and AI Copilot access, please renew your subscription or contact billing at billing@gahar-platform.eg.</p>
    <br/>
    <p>Best regards,<br/>The GAHAR Team</p>
  `;
  return sendEmail({ to: email, subject, html });
}

async function sendPasswordResetNotification(email, resetToken) {
  const resetUrl = `${process.env.APP_BASE_URL || 'https://gahar-platform.eg'}/reset-password?token=${resetToken}`;
  const subject = `[GAHAR] Password Reset Request`;
  const html = `
    <h2>GAHAR Password Reset</h2>
    <p>We received a request to reset your password. Use the secure link below to update your password:</p>
    <p><a href="${resetUrl}" style="background:#0F5257;color:#fff;padding:10px 18px;text-decoration:none;border-radius:6px;display:inline-block;">Reset Password</a></p>
    <p>Or paste this link into your browser: <code>${resetUrl}</code></p>
    <p><em>This link will expire in 1 hour. If you did not request this, please ignore this email.</em></p>
    <br/>
    <p>Best regards,<br/>GAHAR Security Team</p>
  `;
  return sendEmail({ to: email, subject, html });
}

async function sendFacilityStatusNotification(email, facilityName, status, reason = '') {
  const isApproved = status === 'APPROVED' || status === 'ACTIVE';
  const subject = isApproved 
    ? `[GAHAR] Account Approved & Activated - Welcome ${facilityName}!`
    : `[GAHAR] Account Registration Update - ${facilityName}`;
  
  const html = isApproved ? `
    <h2>Congratulations! Your Facility Account is Activated</h2>
    <p>Dear Administrator,</p>
    <p>Your healthcare facility <strong>${facilityName}</strong> has been officially approved and activated on the GAHAR Platform.</p>
    <p>You can now log in and access your full GAHAR 2025 Accreditation workspace, Gap Analysis tools, Document Library, and AI Copilot.</p>
    <br/>
    <p>Best regards,<br/>The GAHAR Team</p>
  ` : `
    <h2>Account Status Update</h2>
    <p>Dear Administrator,</p>
    <p>Your registration for <strong>${facilityName}</strong> status has been updated to: <strong>${status}</strong>.</p>
    ${reason ? `<p><strong>Reason / Note:</strong> ${reason}</p>` : ''}
    <p>If you have questions, please contact our support team at support@gahar-platform.eg.</p>
  `;
  return sendEmail({ to: email, subject, html });
}

module.exports = {
  sendEmail,
  sendFacilityRegistrationNotification,
  sendRegistrationReceivedNotification,
  sendPaymentVerificationNotification,
  sendFacilityStatusNotification,
  sendSubscriptionActivatedNotification,
  sendSubscriptionExpirationReminder,
  sendPasswordResetNotification,
};
