---
name: sms-template-authoring
description: >
  Use when adding or altering anything in assets/templates/, the template
  engine (lib/capture/template_engine/), or test/fixtures/sms/. Use when a
  new bank/wallet SMS format is being onboarded, an existing regex is being
  tightened, or a false-positive/false-negative parse is being fixed.
checklist:
  - Every new or changed template ships with >= 5 fixtures in
    test/fixtures/sms/<bank>/, including at least one negative case
    (failed/declined/OTP SMS that must NOT produce a transaction).
  - Fixtures are sanitized real SMS — account digits and names masked,
    everything else (spacing, punctuation, wording) byte-accurate to what
    the bank actually sends.
  - The regex uses named capture groups matching the field names in
    NormalizedTransactionRecord (amount, account, merchant, date, ref) —
    no positional-only groups for fields the normalizer needs by name.
  - The normalizer round-trips every known amount format (lakh commas,
    decimals, no-decimal), every known currency marker (Rs, Rs., ₹, INR),
    and every known date format used by templates for that bank.
  - Credited-vs-debited wording traps are covered: "credited" appearing in
    a debit-context sentence (e.g. refund confirmation) does not flip
    direction; "will be credited" (future) must not be parsed as a
    completed transaction at all.
  - Failed/declined/reversed SMS produce no transaction (or an explicit
    reversal record if the plan later adds that) — never a false debit/credit.
  - docs/sms-templates.md is updated with the new sender pattern and a short
    description of the format variant.
  - `flutter test test/capture/` passes with the new fixtures included, and
    the full fixture suite count in the PR description matches
    test/fixtures/sms/ actual file count (no fixtures added but not wired).
---

# SMS Template Authoring

Plan references: PLAN.md §3 (`assets/templates/*.json`, `test/fixtures/sms/`),
§6.3 (template JSON format, worked HDFC example), §7.1 (parser cascade),
§10 (fixture-driven testing is "the backbone").

## 1. Template JSON format

One file per sender family under `assets/templates/`, e.g. `hdfc.json`:

```json
{
  "sender_patterns": ["^[A-Z]{2}-HDFCBK$", "^HDFCBK$"],
  "templates": [
    {
      "id": "hdfc_upi_debit_v1",
      "regex": "Rs\\.?\\s?(?<amount>[\\d,]+\\.?\\d*) debited from a/c \\*\\*(?<account>\\d{4}) .* to (?<merchant>.+?) on (?<date>\\d{2}-\\d{2}-\\d{2}).*Ref (?<ref>\\d+)",
      "direction": "debit",
      "channel": "upi",
      "date_format": "dd-MM-yy"
    }
  ]
}
```

Rules:
- `sender_patterns` matches the SMS sender ID, not the body — keep it tight
  (real bank sender IDs are short alphanumeric codes); don't use `.*`.
- One `id` per template, versioned with a trailing `_v1`, `_v2` suffix —
  never edit an existing template's regex in place if it's already matched
  production SMS; add a new versioned template instead so historical
  fixtures for `_v1` keep proving `_v1` still works, and add fixtures for
  `_v2` separately. Only collapse versions when you've confirmed via
  fixtures that `_v2` is a strict superset.
- Templates are tried in file order per sender — put more specific
  patterns before general fallback ones for that sender.

## 2. Named-group regex conventions

Every field the normalizer consumes is a **named** group, matching
`NormalizedTransactionRecord` field names (or their raw pre-normalization
form): `amount`, `account`, `merchant`, `date`, `ref`. This is what lets
`field_normalizer.dart` be generic across all bank templates instead of
having per-bank normalization branches.

- `amount`: capture the raw numeric text including commas; normalization
  (lakh-comma stripping, decimal handling) happens in the normalizer, not
  the regex.
- `merchant`: capture greedily-but-boundedly (`.+?` with a clear stop
  anchor like `" on "` or `" Ref "`) — test against real fixtures, since
  merchant text length varies a lot and a too-greedy group silently eats
  the date/ref.
- `date`: capture in whatever format the bank sends; declare it via
  `date_format` in the template (`dd-MM-yy`, `dd/MM/yyyy`, etc.) — never
  assume ISO.
