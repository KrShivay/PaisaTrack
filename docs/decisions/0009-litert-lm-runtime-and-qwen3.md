# ADR 0009 — LiteRT-LM runtime and Qwen3 0.6B

Status: accepted (approved by product owner, 2026-07-26)

Supersedes the runtime and model selection in ADR 0008.

## Context

ADR 0008 described Qwen2.5-1.5B, while production code actually used a
Qwen2.5-0.5B MediaPipe `.task`. MediaPipe LLM Inference is maintenance-only,
and current Google edge-model releases target LiteRT-LM. Keeping model
metadata separately in native code, Dart UI, and ADR text caused the mismatch.

## Decision

- Runtime: `com.google.ai.edge.litertlm:litertlm-android:0.14.0`.
- Java/Kotlin target: 17. The pinned Android AAR compiles successfully with the
  existing toolchain; Java 21 is not required by this artifact.
- Model: `litert-community/Qwen3-0.6B`,
  `qwen3_0_6b_mixed_int4.litertlm`.
- Revision: `dd97997951bb15a2a71f539ba17f604707c0b11a`.
- Exact size: `497664000` bytes.
- SHA-256: `b1baab462f6be49d70eada79d715c2c52cd9ece0cad00bddf6a2c097d23498e9`.
- Context: 2048 tokens.
- Backend: CPU.
- License: Apache-2.0; the repository is ungated.

The revision, size, and SHA-256 were read from the Hugging Face model and tree
APIs for the exact revision on 2026-07-26. The LFS object identifier is the
artifact SHA-256. Production metadata lives in `LlmModelSpec.kt`; Settings
reads it through the native status contract instead of duplicating it.

LiteRT-LM receives separate system and user content and applies the packaged
chat template. Application code must not emit Qwen chat tokens. Every request
uses a new conversation, `/no_think`, and the existing deterministic
post-validation boundaries.

## Eligibility

The initial conservative admission rule requires:

- a non-low-RAM Android device;
- at least 4 GB total RAM;
- at least 1.5 GB currently available memory;
- enough storage for the partial, verified target, fallback copy, and 128 MiB
  headroom.

These values are safety gates, not performance claims. They must not be lowered
without physical-device PSS/LMK evidence. A process kill cannot be recovered
with an exception handler.

## Consequences

- MediaPipe `tasks-genai` is removed; `tasks-text` remains for the independent
  embedder.
- Downloads are revision-pinned, bounded, resumable, SHA-verified, and
  app-private.
- The previous application release/commit is the rollback mechanism; two LLM
  runtimes are not shipped together.
- Deterministic assistant, SMS, and narrative safeguards remain authoritative.

## Primary sources

- <https://ai.google.dev/edge/litert-lm/android>
- <https://huggingface.co/litert-community/Qwen3-0.6B>
- <https://huggingface.co/api/models/litert-community/Qwen3-0.6B>
