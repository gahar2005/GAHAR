-- =============================================================================
-- GAHAR Healthcare Accreditation Platform
-- Migration: Deterministic SAT Dataset Deduplication & Missing Standards Alignment
-- Target: public.sat_standards, public.sat_sub_evidence, public.sat_sub_scores
-- =============================================================================

BEGIN;

-- 1. Insert Missing GAHAR 2025 Standards (PCC.14, PCC.15, DAS.24, IMT.05)
INSERT INTO sat_standards (
    standard_code, chapter_code, item_number, category, standard_title,
    book_reference_code, workbook_sheet, sort_order, is_essential, is_active
) VALUES 
('PCC.14', 'PCC', 14, 'PATIENT-CENTERED CARE', 'The hospital’s responsibility towards the patient’s belongings is defined.', NULL, 'PCC', 730, false, true),
('PCC.15', 'PCC', 15, 'PATIENT-CENTERED CARE', 'The hospital improves provided services based on measured patients'' and families’ feedback.', NULL, 'PCC', 780, false, true),
('DAS.24', 'DAS', 24, 'DIAGNOSTIC AND ANCILLARY SERVICES', 'Point-of-care testing is monitored for providing accurate and reliable results.', NULL, 'DAS', 4460, false, true),
('IMT.05', 'IMT', 5, 'INFORMATION MANAGEMENT AND TECHNOLOGY', 'The hospital maintains data and information confidentiality and security.', NULL, 'IMT', 10320, false, true)
ON CONFLICT (standard_code) DO UPDATE SET
    chapter_code = EXCLUDED.chapter_code,
    category = EXCLUDED.category,
    standard_title = EXCLUDED.standard_title,
    workbook_sheet = EXCLUDED.workbook_sheet,
    sort_order = EXCLUDED.sort_order,
    is_active = true;

-- 2. Deterministic Sub-Evidence ID & Standard Code Updates
-- Update any sub-evidence records that had colliding IDs based on sort_order range
UPDATE sat_sub_evidence
SET standard_code = 'PCC.14', id = 'PCC.14.' || item_number
WHERE sort_order >= 730 AND sort_order <= 760 AND standard_code = 'PCC.13';

UPDATE sat_sub_evidence
SET standard_code = 'PCC.15', id = 'PCC.15.' || item_number
WHERE sort_order >= 780 AND sort_order <= 800 AND standard_code = 'PCC.13';

UPDATE sat_sub_evidence
SET standard_code = 'DAS.24', id = 'DAS.24.' || item_number
WHERE sort_order >= 4460 AND sort_order <= 4500 AND standard_code = 'DAS.23';

UPDATE sat_sub_evidence
SET standard_code = 'IMT.05', id = 'IMT.05.' || item_number
WHERE sort_order >= 10320 AND sort_order <= 10350 AND standard_code = 'IMT.04';

-- 3. Update any facility scores that were recorded under the previous standard codes
-- if the standard_code in sat_sub_scores indicated the target standard
UPDATE sat_sub_scores
SET standard_code = 'PCC.14', evidence_id = 'PCC.14.' || SUBSTRING(evidence_id FROM '\.([0-9]+)$')
WHERE standard_code = 'PCC.14' AND evidence_id LIKE 'PCC.13.%';

UPDATE sat_sub_scores
SET standard_code = 'PCC.15', evidence_id = 'PCC.15.' || SUBSTRING(evidence_id FROM '\.([0-9]+)$')
WHERE standard_code = 'PCC.15' AND evidence_id LIKE 'PCC.13.%';

UPDATE sat_sub_scores
SET standard_code = 'DAS.24', evidence_id = 'DAS.24.' || SUBSTRING(evidence_id FROM '\.([0-9]+)$')
WHERE standard_code = 'DAS.24' AND evidence_id LIKE 'DAS.23.%';

UPDATE sat_sub_scores
SET standard_code = 'IMT.05', evidence_id = 'IMT.05.' || SUBSTRING(evidence_id FROM '\.([0-9]+)$')
WHERE standard_code = 'IMT.05' AND evidence_id LIKE 'IMT.04.%';

COMMIT;
