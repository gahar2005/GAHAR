-- =============================================================================
-- GAHAR Platform - Migration V4: Document Metadata Schema Expansion
-- Phase 1 Production-Readiness (Prepared Migration - DO NOT EXECUTE AUTOMATICALLY)
-- =============================================================================
-- This migration expands the 'documents' table to explicitly hold storage metadata
-- and file characteristics alongside existing GAHAR compliance fields.
--
-- STATUS: PREPARED ONLY. Do NOT run against live Supabase database without review.
-- Backward Compatibility: The backend code is adapted to function with or without
-- these additional columns by mapping to/from 'file_path'.
-- =============================================================================

-- 1. Explicit storage path (complements/mirrors file_path for clarity)
ALTER TABLE documents ADD COLUMN IF NOT EXISTS storage_path VARCHAR(512);

-- 2. Storage provider identifier ('SUPABASE_STORAGE' or 'LOCAL_SECURE_STORAGE')
ALTER TABLE documents ADD COLUMN IF NOT EXISTS storage_provider VARCHAR(64) DEFAULT 'SUPABASE_STORAGE';

-- 3. File size in bytes
ALTER TABLE documents ADD COLUMN IF NOT EXISTS file_size BIGINT;

-- 4. MIME type (e.g., 'application/pdf', 'image/png')
ALTER TABLE documents ADD COLUMN IF NOT EXISTS mime_type VARCHAR(128);

-- 5. Email of the uploading user (decoupling from UUID foreign key)
ALTER TABLE documents ADD COLUMN IF NOT EXISTS uploaded_by_email VARCHAR(255);

-- 6. Backfill storage_path from file_path for existing rows
UPDATE documents 
SET storage_path = file_path 
WHERE storage_path IS NULL AND file_path IS NOT NULL;

-- 7. Performance index for active vs soft-deleted queries scoped by tenant
CREATE INDEX IF NOT EXISTS idx_documents_facility_deleted 
ON documents(facility_id, deleted_at);
