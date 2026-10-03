# ADR 0023: Render a static local UPI QR from stored VPA evidence

Status: Accepted for T-199 implementation

## Context

Transaction details and Sort already carry the source-stored counterparty VPA.
A scannable QR is useful at those same points, but a payment URI can carry
financial instructions. It must not fabricate or reuse an amount or imply that
the app verified the payee. Sort's review projection must expose the stored VPA
as its own optional field; a merchant grouping key is not payment evidence.

## Decision

- Add `qr_flutter` `^4.1.0` as an on-device QR renderer.
- Render a QR only when the trimmed stored VPA has a modest valid shape: a
  non-empty local part and handle with no whitespace, controls, or URI
  delimiters. Do not maintain a bank/provider allowlist.
- Pass the VPA as a distinct optional field through the review DTO and its
  repository mapper, preserving null values and backward-compatible DTO
  constructors. Never derive it from the resolved title or identity key.
- Construct a static URI using the standard encoded query parameters
  `pa=<exact trimmed VPA>`, `pn=<safe bounded transaction title or exact VPA
  fallback>`, and `cu=INR`. Include no `am`, `tr`, transaction ID,
  reference, or signed value. Show the payee name and exact VPA in the sheet;
  keep the encoded URI internal to generation/tests.
- Use a black QR on a white surface with a quiet zone of at least four modules.
  Keep the display large and responsive, with a 256dp minimum when available
  width permits, in a scrollable modal with an explicit close action.
- QR generation is local and informational. Do not perform VPA lookup,
  ownership verification, network access, payment-app launch, or payment
  execution. The QR is not proof that a payee controls the VPA.

## Consequences

The renderer adds a small UI dependency but does not change storage schema, parsing,
permissions, network policy, or transaction state. VPA format validation must
remain conservative enough to suppress malformed/unsafe strings without
depending on provider-specific handles. Only synthetic QR fixtures may be
exported for decoder or device QA.

Rollback: remove the QR dependency, action, payload helper, and modal; keep the
existing stored VPA display and copy behavior.
