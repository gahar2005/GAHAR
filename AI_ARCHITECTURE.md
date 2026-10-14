# GAHAR AI Architecture & RAG Specification

## 1. Grounded Accreditation Intelligence

The GAHAR AI Copilot is an assistive compliance advisor designed specifically for healthcare accreditation. It does NOT hallucinate standard requirements or guess accreditation legal statuses.

### Architectural Tiers:
1. **Official Standards Grounding**: Ingested from the GAHAR 2025 Hospital Standards handbook and the SAT 2025 workbook dataset.
2. **Facility Context Injection**: Current screen context, facility scope of service, bed size, active gaps, and document metadata are automatically supplied in the system prompt.
3. **Local Hybrid Retrieval (RAG)**:
   - Arabic text normalization (removing diacritics, tatweel, normalizing Alef, Teh Marbuta, Alef Maksura).
   - Arabic stemming and English synonym expansion.
   - BM25 ranker (`k1 = 1.2`, `b = 0.75`) filtering top-K relevant standards before prompting the LLM.
4. **Provider Fallback Strategy**:
   - Primary: Groq API (`llama-3.3-70b-versatile`, `llama-3.1-8b-instant`).
   - Fallback: Google Gemini API (`gemini-2.5-flash`).
   - Deterministic Fallback: Standard GAHAR evidence-of-compliance checklists when offline or if upstream APIs are unreachable.

---

## 2. AI Safety & Boundaries

- **No Official Determinations**: The AI explicitly reminds users: *"This is assistive guidance based on GAHAR 2025 reference standards. Formal compliance requires official GAHAR surveyor evaluation."*
- **Tenant Context Isolation**: Retrieval filters by tenant ID. Private documents or evidence belonging to Facility A are never accessible or included in the retrieval context of Facility B.
- **Client Key Isolation**: Zero AI keys exist on the client side. The Flutter app communicates exclusively through `/api/ai/copilot`.