- Compile each template's regex once at registry load time and cache it per
  sender (existing convention, see WORKLOG T-012 note) — don't recompile
  per-message.

## 3. The fixture-first law

**No template is merged without ≥5 fixtures covering it**, including at
least one negative case. This is not a suggestion — a template with fewer
fixtures is unreviewed guesswork about a real bank's format.

Fixture layout (plan §3, §10): `test/fixtures/sms/<bank>/<case>.txt` +
`test/fixtures/sms/<bank>/<case>.expected.json` (or `null`/an explicit
"unparsed" marker for negative cases).

Minimum coverage per new template:
1. The canonical case (from the worked example you based the regex on).
2. An amount-format variant (comma/no-comma, or decimal/no-decimal).
3. A merchant-name edge case (very short, or containing punctuation the
   regex must not choke on).
4. **A negative case:** a failed/declined/reversed SMS from the same
   sender that must produce `expected: unparsed` (or equivalent) — never a
   transaction. This is the single most-skipped case in rushed template
   PRs; it's mandatory precisely because it's easy to skip.
5. A near-miss case: an SMS from the same sender that's a *different*
   message type (e.g. an OTP or promo) confirming the sender-pattern match
   alone doesn't cause a false parse.

## 4. Normalizer trap list

These are the specific bugs that have bitten real Indian bank SMS parsers.
Every one needs a unit test in `test/capture/template_engine/field_normalizer_test.dart`,
not just template-level coverage:

- **Lakh commas:** `1,00,000.50` is one lakh, not "1.00" + garbage — the
  normalizer must strip commas positionally, not assume Western
  thousands-grouping.
- **Currency markers:** `Rs`, `Rs.`, `₹`, `INR` all mean the same thing and
  must normalize to the same numeric amount with no marker in the stored
  value.
- **Date formats:** `dd-MM-yy` vs `dd/MM/yyyy` vs `dd-MMM-yy` (e.g.
  `05-Jul-26`) — declared per-template via `date_format`, never inferred
  from the string shape at parse time.
- **Credited-vs-debited wording traps:** "Rs.500 credited back to your
  a/c" in a *refund* message is a credit; "Rs.500 will be credited on
  processing" is a future event and must not create a transaction at all;
  "your a/c will be debited" (pre-auth notice) is also future, not actual.
  Direction comes from the template's declared `direction` plus tense
  words in the regex boundary, not a naive substring search for
  "credit"/"debit".
- **Failed/declined SMS must not parse into a transaction.** Words like
  "declined", "failed", "reversed", "insufficient balance" on an otherwise
  matching template must route to a dedicated failure template (or the
  sender's templates must simply not match that body) — verified by the
  negative fixture in every bank's fixture set.

## 5. Sanitizing a real SMS into a fixture

1. Take the real SMS body/sender exactly as received.
2. Mask account digits: replace real 4-digit (or longer) account/card
   fragments with a fixed placeholder like `4521` — keep the *number of
   digits* and surrounding format (`**4521`, `xx4521`) identical, just
   substitute digits so the original account isn't recoverable.
2b. If a real name appears (P2P transfer "to RAHUL K"), replace with a
   placeholder name of the same rough shape (`to JOHN D`) — never leave a
   real counterparty name in a committed fixture.
3. Do **not** alter spacing, punctuation, capitalization, or line breaks —
   the regex must be tested against the bank's actual formatting quirks,
   not a cleaned-up version of them.
4. Write the paired `.expected.json` by hand-computing what
   `NormalizedTransactionRecord` fields the fixture *should* produce
   (amount, direction, channel, ts, ref_id, etc.) — this is the assertion,
   not a snapshot of whatever the parser currently outputs.
5. Add one line to `docs/sms-templates.md` describing the new sender
   pattern/variant so the catalog stays a living, browsable doc.

## Related

- `flutter-conventions` — Result-typed parser failures.
- `intelligence-modules` — what happens after a template match (enrichment).
- `testing-discipline` — fixture harness mechanics and the manual QA list.
