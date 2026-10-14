const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');

const ALLOWED_MIME_TYPES = [
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'image/png',
  'image/jpeg',
  'text/plain',
];

const MAX_FILE_SIZE_BYTES = 15 * 1024 * 1024; // 15MB

const LOCAL_STORAGE_ROOT = path.join(__dirname, 'uploads');

// Ensure base local storage directory exists
if (!fs.existsSync(LOCAL_STORAGE_ROOT)) {
  fs.mkdirSync(LOCAL_STORAGE_ROOT, { recursive: true });
}

/**
 * Validates file type and size
 */
function validateFile({ mimeType, sizeBytes, originalName }) {
  if (sizeBytes > MAX_FILE_SIZE_BYTES) {
    return { valid: false, error: `File size exceeds maximum limit of 15MB (${(sizeBytes / (1024 * 1024)).toFixed(2)}MB).` };
  }

  // Extract extension
  const ext = path.extname(originalName || '').toLowerCase();
  const allowedExtensions = ['.pdf', '.doc', '.docx', '.xls', '.xlsx', '.png', '.jpg', '.jpeg', '.txt'];
  
  if (!allowedExtensions.includes(ext)) {
    return { valid: false, error: `Invalid file extension (${ext}). Allowed: PDF, DOC, DOCX, XLS, XLSX, PNG, JPG, TXT.` };
  }

  return { valid: true };
}

/**
 * Uploads a document to storage (Supabase Storage or tenant-isolated local storage)
 */
async function uploadDocument({ facilityId, originalName, mimeType, base64Content }) {
  const buffer = Buffer.from(base64Content, 'base64');
  
  const validation = validateFile({
    mimeType,
    sizeBytes: buffer.length,
    originalName,
  });

  if (!validation.valid) {
    throw new Error(validation.error);
  }

  const fileId = uuidv4();
  const ext = path.extname(originalName || '.pdf');
  const safeFileName = `${fileId}${ext}`;
  const storagePath = `facilities/${facilityId}/documents/${safeFileName}`;

  const isProduction = process.env.NODE_ENV === 'production';
  const hasSupabaseConfig = !!(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);

  // In production, refuse silent fallback to ephemeral container disk
  if (isProduction && !hasSupabaseConfig) {
    throw new Error('Supabase Storage configuration (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY) is required in production mode. Refusing silent fallback to ephemeral local storage.');
  }

  // Supabase Storage implementation
  if (hasSupabaseConfig) {
    try {
      const bucketName = process.env.SUPABASE_STORAGE_BUCKET || 'gahar-documents';
      const uploadUrl = `${process.env.SUPABASE_URL}/storage/v1/object/${bucketName}/${storagePath}`;

      const response = await fetch(uploadUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
          'Content-Type': mimeType || 'application/octet-stream',
          'x-upsert': 'true',
        },
        body: buffer,
      });

      if (response.ok) {
        return {
          fileId,
          storageProvider: 'SUPABASE_STORAGE',
          storagePath,
          sizeBytes: buffer.length,
          originalName,
          mimeType,
          publicUrl: null, // Healthcare documents remain private; served via authenticated /download
        };
      } else {
        const errorText = await response.text();
        if (isProduction) {
          throw new Error(`Failed to upload document to Supabase Storage (HTTP ${response.status}): ${errorText}`);
        }
        console.warn('⚠️ Supabase Storage upload failed, falling back to secure local tenant storage in dev:', errorText);
      }
    } catch (err) {
      if (isProduction) {
        throw err;
      }
      console.warn('⚠️ Supabase Storage upload failed, falling back to secure local tenant storage:', err.message);
    }
  }

  // Local Tenant-Isolated Storage (development/testing only)
  const tenantDir = path.join(LOCAL_STORAGE_ROOT, facilityId);
  if (!fs.existsSync(tenantDir)) {
    fs.mkdirSync(tenantDir, { recursive: true });
  }

  const destination = path.join(tenantDir, safeFileName);
  fs.writeFileSync(destination, buffer);

  return {
    fileId,
    storageProvider: 'LOCAL_SECURE_STORAGE',
    storagePath,
    localPath: destination,
    sizeBytes: buffer.length,
    originalName,
    mimeType,
    publicUrl: null,
  };
}

/**
 * Retrieves a document with strict facility ownership verification
 */
async function getDocumentBuffer({ facilityId, storagePath }) {
  const isProduction = process.env.NODE_ENV === 'production';
  const hasSupabaseConfig = !!(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);

  // Path traversal check: ensure path belongs to the given facility
  const expectedPrefix = `facilities/${facilityId}/`;
  if (!storagePath.startsWith(expectedPrefix)) {
    throw new Error('Access Denied: Cross-tenant storage access detected.');
  }

  if (isProduction && !hasSupabaseConfig) {
    throw new Error('Supabase Storage configuration is required to retrieve documents in production mode.');
  }

  // Supabase Storage fetch
  if (hasSupabaseConfig) {
    try {
      const bucketName = process.env.SUPABASE_STORAGE_BUCKET || 'gahar-documents';
      const fetchUrl = `${process.env.SUPABASE_URL}/storage/v1/object/${bucketName}/${storagePath}`;

      const res = await fetch(fetchUrl, {
        headers: {
          'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}`,
        },
      });

      if (res.ok) {
        const arrayBuf = await res.arrayBuffer();
        return Buffer.from(arrayBuf);
      } else if (isProduction) {
        throw new Error(`Failed to retrieve document from Supabase Storage (HTTP ${res.status}).`);
      }
    } catch (err) {
      if (isProduction) {
        throw err;
      }
      console.warn('⚠️ Supabase Storage fetch error:', err.message);
    }
  }

  // Local file lookup (development/testing fallback)
  const fileName = path.basename(storagePath);
  const localFile = path.join(LOCAL_STORAGE_ROOT, facilityId, fileName);

  if (fs.existsSync(localFile)) {
    return fs.readFileSync(localFile);
  }

  throw new Error('Document file not found.');
}

/**
 * Deletes a document with strict facility ownership check
 */
async function deleteDocumentFile({ facilityId, storagePath }) {
  const expectedPrefix = `facilities/${facilityId}/`;
  if (!storagePath.startsWith(expectedPrefix)) {
    throw new Error('Access Denied: Cannot delete file belonging to another facility.');
  }

  // Supabase Storage delete
  if (process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY) {
    try {
      const bucketName = process.env.SUPABASE_STORAGE_BUCKET || 'gahar-documents';
      const deleteUrl = `${process.env.SUPABASE_URL}/storage/v1/object/${bucketName}/${storagePath}`;
      await fetch(deleteUrl, {
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY}` },
      });
    } catch (_) {}
  }

  // Local delete
  const fileName = path.basename(storagePath);
  const localFile = path.join(LOCAL_STORAGE_ROOT, facilityId, fileName);
  if (fs.existsSync(localFile)) {
    fs.unlinkSync(localFile);
  }

  return true;
}

module.exports = {
  validateFile,
  uploadDocument,
  getDocumentBuffer,
  deleteDocumentFile,
  MAX_FILE_SIZE_BYTES,
  ALLOWED_MIME_TYPES,
};
