const { query, memoryDb } = require('./db');
const { v4: uuidv4 } = require('uuid');

/**
 * Record a security audit event into database & log stream.
 * Strips sensitive keys like password, token, secret.
 */
async function logAuditEvent({ facilityId = null, userId = null, userEmail = null, action, entityType = null, entityId = null, details = {}, req = null }) {
  try {
    const ipAddress = req ? (req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '127.0.0.1') : '127.0.0.1';
    
    // Sanitize details object (remove passwords/tokens)
    const sanitizedDetails = { ...details };
    delete sanitizedDetails.password;
    delete sanitizedDetails.password_hash;
    delete sanitizedDetails.token;
    delete sanitizedDetails.apiKey;

    const auditItem = {
      id: uuidv4(),
      facility_id: facilityId,
      user_id: userId,
      user_email: userEmail,
      action,
      entity_type: entityType,
      entity_id: entityId,
      details: sanitizedDetails,
      ip_address: ipAddress,
      timestamp: new Date().toISOString()
    };

    console.log(`🔒 [AUDIT] Action: ${action} | User: ${userEmail || userId || 'System'} | Facility: ${facilityId || 'N/A'}`);

    // Try SQL query insert
    const sql = `
      INSERT INTO audit_logs (id, facility_id, user_id, user_email, action, entity_type, entity_id, details, ip_address, timestamp)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
    `;
    const res = await query(sql, [
      auditItem.id,
      auditItem.facility_id,
      auditItem.user_id,
      auditItem.user_email,
      auditItem.action,
      auditItem.entity_type,
      auditItem.entity_id,
      JSON.stringify(auditItem.details),
      auditItem.ip_address,
      auditItem.timestamp
    ]);

    if (!res) {
      memoryDb.audit_logs.unshift(auditItem);
    }
    return auditItem;
  } catch (err) {
    console.error('⚠️ Audit log error:', err.message);
  }
}

module.exports = {
  logAuditEvent
};
