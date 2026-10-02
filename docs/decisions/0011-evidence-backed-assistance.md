# ADR 0011 — Evidence-backed transaction assistance and AI

Status: accepted-in-part, 2026-10-02. T-178a slice a4 implements the typed
insight claim and fixed-rendering portions below; remaining assistant language
work stays under T-178c. No schema or model/runtime dependency was added.

## Context

Repeated transaction editing defeats automatic capture. Existing categorization,
feedback, identity and analytics components provide a foundation, but helper
logic and plausible model output do not establish production accuracy.

## Proposed decision

- Keep raw SMS/statement evidence and original extracted spans immutable.
  Normalized transaction values may change through explicit correction, retaining
  old/new values, actor/source, evidence and edit version. Derived fields carry
  provenance and explicit confirmation state.
- Separate payee identity, category, payment purpose and spending eligibility.
  A personal VPA does not alone establish a non-spending transfer.
- Reuse one correction/undo path and stable identity rules across capture,
  detail, grouped review and future evidence imports.
- Train from explicit confirmed outcomes; silence and automatic assignments
  are not labels. Undo invalidates corresponding feedback and cached results.
- Deterministic queries own arithmetic and source links. Statistical models may
  estimate future values with uncertainty. The LLM may interpret questions or
  choose supported claim IDs, but cannot invent financial facts or write SQL.
- Estimates, suggestions and scenarios never become settled transactions.
- All financial processing remains on-device under ADR 0002. Optional model
  failure leaves capture, queries and explicit rules usable.

## Consequences and alternatives

A larger model alone cannot recover an absent payment purpose. Prioritize
identity, trusted feedback and grouped review before adding model calls.
Free-form generated insights are rejected in favor of typed, evidenced claims;
this limits language flexibility but makes the answer auditable.

Before implementation, T-177a must review this proposal, audit reuse of existing
schema and define additive migrations only where needed. Receipt OCR and new
model/runtime dependencies need a separate feasibility/privacy decision.

See [feature plan](../plans/smart-transaction-assistance.md) and
[AI report](../reports/grounded-ai-opportunities.md) for delivery and evaluation.
