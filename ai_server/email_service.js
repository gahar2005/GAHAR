const nodemailer = require('nodemailer');

const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@accredigo.eg';

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
      from: `"AccrediGo Platform" <${process.env.SMTP_FROM || 'no-reply@accredigo.eg'}>`,
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
  const subject = `[AccrediGo] New Facility Registration: ${facilityData.name}`;
  const html = `
    <h2>New Healthcare Facility Registration Request</h2>
    <p>A new facility has requested onboarding on AccrediGo:</p>
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
    <p>Please log into your Super Admin Portal to review and approve/reject this request.</p>
  `;
  return sendEmail({ to: ADMIN_EMAIL, subject, html });
}

async function sendPaymentVerificationNotification(paymentData, facilityName) {
  const subject = `[AccrediGo] Payment Proof Submitted: ${facilityName}`;
  const html = `
    <h2>Payment Verification Required</h2>
    <p>Facility <strong>${facilityName}</strong> submitted payment proof for verification:</p>
    <ul>
      <li><strong>Amount:</strong> EGP ${paymentData.amount}</li>
      <li><strong>Payment Method:</strong> ${paymentData.payment_method}</li>
      <li><strong>Transaction Ref:</strong> ${paymentData.transaction_ref || 'N/A'}</li>
      <li><strong>Proof URL:</strong> ${paymentData.proof_url || 'N/A'}</li>
    </ul>
    <p>Log in to Super Admin Portal to verify and activate subscription.</p>
  `;
  return sendEmail({ to: ADMIN_EMAIL, subject, html });
}

async function sendFacilityStatusNotification(email, facilityName, status, reason = '') {
  const isApproved = status === 'APPROVED' || status === 'ACTIVE';
  const subject = isApproved 
    ? `[AccrediGo] Account Approved & Activated - Welcome ${facilityName}!`
    : `[AccrediGo] Account Registration Update - ${facilityName}`;
  
  const html = isApproved ? `
    <h2>Congratulations! Your Facility Account is Activated</h2>
    <p>Dear Administrator,</p>
    <p>Your healthcare facility <strong>${facilityName}</strong> has been officially approved and activated on AccrediGo.</p>
    <p>You can now log in and access your full GAHAR 2025 Accreditation workspace, Gap Analysis tools, Document Library, and AI Copilot.</p>
    <br/>
    <p>Best regards,<br/>The AccrediGo Team</p>
  ` : `
    <h2>Account Status Update</h2>
    <p>Dear Administrator,</p>
    <p>Your registration for <strong>${facilityName}</strong> status has been updated to: <strong>${status}</strong>.</p>
    ${reason ? `<p><strong>Reason / Note:</strong> ${reason}</p>` : ''}
    <p>If you have questions, please contact our support team at support@accredigo.eg.</p>
  `;
  return sendEmail({ to: email, subject, html });
}

module.exports = {
  sendEmail,
  sendFacilityRegistrationNotification,
  sendPaymentVerificationNotification,
  sendFacilityStatusNotification,
};
