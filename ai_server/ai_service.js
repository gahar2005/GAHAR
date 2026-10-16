// =============================================================================
// GAHAR AI Service — Production Multi-Provider Integration
// Supported Providers: Groq, Google Gemini, OpenAI
// Features: Official SDKs, Provider Fallback, Dynamic Model Selection,
//           Strict Timeouts, Granular Error Classification, Zero Client Keys.
// =============================================================================

const Groq = require("groq-sdk");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const { OpenAI } = require("openai");

const TIMEOUT_MS = 15000; // 15 seconds max per provider attempt

// Initialize SDK clients exclusively on the backend (never sent to client)
const groqClient = process.env.GROQ_API_KEY ? new Groq({ apiKey: process.env.GROQ_API_KEY }) : null;
const geminiClient = process.env.GEMINI_API_KEY ? new GoogleGenerativeAI(process.env.GEMINI_API_KEY) : null;
const openaiClient = process.env.OPENAI_API_KEY ? new OpenAI({ apiKey: process.env.OPENAI_API_KEY }) : null;

// Helper: Wrap promise with timeout
function withTimeout(promise, ms = TIMEOUT_MS, label = "AI Request") {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms)
    ),
  ]);
}

// Classify error into structured categories without logging credentials or prompts
function classifyError(error) {
  const msg = error?.message || String(error);
  const status = error?.status || error?.statusCode;

  if (status === 401 || status === 403 || /invalid.*key|unauthorized|api_key/i.test(msg)) {
    return { type: "INVALID_API_KEY", status: 401, detail: "API key is invalid or rejected by provider." };
  }
  if (status === 429 || /quota|rate limit|too many requests|credits/i.test(msg)) {
    return { type: "RATE_LIMIT_OR_QUOTA_EXCEEDED", status: 429, detail: "Rate limit or usage quota exhausted." };
  }
  if (status === 404 || /not found|not available to new users|unsupported/i.test(msg)) {
    return { type: "MODEL_NOT_FOUND", status: 404, detail: "Configured model is unavailable or deprecated." };
  }
  if (status === 503 || status === 502 || status === 504 || /demand|service unavailable|timeout|timed out|econnreset/i.test(msg)) {
    return { type: "SERVICE_UNAVAILABLE", status: 503, detail: "Provider service temporarily unavailable or timed out." };
  }
  return { type: "PROVIDER_ERROR", status: status || 500, detail: msg.slice(0, 120) };
}

/**
 * Call Groq chat completions
 */
async function callGroq({ systemPrompt, userMessage }) {
  if (!groqClient) throw new Error("Groq API key not configured");

  const configuredModel = process.env.GROQ_MODEL || "llama-3.3-70b-versatile";
  const candidateModels = Array.from(new Set([
    configuredModel,
    "llama-3.3-70b-versatile",
    "llama-3.1-8b-instant"
  ])).filter(Boolean);

  let lastError = null;

  for (const model of candidateModels) {
    try {
      const call = groqClient.chat.completions.create({
        model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userMessage },
        ],
        max_tokens: 1024,
        temperature: 0.2,
      });

      const completion = await withTimeout(call, TIMEOUT_MS, `Groq (${model})`);
      const reply = completion.choices?.[0]?.message?.content?.trim();
      if (reply) {
        return { reply, provider: "groq", model };
      }
    } catch (err) {
      lastError = err;
      const classified = classifyError(err);
      console.warn(`⚠️ Groq model [${model}] failed (${classified.type}):`, classified.detail);
      // If invalid API key, don't retry other models on same provider
      if (classified.type === "INVALID_API_KEY") break;
    }
  }

  throw lastError || new Error("Groq returned empty response");
}

/**
 * Call Google Gemini content generation
 */
async function callGemini({ systemPrompt, userMessage }) {
  if (!geminiClient) throw new Error("Gemini API key not configured");

  const configuredModel = process.env.GEMINI_MODEL || "gemini-3.5-flash-lite";
  const candidateModels = Array.from(new Set([
    configuredModel,
    "gemini-3.5-flash-lite",
    "gemini-3.8-flash",
    "gemini-flash-latest"
  ])).filter(Boolean);

  let lastError = null;

  for (const modelName of candidateModels) {
    try {
      const model = geminiClient.getGenerativeModel({ model: modelName });
      const promptText = `${systemPrompt}\n\n[USER INQUIRY]:\n${userMessage}`;

      const call = model.generateContent(promptText);
      const result = await withTimeout(call, TIMEOUT_MS, `Gemini (${modelName})`);
      const response = await result.response;
      const reply = response.text()?.trim();
      if (reply) {
        return { reply, provider: "gemini", model: modelName };
      }
    } catch (err) {
      lastError = err;
      const classified = classifyError(err);
      console.warn(`⚠️ Gemini model [${modelName}] failed (${classified.type}):`, classified.detail);
      if (classified.type === "INVALID_API_KEY") break;
    }
  }

  throw lastError || new Error("Gemini returned empty response");
}

