# Archived ADR 0008 — Pinned on-device LLM artifact (T-075)

Status: superseded by ADR 0009 (2026-07-26)

The implementation now uses LiteRT-LM and Qwen3 0.6B mixed INT4. See
[ADR 0009](0009-litert-lm-runtime-and-qwen3.md) for the current contract.

## Context

T-075 (on-device LLM runtime foundation) was Blocked pending one actually
downloadable MediaPipe-compatible model artifact: URL, exact SHA-256, model
format/runtime version, and license/redistribution record. PLAN §2 and ADR
0002 name "Gemma-2B-class, open weights" via the MediaPipe LLM Inference API,
with `llama.cpp` FFI as recorded fallback. A critical practical constraint
surfaced during selection: **Gemma weights on Hugging Face and Kaggle are
license-gated** (require account + terms acceptance), which breaks T-075's
user-initiated, unauthenticated, resumable in-app download. ADR 0002's list
of acceptable alternatives already includes Qwen2.5-1.5B.

## Decision

Pin **Qwen2.5-1.5B-Instruct, dynamic_int8, 4096-token context, MediaPipe
`.task` bundle** from the official `litert-community` Hugging Face org
(Google AI Edge's LiteRT community releases). It is ungated, Apache-2.0,
and benchmarked by Google on the MediaPipe LLM Inference API.

### Artifact pin

- File: `Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task`
- Repo: `litert-community/Qwen2.5-1.5B-Instruct` (base model
  `Qwen/Qwen2.5-1.5B-Instruct`), `"gated": false` per the HF API
- Revision-pinned download URL (immutable; revision
  `19edb84c69a0212f29a6ef17ba0d6f278b6a1614`, 2025-11-25):
  `https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/19edb84c69a0212f29a6ef17ba0d6f278b6a1614/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task`
- Size: `1598556720` bytes (~1.6 GB)
- SHA-256: `82968d0a6c3872cf016fdbcfc591571605f4c7fd2b0f64d2533df502cc6596b3`
  (authoritative: Hugging Face LFS object id from the HF tree API, read
  2026-07-11 — not a third-party transcription)
- Supports HTTP Range requests via HF's CDN → the T-075 resumable download
  AC is implementable against this URL.

### Runtime / format contract

- Format: MediaPipe Task Bundle (`.task`) — model + tokenizer + metadata in
  one file; the LLM Inference API consumes it directly, no separate
  tokenizer artifact.
- Runtime: `com.google.mediapipe:tasks-genai:0.10.24` (latest published on
  Maven Central as of 2026-07-11; note upstream skipped genai for 0.10.26 —
  pin exactly, bump only with a determinism/regression pass and an ADR
  update).
- Inference: CPU via XNNPACK; prefill signatures 32/128/512/1280; context
  window 4096 tokens (ekv4096). Google-published benchmarks (S25 Ultra,
  int8/4096): prefill ~163 tk/s, decode ~26 tk/s, TTFT ~6.6 s, peak RSS
  ~2.2 GB. Older/low-RAM devices must gate on available memory → the
  "unsupported device → typed no-op" AC clause.
- The f32 variants (~6 GB) and ekv1280 variants exist in the same repo;
  ekv4096-int8 chosen: same 1.6 GB size as ekv1280 with 3.2× the context —
  headroom for T-076's intent prompts over long merchant lists.

### License / redistribution record

Apache-2.0 (both the base Qwen model and the litert-community conversion —
`license: apache-2.0` in the model card). Redistribution is therefore
permitted, but the model is still **never bundled in the APK** (T-075 AC:
user-initiated download, app-private storage, delete control in Settings)
and never committed to the repo (size). Download is the only network use,
per ADR 0002.

### Why not Gemma

Gemma-2B/Gemma-3 `.task` artifacts exist (Kaggle/HF) but are gated behind
Google's Gemma Terms: an in-app anonymous download would violate the gate or
require shipping credentials. If Google ever publishes an ungated Gemma
`.task`, revisiting requires a superseding ADR. `llama.cpp` FFI (GGUF
Qwen2.5-1.5B-Instruct-Q4_K_M, ungated) remains the recorded fallback if the
MediaPipe runtime proves unworkable — same model family keeps prompt design
portable.

## Consequences

- T-075 unblocks: `LlmRuntime` wraps the LLM Inference API behind the
  feature flag; download abstraction targets the pinned URL with SHA-256
  verification (hash above is enforceable in code immediately — unlike ADR
  0007, no backfill step needed since HF publishes LFS SHA-256).
- PLAN §2's "Gemma-2B-class" reading is amended by this ADR to "1–2B-class
  open instruction-tuned model"; Qwen2.5-1.5B-Instruct is the pinned
  instance.
- ~1.6 GB storage + ~2.2 GB peak RSS during inference; Settings must show
  size before download and expose delete (T-075 AC).
- Multilingual (incl. Hinglish-ish SMS text) capability is adequate for
  extraction/intent tasks; quality ceiling revisited only after Phase 4
  evidence, per ADR 0002 ("remedy is more templates, not cloud").
