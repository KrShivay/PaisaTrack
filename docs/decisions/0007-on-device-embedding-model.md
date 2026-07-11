# ADR 0007 — Pinned on-device text-embedding model (T-050)

Status: accepted (@human approved via @claude session, 2026-07-11)

## Context

T-050 (on-device text embedder) was Blocked pending a pinned embedding
artifact and inference contract: exact model file/source + hash, license/
redistribution record, tokenizer/input tensor contract, output tensor/
dimension, and runtime version. ADR 0002 constrains the choice to free,
open-weight, on-device-only components via TFLite / MediaPipe Text Embedder,
with model download being the app's only permitted network use. The embedder
feeds merchant entity resolution (PLAN §7.3, cosine similarity over <2k
merchant strings) and the local classifier's features (§7.4), so the model
must be small, fast on low-end Android CPUs, and deterministic for fixed
inputs on a given device.

## Decision

Pin the **MediaPipe Universal Sentence Encoder** (dual-encoder, float32
TFLite) — the official recommended model for the MediaPipe Text Embedder
task — fetched lazily from Google's versioned model bucket.

### Artifact pin

- Model: Universal Sentence Encoder, float32, TFLite, ~6 MB
- Canonical versioned URL (pin this, never `latest`):
  `https://storage.googleapis.com/mediapipe-models/text_embedder/universal_sentence_encoder/float32/1/universal_sentence_encoder.tflite`
- Byte-exact immutable fetch (GCS generation-pinned):
  `https://storage.googleapis.com/download/storage/v1/b/mediapipe-models/o/text_embedder%2Funiversal_sentence_encoder%2Ffloat32%2F1%2Funiversal_sentence_encoder.tflite?generation=1682480025058456&alt=media`
- GCS object metadata (authoritative, read 2026-07-11 from the public GCS
  JSON API for the object above):
  - generation: `1682480025058456` (metageneration 1, finalized 2023-04-26)
  - size: `6120274` bytes
  - MD5: `5123e0bb50df2978272ca25bfc7194f1` (base64 `USPgu1DfKXgnLKJb/HGU8Q==`)
  - CRC32C: `7eb73e02` (base64 `frc+Ag==`)
  - The `float32/latest/` alias is byte-identical today (same MD5/CRC32C/
    size, generation 1682480025114200) but is mutable by definition — do not
    reference it in code.
- SHA-256: `<PENDING — run tool/verify_embedder_model.py once on a networked
  machine; it verifies size+MD5 against the values above, then prints the
  SHA-256 to record here and in AppConstants>`. The agent session that
  authored this ADR could not download the binary (sandbox egress blocked),
  and no fabricated hash is recorded. Until filled in, integrity enforcement
  in code MUST use size + MD5 from the metadata above, which came from
  Google's API, not from a third party.

### Inference contract

- Runtime: MediaPipe Tasks Text, Android Maven artifact
  `com.google.mediapipe:tasks-text:0.10.26` (pin exactly; newer 0.10.x exist
  — bumping requires re-running the determinism test and updating this ADR).
- Integration: Kotlin platform channel from the existing MainActivity channel
  pattern → `TextEmbedder.createFromOptions` with the model file path. The
  `mediapipe_text` Flutter plugin was evaluated and rejected: v0.0.1 (May
  2024), requires Flutter master channel + the `native-assets` experiment —
  not production-viable.
- Input: a single Dart `String` (the normalized merchant string). All
  tokenization/preprocessing is in-task (the model carries three string
  input tensors per the task docs; the Tasks API hides this — callers never
  build tensors).
- Output: one embedding head, float32 vector. Expected dimension: **100**
  (USE dual-encoder lite family). The dimension is NOT confirmed from a
  primary Google document; `tool/verify_embedder_model.py --dim` prints the
  real dimension via the mediapipe Python package, and the T-050
  deterministic test MUST assert the actual dimension and this ADR MUST be
  updated with the confirmed value before T-051 stores any embedding.
- Similarity: cosine, via our own pure-Dart implementation over the returned
  vectors (embeddings stored in `merchants.embedding` BLOB as float32
  little-endian, length = confirmed dimension).
- Determinism: float32 CPU inference on fixed model bytes is deterministic
  per device. The T-050 "deterministic output test over fixed inputs" runs
  as an on-device/integration test with golden vectors generated on the
  reference device — golden vectors are NOT portable across ABIs; the unit
  suite uses the fake/no-op embedder path.

### License / redistribution record

Google publishes no standalone license file for this model artifact; it is
distributed from Google's official MediaPipe Solutions models page for use
with the MediaPipe Tasks API (the MediaPipe project itself is Apache-2.0).
Recorded position: free to download and use on-device — satisfying ADR 0002 —
but with no explicit redistribution grant, so the model file is **never
committed to this repo, never bundled in the APK, and never re-hosted**.
The app lazily downloads it from the pinned URL on first use (WiFi-aware,
resumable not required at 6 MB, integrity-checked per the pin above, stored
app-private, delete control in Settings). If Google ever removes the object,
the generation pin fails closed and the embedder's no-op fallback keeps
ingest working (per T-050 AC).

### Alternatives considered

- **EmbeddingGemma-300M (LiteRT)** — newer and stronger, but ~200 MB,
  768-dim, Gemma Terms of Use rather than a plain OSS license, and heavier
  than needed for short merchant strings. Rejected for size/latency.
- **Sentence-transformers MiniLM converted to TFLite** — good quality but no
  official TFLite artifact; we would own the conversion, tokenizer contract,
  and hosting, violating the no-rehosting position above.
- **TFLite-support average word embedder** — smaller/faster but bag-of-words
  quality is too weak for merchant-name similarity (e.g. transliterated
  Indian merchant strings).

## Consequences

- T-050 unblocks: Embedder wraps the platform channel; no-op fallback when
  the model file is absent; ingest never blocks on the download.
- One new native dependency (`tasks-text`) pinned in `android/app/build.gradle`.
- Embedding dimension is device-model-version invariant only while the pin
  holds; any model bump invalidates stored `merchants.embedding` BLOBs and
  requires a re-embed migration — changing the pin requires a superseding
  ADR.
- Benchmarks (Google-published): ~18 ms CPU on Pixel 6 — comfortably inside
  the nightly 3-min budget and fine for per-ingest use.
