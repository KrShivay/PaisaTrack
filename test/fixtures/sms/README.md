# SMS Fixture Format

Use sanitized real messages only.

Each case should include:

- `<case>.txt` containing the sanitized SMS body
- `<case>.expected.json` containing the normalized transaction record

Organize by sender or bank, for example `test/fixtures/sms/hdfc/upi_debit_001.txt`.