/**
 * Call OpenAI chat completions
 */
async function callOpenAI({ systemPrompt, userMessage }) {
  if (!openaiClient) throw new Error("OpenAI API key not configured");

  const configuredModel = process.env.OPENAI_MODEL || "gpt-4o-mini";
  const candidateModels = Array.from(new Set([
    configuredModel,
    "gpt-4o-mini",
    "gpt-4o",
    "gpt-3.5-turbo"
  ])).filter(Boolean);

  let lastError = null;

  for (const model of candidateModels) {
    try {
      const call = openaiClient.chat.completions.create({
        model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userMessage },
        ],
        max_tokens: 1024,
        temperature: 0.2,
      });

      const completion = await withTimeout(call, TIMEOUT_MS, `OpenAI (${model})`);
      const reply = completion.choices?.[0]?.message?.content?.trim();
      if (reply) {
        return { reply, provider: "openai", model };
      }
    } catch (err) {
      lastError = err;
      const classified = classifyError(err);
      console.warn(`⚠️ OpenAI model [${model}] failed (${classified.type}):`, classified.detail);
      if (classified.type === "INVALID_API_KEY") break;
    }
  }

  throw lastError || new Error("OpenAI returned empty response");
}

/**
 * Master multi-provider execution with ordered fallback:
 * Priority Order: Groq -> Gemini -> OpenAI
 */
async function generateCopilotReply({
  systemPrompt,
  userMessage,
  standardCode = null,
  standardGrounding = null,
  isArabic = false
}) {
  const providerErrors = {};

  // 1. Try Groq (if key present)
  if (groqClient) {
    try {
      const result = await callGroq({ systemPrompt, userMessage });
      console.log(`✅ AI Response generated via Groq [model: ${result.model}]`);
      return { success: true, ...result };
    } catch (err) {
      providerErrors.groq = classifyError(err);
    }
  } else {
    providerErrors.groq = { type: "NOT_CONFIGURED", detail: "GROQ_API_KEY is not set" };
  }

  // 2. Fallback to Google Gemini (if key present)
  if (geminiClient) {
    try {
      const result = await callGemini({ systemPrompt, userMessage });
      console.log(`✅ AI Response generated via Google Gemini [model: ${result.model}]`);
      return { success: true, ...result };
    } catch (err) {
      providerErrors.gemini = classifyError(err);
    }
  } else {
    providerErrors.gemini = { type: "NOT_CONFIGURED", detail: "GEMINI_API_KEY is not set" };
  }

  // 3. Fallback to OpenAI (if key present)
  if (openaiClient) {
    try {
      const result = await callOpenAI({ systemPrompt, userMessage });
      console.log(`✅ AI Response generated via OpenAI [model: ${result.model}]`);
      return { success: true, ...result };
    } catch (err) {
      providerErrors.openai = classifyError(err);
    }
  } else {
    providerErrors.openai = { type: "NOT_CONFIGURED", detail: "OPENAI_API_KEY is not set" };
  }

  // All providers failed: DO NOT hallucinate fake AI response
  console.error("❌ All AI providers failed or are unconfigured:", providerErrors);

  return {
    success: false,
    error: "AI_ALL_PROVIDERS_UNAVAILABLE",
    message: isArabic
      ? "خدمة المساعد الذكي غير متاحة حالياً بسبب انشغال أو توقف مزودي الخدمة السحابية. يرجى المحاولة لاحقاً."
      : "The AI Copilot service is currently unavailable. All configured AI providers failed. Please try again shortly.",
    providerErrors,
    standardReference: standardCode && standardGrounding ? standardGrounding : null,
    standardCode: standardCode || null
  };
}

/**
 * Returns current configuration status of all three AI providers
 */
function getProviderStatus() {
  return {
    groq: {
      configured: !!groqClient,
      model: process.env.GROQ_MODEL || "llama-3.3-70b-versatile",
    },
    gemini: {
      configured: !!geminiClient,
      model: process.env.GEMINI_MODEL || "gemini-3.5-flash-lite",
    },
    openai: {
      configured: !!openaiClient,
      model: process.env.OPENAI_MODEL || "gpt-4o-mini",
    },
  };
}

module.exports = {
  generateCopilotReply,
  callGroq,
  callGemini,
  callOpenAI,
  getProviderStatus,
  classifyError,
};
