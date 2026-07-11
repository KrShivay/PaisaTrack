#!/usr/bin/env python3
"""Verify the pinned T-050 embedding model artifact (ADR 0007).

Downloads the generation-pinned Universal Sentence Encoder TFLite file,
verifies size and MD5 against the GCS metadata recorded in ADR 0007, then
prints the SHA-256 to paste into the ADR and AppConstants.

Usage:
  python3 tool/verify_embedder_model.py            # download + verify + sha256
  python3 tool/verify_embedder_model.py --dim      # also print embedding dim
                                                   # (requires: pip install mediapipe)

Stdlib-only unless --dim is used. No data leaves the machine.
"""

import hashlib
import sys
import tempfile
import urllib.request

# ADR 0007 pins — do not edit without a superseding ADR.
PINNED_URL = (
    "https://storage.googleapis.com/download/storage/v1/b/mediapipe-models/o/"
    "text_embedder%2Funiversal_sentence_encoder%2Ffloat32%2F1%2F"
    "universal_sentence_encoder.tflite?generation=1682480025058456&alt=media"
)
EXPECTED_SIZE = 6_120_274
EXPECTED_MD5 = "5123e0bb50df2978272ca25bfc7194f1"


def main() -> int:
    print(f"Downloading pinned artifact (generation 1682480025058456)...")
    with urllib.request.urlopen(PINNED_URL) as resp:
        data = resp.read()

    size = len(data)
    md5 = hashlib.md5(data).hexdigest()
    sha256 = hashlib.sha256(data).hexdigest()

    ok = True
    if size != EXPECTED_SIZE:
        print(f"FAIL size: got {size}, expected {EXPECTED_SIZE}")
        ok = False
    if md5 != EXPECTED_MD5:
        print(f"FAIL md5: got {md5}, expected {EXPECTED_MD5}")
        ok = False
    if not ok:
        print("Artifact does NOT match the ADR 0007 pin. Do not record this hash.")
        return 1

    print(f"OK   size:   {size}")
    print(f"OK   md5:    {md5}")
    print(f"SHA-256:     {sha256}")
    print("→ Record this SHA-256 in docs/decisions/0007-on-device-embedding-model.md")

    if "--dim" in sys.argv:
        try:
            from mediapipe.tasks import python as mp_python  # type: ignore
            from mediapipe.tasks.python import text as mp_text  # type: ignore
        except ImportError:
            print("--dim requires: pip install mediapipe")
            return 1
        with tempfile.NamedTemporaryFile(suffix=".tflite") as f:
            f.write(data)
            f.flush()
            embedder = mp_text.TextEmbedder.create_from_model_path(f.name)
            result = embedder.embed("HDFC BANK NEFT SALARY")
            dim = len(result.embeddings[0].embedding)
            print(f"Embedding dimension: {dim}")
            print("→ Record/confirm this dimension in ADR 0007 before T-051.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
