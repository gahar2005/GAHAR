# GAHAR Platform Architecture Specification

## 1. System Architecture Diagram

```
+---------------------------------------------------------------------------------+
|                                 CLIENT LAYER                                    |
|  Flutter Web / Desktop / Mobile (Material 3 • GAHAR Design System • Bilingual)  |
+---------------------------------------------------------------------------------+
                                      │  HTTPS / REST / JWT
                                      ▼
+---------------------------------------------------------------------------------+
|                                 BACKEND API                                     |
|  Node.js (v24+) Express API • Helmet Security • Rate Limiter • CORS Validation  |
|                                                                                 |
|  +--------------------+  +--------------------+  +----------------------------+ |
|  | Auth & RBAC        |  | Tenant Context     |  | Audit Logging Engine       | |
|  | - Super Admin Auth |  | - JWT Extraction   |  | - Immutable Audit Events   | |
|  | - Facility Auth    |  | - Tenant Guard     |  | - Role & Tamper Tracking   | |
|  +--------------------+  +--------------------+  +----------------------------+ |
|                                                                                 |
|  +--------------------+  +--------------------+  +----------------------------+ |
|  | Applicability      |  | GAHAR SAT Scoring  |  | Document Lifecycle & Gov.  | |
|  | - 12 Questions     |  | - 277 Standards    |  | - Pre-Question Customize   | |
|  | - Scope Calculator |  | - 1,159 Sub-items  |  | - Version History (v1.x)   | |
|  | - Auto-Exclusions  |  | - Excel Formulations| | - Committee Sign-off       | |
|  +--------------------+  +--------------------+  +----------------------------+ |
|                                                                                 |
|  +--------------------+  +--------------------+  +----------------------------+ |
|  | Mock Survey Engine |  | Monitoring & ROI   |  | AI Copilot Proxy Gateway   | |
|  | - Tracer Checklists|  | - Health KPIs      |  | - No Keys on Client        | |
|  | - Surveyor Reports |  | - Transparent ROI  |  | - Groq / Gemini Fallback   | |
|  +--------------------+  +--------------------+  +----------------------------+ |
+---------------------------------------------------------------------------------+
                      │                                      │
                      ▼                                      ▼
+-----------------------------------+  +------------------------------------------+
|      POSTGRESQL / SUPABASE        |  |         TENANT ISOLATED STORAGE          |
|  - Relational Schema (33 tables)  |  |  - Base64 & Multipart Uploads           |
|  - Row Level Security (RLS)       |  |  - MIME & Extension Sanitization         |
|  - Multi-Tenant Foreign Keys      |  |  - Path Traversal Blockers               |
|  - In-Memory Development Store    |  |  - Strict Tenant Scoping                 |
+-----------------------------------+  +------------------------------------------+
```

## 2. Accreditation Journey Pipeline

The product lifecycle covers 4 rigorous phases:

### Phase 1: Readiness Review
1. **Facility Registration**: Gathers facility classification (Hospital, Specialized Center, Lab, Radiology), governorate, license numbers, bed capacity, and quality team details. Registered facilities start in `PENDING_REVIEW` state requiring platform administrator verification.
2. **Applicability Engine**: A 12-question diagnostic questionnaire checks surgical suites, radiology, in-house laboratory, academic residency, psychiatry, dialysis, blood bank, hyperbaric oxygen, and emergency. Excluded standards are omitted from SAT scoring denominators and document requirements.

### Phase 2: Accreditation Execution
3. **SAT Assessment**: Official dataset of 277 GAHAR standards and 1,159 sub-evidence requirements. Allows row-by-row scoring (`Fully Met = 2`, `Partially Met = 1`, `Not Met = 0`, `N/A = Excluded`).
4. **Deterministic Scoring**: Backend aggregates standard and chapter scores without AI inference. Overall readiness score = $\frac{\sum \text{Scored Items}}{\text{Applicable Items} \times 2} \times 100$.
5. **Gap Analysis**: Automatically generates gap entries for standards scoring $<100\%$, with severity tagging, recommended actions, and improvement scenarios.
6. **Action Plans**: Assigns tasks with due dates, departmental ownership, priority, and required Quality Committee verification.

### Phase 3: Survey Preparation
7. **Document Generation**: Grounded AI drafting of policies, procedures, SOPs, and forms. Facilities customize headers, document codes, owners, and effective dates.
8. **Document Governance & Version Control**: Multi-version retention (v1.0, v1.1, v2.0) with change summaries. Review states: `Draft → Under Review → Approved / Rejected / Revision Required`.
9. **Mock Survey**: Onsite audit simulation utilizing tracer methodology (patient tracers and systems tracers) yielding official readiness gap reports.

### Phase 4: Monitoring & Continuous Improvement
10. **Continuous Health Monitoring**: Live tracking of license expiration dates, recurring gaps, evidence freshness, and periodic document review cycles.
11. **Transparent ROI Engine**: Calculates net financial return on accreditation investment ($562\%$ average benchmark) based on verified infection control savings and length-of-stay reduction.
