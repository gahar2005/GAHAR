# GAHAR Production Deployment Guide

## 1. Environment Configurations

Create a `.env` file inside `ai_server/` based on `.env.example`:

```bash
PORT=3000
NODE_ENV=production

# Database (PostgreSQL / Supabase)
DATABASE_URL=postgresql://postgres:[PASSWORD]@[HOST]:5432/postgres?sslmode=require
SUPABASE_URL=https://[PROJECT_REF].supabase.co
SUPABASE_SERVICE_ROLE_KEY=[SERVICE_ROLE_SECRET]

# JWT Authentication (generate with: openssl rand -base64 32)
JWT_SECRET=[SECURE_RANDOM_32_CHARACTERS]

# Super Admin Initial Bootstrapping
SUPER_ADMIN_EMAIL=superadmin@gahar.gov.eg
SUPER_ADMIN_PASSWORD=[SECURE_INITIAL_PASSWORD]

# AI Providers (Backend Only)
GROQ_API_KEY=[GROQ_API_KEY]
GROQ_MODEL=llama-3.3-70b-versatile
GEMINI_API_KEY=[GEMINI_API_KEY]
GEMINI_MODEL=gemini-2.5-flash

# SMTP Email Configuration (Nodemailer)
SMTP_HOST=smtp.mailgun.org
SMTP_PORT=587
SMTP_USER=postmaster@mg.gahar.gov.eg
SMTP_PASS=[SMTP_SECRET]
EMAIL_FROM="GAHAR Platform <noreply@gahar.gov.eg>"
```

---

## 2. Docker / Container Deployment

### Backend Service (Dockerfile)
```dockerfile
FROM node:24-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

### Flutter Web Frontend (Nginx Dockerfile)
```dockerfile
FROM nginx:alpine
COPY build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

## 3. Database Migration Execution

To apply the schema and seed the 277 GAHAR standards and 1,159 sub-evidence items to your production PostgreSQL/Supabase database:

```bash
cd ai_server
node run_migration.js
node seed_all_sat_data.js
```
