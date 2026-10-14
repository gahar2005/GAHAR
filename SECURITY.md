# GAHAR Security Specification & Hardening Report

## 1. Security Architecture Principles

- **Zero Client-Side Credentials**: No AI provider API keys (Groq, OpenAI, Google Gemini) or database passwords are ever delivered to the Flutter client bundle. All sensitive requests are mediated by the backend server.
- **Strict Multi-Tenancy**: The client cannot choose or forge its `facility_id`. Every tenant-scoped query relies exclusively on the verified cryptographically-signed JWT issued during authentication.
- **Row-Level Security (RLS)**: PostgreSQL tables have RLS enabled. Facility tenants can only select and mutate records where `facility_id = current_setting('request.jwt.claim.facility_id')`.
- **Role-Based Access Control (RBAC)**: Distinct permissions separate `SUPER_ADMIN`, `FACILITY_ADMIN`, `QUALITY_MANAGER`, `DEPARTMENT_HEAD`, and `STAFF`.

---

## 2. Hardening Measures Implemented

| Security Domain | Implementation Details | Status |
| :--- | :--- | :--- |
| **Authentication** | JSON Web Tokens (JWT) signed with SHA-256 HMAC (min 32-char secret). Expire in 24 hours. | Verified |
| **Password Storage** | `bcryptjs` hashing with salt rounds = 10. Raw passwords are never persisted. | Verified |
| **Cross-Tenant Guard** | Mismatches between JWT claim and `X-Facility-Id` header immediately terminate with `HTTP 403 Forbidden` and trigger a security audit event. | Verified |
| **File Storage Protection** | Uploaded documents are checked against allowed MIME types (`application/pdf`, `image/png`, `image/jpeg`, `application/msword`) and a 10MB file limit. Filenames are UUID-sanitized to prevent path traversal (`../`). | Verified |
| **Security Headers** | Helmet.js middleware active with CSP, HSTS, frameguard, and XSS filter. | Verified |
| **Audit Logging** | High-severity security events (`SUPER_ADMIN_LOGIN`, `SUSPICIOUS_CROSS_TENANT_ATTEMPT`, `UNAUTHORIZED_ROLE_ACCESS`) write immutable logs with IP, user agent, and timestamp. | Verified |

---

## 3. Security Verification Test Matrix

```
[TEST] Super Admin Authentication: HTTP 200 | Token Issued: true
[TEST] Cross-Tenant Header Block: HTTP 403 Forbidden (PASS)
[TEST] RBAC Unauthorized Facility Endpoint Block: HTTP 403 Forbidden (PASS)
[TEST] Unauthenticated Request Block: HTTP 401 Unauthorized (PASS)
[TEST] Spoofed Tenant Scoring Injection: Thwarted by JWT Derivation (PASS)
[TEST] PostgREST RLS Read Isolation: 0 cross-tenant records returned (PASS)
```
