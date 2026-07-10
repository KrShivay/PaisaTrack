# SMS Fixture Format

Use sanitized real messages only.

Each case should include:

- `<case>.txt` containing the sanitized SMS body
- `<case>.expected.json` containing fixture metadata and expected parser output

Fixture metadata may add `"provenance": "public"` for a real, publicly posted
SMS. Its absence means `device`, preserving the existing fixture contract.

Organize by sender or bank, for example `test/fixtures/sms/hdfc/upi_debit_001.txt`.

Expected JSON shape:

```json
{
  "sender": "XX-HDFCBK",
  "received_at": 1783209600000,
  "expected": {
    "ok": {
      "amount": 125.5,
      "direction": "debit",
      "channel": "upi",
      "merchant_raw": "SANITIZED MERCHANT",
      "counterparty_vpa": null,
      "account_hint": "1234",
      "balance_after": null,
      "ref_id": "SANITIZEDREF",
      "ts": 1783209600000,
      "parse_source": "template",
      "parse_confidence": 1.0
    }
  }
}
```

Parser misses use `"expected": {"err": "unparsed"}`. The helper in
`test/fixtures/sms_fixture_runner.dart` scans nested bank/sender folders,
returns an empty case list for an empty root, and compares parser output with
this stable shape.
