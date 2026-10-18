# AccrediGo (GAHAR) — Production Deployment & Configuration Guide

This guide documents the deployment configuration for the **AccrediGo (GAHAR) Healthcare Accreditation Platform** on Render and GitHub.

---

## 1. Render Web Service Deployment Configuration

### Service Setup:
- **Environment**: Node.js
- **Root Directory**: `ai_server` (recommended) or root repository
- **Build Command**: `npm install`
- **Start Command**: `node server.js`
- **Health Check Path**: `/health`
- **Auto-Deploy**: Yes (on push to `main` branch)

---

## 2. Environment Variables Configuration

Configure the following environment variables in your Render Web Service dashboard under **Environment**:

| Environment Variable | Required | Description / Production Recommendation |
| :--- | :---: | :--- |
| `NODE_ENV` | **Yes** | Set to `production`. Enforces strict security and refuses silent fallbacks. |
| `PORT` | Auto | Injected automatically by Render (do not hardcode). |
| `DATABASE_URL` | **Yes** | Pooled connection string to live Supabase / PostgreSQL database (`?sslmode=require`). |
| `JWT_SECRET` | **Yes** | Strong cryptographic secret (minimum 32 characters, e.g. `openssl rand -base64 32`). |
| `SUPABASE_URL` | **Yes** | Supabase project URL (e.g. `https://your-project.supabase.co`). |
| `SUPABASE_SERVICE_ROLE_KEY` | **Yes** | Trusted backend-only service role secret key. Never expose in Flutter or client code. |
| `SUPABASE_STORAGE_BUCKET` | Optional | Document bucket name; defaults to `gahar-documents` (must remain private). |
| `SUPER_ADMIN_EMAIL` | **Yes** | Official Super Admin email (e.g. `superadmin@gahar.gov.eg`). |
| `SUPER_ADMIN_PASSWORD` | **Yes** | Strong initial Super Admin password. Hashed with bcrypt on first boot. |
| `GROQ_API_KEY` | Optional | Fast LLM inference key (Groq Cloud). |
| `GROQ_MODEL` | Optional | Defaults to `llama-3.3-70b-versatile` (fallbacks: `llama-3.1-8b-instant`). |
| `GEMINI_API_KEY` | Optional | Google Gemini API key. |
| `GEMINI_MODEL` | Optional | Defaults to `gemini-3.5-flash-lite` (fallbacks: `gemini-3.8-flash`, `gemini-flash-latest`). |
| `OPENAI_API_KEY` | Optional | OpenAI API key for GPT models. |
| `OPENAI_MODEL` | Optional | Defaults to `gpt-4o-mini` (fallbacks: `gpt-4o`, `gpt-3.5-turbo`). |
| `SMTP_HOST` | Optional | Outgoing SMTP host (e.g. `smtp.mailgun.org`, `smtp.sendgrid.net`). |
| `SMTP_PORT` | Optional | SMTP port (e.g. `587` for STARTTLS, `465` for SSL/TLS). |
| `SMTP_USER` | Optional | SMTP authentication username. |
| `SMTP_PASS` | Optional | SMTP authentication password. |
| `SMTP_FROM` | Optional | Sender address (e.g. `"AccrediGo / GAHAR Platform" <no-reply@gahar-platform.eg>`). |
| `APP_BASE_URL` | Optional | Frontend application URL for password reset links (e.g. `https://gahar-platform.eg`). |

---

## 3. Database Initialization & Schema Migrations

For a brand-new Supabase project:

1. **Option A (Recommended — Complete Schema + Seed Data)**:
   Applies base tables, v2 expansion tables, RLS policies, and seeds all 281 standards and 1,159 sub-evidence requirements in a single idempotent run:
   ```bash
   cd ai_server
   node seed_all_sat_data.js
   ```

2. **Option B (DDL Migrations Only)**:
   If seeding is handled separately or in stages:
   ```bash
   cd ai_server
   node run_migration.js
   ```

3. **Option C (Automatic on First Boot)**:
   When `DATABASE_URL` is configured, `server.js` automatically executes `initializeDatabase()` on startup, applying `schema.sql` -> `gahar_v2_migration.sql` -> `fix_sat_dataset_duplicates.sql` using idempotent `IF NOT EXISTS` / `ON CONFLICT` guards.

### Row Level Security (RLS) Architecture & Rules:
- **Backend Service Context**: The Express backend connects to PostgreSQL / Supabase via `DATABASE_URL` (service role connection), which bypasses RLS by PostgreSQL design.
- **Tenant Isolation**: In the backend API layer, tenant isolation is strictly enforced by the `enforceTenantIsolation` middleware (`req.tenantFacilityId = req.user.facilityId`) and parameterized `WHERE facility_id = $1` queries.
- **Client Defense-in-Depth**: The RLS policies in `schema.sql` and `gahar_v2_migration.sql` protect direct client access via Supabase PostgREST (using `request.jwt.claims`).
- **CRITICAL**: Do **NOT** enable `FORCE ROW LEVEL SECURITY` on public tables. Doing so would block backend service queries when `request.jwt.claims` session settings are absent.
- No existing production data will be deleted or overwritten by re-running migrations.
- Password hashes for established accounts are preserved across server restarts.

---

## 4. Verification & Health Probes

- **Liveness & Readiness Probe**: `GET https://[your-service].onrender.com/health` returns HTTP 200 with runtime service status.
- **Run Automated Test Suite**:
  ```bash
  cd ai_server
  npm test
  ```
  Runs the comprehensive 22-point production test suite verifying authentication, multi-tenant isolation, AI provider fallback, signed URLs, and email flows.
