# GAHAR Healthcare Accreditation Platform

**Enterprise SaaS Platform for Healthcare Facility Accreditation Readiness & Continuous Compliance**  
*Grounded in the Official GAHAR (General Authority for Healthcare Accreditation and Regulation) 2025 Hospital Standards*

---

## 🏥 Overview

The **GAHAR Healthcare Accreditation Platform** is an independent, end-to-end digital accreditation workspace engineered for Egyptian healthcare facilities (Hospitals, Specialized Centers, Diagnostic Facilities, and Primary Care Centers). It systematically guides healthcare facilities through all 4 accreditation phases:

- **PHASE 1 — READINESS REVIEW**: Multi-step registration, facility profile, clinical applicability check, and scoping.
- **PHASE 2 — ACCREDITATION EXECUTION**: Self-Assessment Tool (SAT), deterministic chapter/standard scoring, gap analysis engine, and action plan assignments.
- **PHASE 3 — SURVEY PREPARATION**: Pre-survey readiness audit, tracer methodology checklist, mock survey requests, and finding reports.
- **PHASE 4 — MONITORING & CONTINUOUS IMPROVEMENT**: Real-time compliance health tracking, license expiry reminders, document review cycles, and transparent financial & operational ROI analytics.

---

## 🚀 Key Architectural Modules

1. **Applicability Engine**: Dynamic clinical questionnaire (12 scoping questions) that automatically computes excluded standards and removes non-applicable standards from SAT scoring denominators, action plans, and documentation requirements.
2. **SAT Scoring Engine**: 277 official standards and 1,159 sub-evidence criteria extracted programmatically from the *Hospital Full Accreditation SAT 2025* official dataset, scored deterministically (Fully Met = 2, Partially Met = 1, Not Met = 0, N/A = Excluded).
3. **Gap Analysis & Action Plans**: Converts sub-compliant standard scores into prioritized tasks with department assignment, due dates, evidence requirements, and Quality Committee verification workflows.
4. **Document Generation & Governance**: Grounded AI drafting of facility policies, procedures, and forms with pre-question customization, immutable version history (v1.0, v1.1, v2.0), and governance approvals (Draft → Under Review → Approved).
5. **Continuous Monitoring & ROI Analytics**: Post-accreditation tracking with transparent formulas calculating quantified savings in infection prevention, adverse event avoidance, and length-of-stay reduction.
6. **Strict Multi-Tenancy & Zero Client Keys**: All facility data is isolated via verified JWT claims; zero third-party AI keys reside in the client application.

---

## 🛠️ Technology Stack

- **Frontend**: Flutter 3.47+ (Web, Desktop, iOS, Android) with Material 3, custom healthcare emerald/teal/gold design system, and bilingual English/Arabic RTL support.
- **Backend API**: Node.js v24+, Express, Helmet, CORS, JWT authentication, bcryptjs password hashing.
- **Database & RLS**: PostgreSQL / Supabase with Row Level Security (RLS) policies and tenant isolation triggers.
- **Storage**: Tenant-isolated file storage with MIME/extension validation and path traversal protections.
- **AI & RAG**: Context-aware Copilot proxying to Groq (`llama-3.3-70b-versatile`) and Google Gemini (`gemini-2.5-flash`) with local BM25 standard retrieval.

---

## 📦 Quick Start

### 1. Backend Server Setup
```bash
cd ai_server
npm install
cp .env.example .env
# Edit .env with your PostgreSQL/Supabase and AI keys
node server.js
```

### 2. Flutter Client Setup
```bash
flutter pub get
flutter run -d chrome
```

### 3. Running Verification Tests
```bash
# Backend Test Suite
cd ai_server
node test_backend.js
node test_sat_security.js
node test_security_audit.js
node test_gahar_full_platform.js

# Flutter Analysis & Unit Tests
flutter analyze
flutter test
```
