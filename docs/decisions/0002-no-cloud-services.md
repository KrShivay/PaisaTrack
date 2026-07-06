# ADR 0002: No Cloud Services — Free, On-Device-Only Intelligence

## Status

Accepted (2026-07-06)

## Context

PLAN.md originally allowed an optional, feature-flagged Phase 4 cloud LLM
fallback (Anthropic API) for last-resort SMS parsing and narrative insights,
behind an anonymizer. The developer has decided the project must use only free
options — no paid or subscription-based services anywhere, especially for
intelligence features. The cloud path was also the weakest point of the privacy
story ("nothing leaves by default" vs. "nothing *can* leave") and carried the
ongoing burden of adversarial anonymizer testing.

## Decision

Remove the cloud inference path entirely. All intelligence runs on-device with
free, open-weight components:

- Template engine (regex, pure Dart) remains the parsing backbone.
- Classifier: logistic regression in pure Dart.
- Embeddings: open sentence-embedding model via TFLite / MediaPipe Text
  Embedder.
- LLM fallback (Phase 4): MediaPipe LLM Inference with an open-weight
  Gemma-class model, or `llama.cpp` via FFI (e.g. Qwen2.5-1.5B, Phi-3-mini,
  Llama 3.2 1B). Model files are an optional in-app download from a pinned
  source, not bundled in the APK.
- Narrative insights (Phase 4) use the same local model or the deterministic
  insights engine.

Deleted from the plan: `cloud_extractor.dart`, `anonymizer.dart`, the
`enableCloudFallback` flag, the `'cloud'` value of `parse_source`, and all
anonymizer testing requirements.

Constraint going forward: no paid or subscription-based dependency, model,
API, or tool may be introduced. Every addition must be free and preferably
open source. The app makes no network calls carrying user data; the only
permitted network use is the one-time model download.

## Consequences

- Privacy claim strengthens to "no user data can leave the device" and becomes
  structurally enforceable (no networking code in data paths).
- No anonymizer to build or adversarially test; smaller codebase.
- Unmatched-SMS coverage depends entirely on the local model. A 1–2B quantized
  model is ~0.5–1.5 GB and slow on older phones; acceptable because it runs
  only on the rare unmatched SMS, but it must be an optional download.
- On-device LLM prompts may include raw SMS text, since inference never leaves
  the device; the release-log prohibition on raw SMS bodies still applies.
- If on-device extraction quality proves insufficient, the remedy is more
  templates and better fixtures — not a cloud call. Reversing this decision
  requires a superseding ADR.
