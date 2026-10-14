# GAHAR Database & Schema Documentation

## 1. Relational Schema Architecture

The database is built on PostgreSQL / Supabase with comprehensive multi-tenant isolation, foreign key constraints, indexing, and Row Level Security (RLS).

### Core Tables Summary

| Table Name | Description | Tenant Isolation |
| :--- | :--- | :--- |
| `subscription_plans` | Global platform pricing tiers (Standard Hospital, Enterprise, Lab) | Platform Global |
| `facilities` | Registered healthcare organizations with status and profile | Tenant Row Level |
| `users` | Facility staff and platform Super Admins with role enums | `facility_id` Foreign Key |
| `payments` | Subscription payment records and proof upload metadata | `facility_id` Foreign Key |
| `sat_standards` | Official reference catalog of 277 GAHAR standards across 16 chapters | Global Reference (RLS Enabled) |
| `sat_sub_evidence` | 1,159 sub-evidence requirements from the GAHAR SAT 2025 Excel | Global Reference (RLS Enabled) |
| `sat_scores` | Facility standard-level assessment scores (`FULLY_MET`, `PARTIALLY_MET`, `NOT_MET`, `NOT_APPLICABLE`) | `facility_id` Scoped |
| `sat_sub_scores` | Facility sub-evidence assessment scores (0, 1, 2) | `facility_id` Scoped |
| `facility_applicability` | Scoping answers and auto-calculated excluded standard codes | `facility_id` Scoped |
| `gap_items` | Non-compliance records linked to standards with severity | `facility_id` Scoped |
| `action_plans` | Tasks derived from gaps with department assignees and due dates | `facility_id` Scoped |
| `licenses` | Medical and facility permits with expiration timeline tracking | `facility_id` Scoped |
| `documents` | Hospital policies, SOPs, forms with version strings and review states | `facility_id` Scoped |
| `document_versions` | Immutable historical snapshots (v1.0, v1.1) with change notes | Document / Facility Linked |
| `evidence_items` | Uploaded attachments supporting SAT criteria compliance | `facility_id` Scoped |
| `mock_surveys` | Simulated survey requests, tracer checklists, and surveyor findings | `facility_id` Scoped |
| `audit_logs` | Immutable security and operational activity log | Facility & User Linked |

---

## 2. Row Level Security (RLS) Policies

All facility-specific tables enforce RLS:

```sql
-- Example RLS Policy for SAT Scores
ALTER TABLE public.sat_scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY sat_scores_tenant_isolation ON public.sat_scores
    FOR ALL
    USING (
        facility_id = NULLIF(current_setting('request.jwt.claim.facility_id', true), '')::uuid
        OR NULLIF(current_setting('request.jwt.claim.role', true), '') = 'SUPER_ADMIN'
    );
```

Reference tables (`sat_standards` and `sat_sub_evidence`) have read-only RLS enabled for authenticated users, preventing unauthorized standard mutation while permitting Super Admin governance.
