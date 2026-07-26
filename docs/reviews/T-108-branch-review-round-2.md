# Review Round 2 — Verification of Fixes (`codex/t108-bank-capture-coverage`)

**Scope:** re-verification of the 3 CRITICAL / 23 MAJOR / MINOR findings from
`T-108-branch-code-review.md` against the current working tree (uncommitted).

**Verdict:** **Request Changes** — the *design* of nearly every fix is right, and
I re-verified the behavioural ones by executing the regexes, LIKE patterns, and
classifier logic. But **four changes reference APIs that do not exist in the
pinned dependency versions or in this codebase**, so the affected files cannot
compile. `flutter analyze` / `flutter test` cannot have passed.

`node .gitnexus/run.cjs detect-changes` reporting "0 breaking changes" is not
evidence to the contrary — it diffs the structural symbol graph, it does not
typecheck. These four need a real `flutter analyze` run.

---

## Blocking — will not compile

### B1 — `like(..., escape: '\\')` does not exist in drift 2.18.0

**Severity:** CRITICAL (compile error)
**Location:** `lib/data/repositories/transaction_repository.dart:706,712,713,715`

`pubspec.yaml:13` pins `drift: 2.18.0` (exact, and the only version in the pub
cache). In that version:

```dart
// drift-2.18.0/lib/src/runtime/query_builder/expressions/text.dart:8
Expression<bool> like(String regex) {
  return _LikeOperator(this, Variable.withString(regex));
}
```

One positional `String`. There is no `escape:` named parameter, and
`_LikeOperator` (`:171-194`) has no escape support at all — `writeInto` emits
`target LIKE regex` and nothing else. `TableIndex.sql` and LIKE-escape support
landed in later drift releases; neither is available here.

There is a **second, deeper problem**. Even once it compiles, `_escapeLike`
makes matching *worse* rather than better without an `ESCAPE` clause. SQLite only
treats a character as an escape when `ESCAPE` is specified; otherwise `\` is a
literal. So:

```
merchant 'amzn_in'  → _escapeLike → 'amzn\_in'
SQL: merchant_raw LIKE '%amzn\_in%'    (no ESCAPE clause)
→ SQLite looks for a literal backslash → matches nothing
```

The fix currently converts an over-match bug (M2) into a silent no-match bug.

**Suggested fix** — emit the `ESCAPE` clause explicitly via `CustomExpression`:

```dart
/// LIKE with an explicit ESCAPE clause.
///
/// drift 2.18's `like()` cannot emit ESCAPE, and without it SQLite treats the
/// backslashes produced by _escapeLike as literals — so escaping silently
/// turns an over-match into a no-match.
Expression<bool> _likeEscaped(Expression<String> column, String pattern) {
  return CustomExpression<bool>(
    '${column.toString()} LIKE ? ESCAPE \'\\\'',
    // ... bind `pattern` as a variable; see Variable.withString
  );
}
```

Cleaner, and it sidesteps the ~100-clause OR (see B5): register a Dart callback
as a SQLite function once at open and match in one predicate:

```dart
// database.dart, in beforeOpen / the NativeDatabase setup
db.createFunction(
  functionName: 'token_match',
  argumentCount: const AllowedArgumentCount(2),
  function: (args) {
    final haystack = args[0] as String?;
    final needle = args[1] as String?;
    if (haystack == null || needle == null) return false;
    // Same semantics as RuleRepository.findMatch — one source of truth.
    return RegExp('\\b${RegExp.escape(needle)}\\b', caseSensitive: false)
        .hasMatch(haystack);
  },
);
```

```dart
// transaction_repository.dart
query.where((row) => CustomExpression<bool>(
  'token_match(merchant_raw, ?)', /* bind expected */,
));
```

That also removes the need for `_escapeLike` entirely.

---

### B2 — `@TableIndex.sql(...)` does not exist in drift 2.18.0

**Severity:** CRITICAL (compile / build_runner error)
**Location:** `lib/data/db/tables/transactions_table.dart:29-36`

```dart
// drift-2.18.0/lib/src/dsl/table.dart:289
const TableIndex({
  required this.name,
  required this.columns,
  this.unique = false,
});
```

There is no `.sql` named constructor in 2.18.0 (it was added in a later release).
Both annotations fail to resolve, and `drift_dev` codegen will fail before
`.g.dart` is regenerated.

The good news: the indexes are **already created correctly** by the
`customStatement` calls in `database.dart:131-138`, so the annotations are
redundant.

**Suggested fix** — delete both annotations and move the statements out of
`beforeOpen` into a versioned migration step, so they run once rather than on
every app launch:

```dart
// transactions_table.dart — remove the two @TableIndex.sql annotations.
// drift 2.18 cannot express expression indexes as annotations; they are
// created in the migration below instead.
```

```dart
// database.dart
@override
int get schemaVersion => <bump this>;

onUpgrade: (migrator, from, to) async {
  // ...
  if (from < <new version>) {
    // Expression indexes: _correctionTargets filters on lower(merchant_raw)
    // and lower(counterparty_vpa); a plain column index cannot serve those.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_merchant_raw_lower '
      'ON transactions (lower(merchant_raw));',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_transactions_counterparty_vpa_lower '
      'ON transactions (lower(counterparty_vpa));',
    );
  }
},
```

Keep `onCreate` covered too, and drop the `beforeOpen` copies.

---

### B3 — `LlmDownloadRetry` mixin cannot be applied to these classes

**Severity:** CRITICAL (compile error)
**Location:** `lib/intelligence/llm/llm_runtime.dart:55,76,288`

```dart
mixin LlmDownloadRetry on LlmRuntime { ... }

class PlatformLlmRuntime with LlmDownloadRetry implements LlmRuntime { ... }
class NoopLlmRuntime     with LlmDownloadRetry implements LlmRuntime { ... }
```

A mixin's `on` constraint must be satisfied by the **superclass** accumulated so
far. Both classes have superclass `Object`; `implements` contributes nothing to
the superclass chain. Dart rejects this:

> `'LlmDownloadRetry' can't be mixed onto 'Object' because 'Object' doesn't
> implement 'LlmRuntime'.`

This is the mixin shape I suggested, but it only works with `extends`. My
original snippet was wrong on this point — apologies for sending you down that
path.

**Suggested fix** — `extends` instead of `implements`:

```dart
abstract class LlmRuntime {
  const LlmRuntime();   // generative const ctor so subclasses stay const

  Future<LlmResult<String>> complete(String prompt);
  // ...
  Future<bool> downloadModelWithRetry({
    int maxRetries,
    Duration delay,
  });
}

mixin LlmDownloadRetry on LlmRuntime { /* unchanged */ }

class PlatformLlmRuntime extends LlmRuntime with LlmDownloadRetry {
  const PlatformLlmRuntime({
    MethodChannel channel = const MethodChannel('com.paisatrack/llm'),
    this.enabled = AppConstants.enableLocalLlm,
  })  : _channel = channel,
        super();
  // ...
}

class NoopLlmRuntime extends LlmRuntime with LlmDownloadRetry { /* ... */ }
```

Alternatively drop the `on` clause and redeclare the two members the mixin needs
(`Future<bool> downloadModel();`) as abstract inside the mixin — that keeps
`implements` working:

```dart
mixin LlmDownloadRetry {
  Future<bool> downloadModel();   // supplied by the host class

  Future<bool> downloadModelWithRetry({ /* ... */ }) async { /* ... */ }
}
```

Note `_FakeLlmRuntime extends NoopLlmRuntime` (`test/features/settings/settings_test.dart:36`)
inherits this error too.

---

### B4 — The new T-108 test file references a type that doesn't exist

**Severity:** CRITICAL (compile error) — and it is the regression gate for C1
**Location:** `test/capture/hdfc_icici_template_test.dart:4,26-29` (and 8 more sites)

The restructuring is exactly right — reads the shipped assets, goes through
`TemplateMatcher`, asserts `ts`. But it will not compile:

1. **`import '.../template_engine/sms_message.dart'`** — no such file exists.
   `lib/capture/template_engine/` contains only `field_normalizer.dart`,
   `template_matcher.dart`, `template_registry.dart`, `template_trust_ledger.dart`.
2. **`SmsMessage(sender:, body:, timestamp:)`** — the class doesn't exist.
   `TemplateMatcher.match` takes `RawSms` (`lib/data/models/raw_sms.dart`), whose
   constructor is `RawSms({required id, required sender, required body,
   required receivedAt})` — different type, different parameter name, and `id` is
   missing.
3. **`expect(record.accountHint, '5678')`** — `FieldNormalizer:29` builds
   `accountHint: 'xx$account'`, so the actual value is `'xx5678'`. All 9
   `accountHint` assertions are wrong.
4. **`expect(record.ts, DateTime.utc(...).millisecondsSinceEpoch)`** —
   `NormalizedTransactionRecord.ts` is a `DateTime`
   (`normalized_transaction_record.dart:31`), not an int. All 9 `ts` assertions
   compare a `DateTime` to an `int`.
5. `import '.../field_normalizer.dart'` is unused.

Point 4 matters most: **the `ts` assertion is the one that catches C1**, and it
is currently written in a form that can never pass.

**Suggested fix:**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

RawSms _sms({required String sender, required String body, required DateTime at}) =>
    RawSms(id: 'sms_test', sender: sender, body: body, receivedAt: at);

// ...
test('parses HDFC UPI debit template via TemplateMatcher', () async {
  final record = await matcher.match(_sms(
    sender: 'VK-HDFCBK',
    body: 'Money Transfer: Rs 1,450.50 debited from A/C x5678 to Coffee Shop '
        'on 15-Jul-26 via UPI Ref 619283746510',
    // Deliberately NOT the SMS date: proves ts came from the template, not
    // the fallback — this is the assertion that catches an unsupported
    // date_format silently falling through.
    at: DateTime.utc(2026, 1, 1),
  ));

  expect(record, isNotNull);
  expect(record!.amount, 1450.50);
  expect(record.accountHint, 'xx5678');
  expect(record.merchantRaw, 'Coffee Shop');
  expect(record.refId, '619283746510');
  expect(record.ts, DateTime.utc(2026, 7, 15));
  expect(record.parseConfidence, 0.85);  // public provenance cap (ADR 0005)
});
```

Setting `receivedAt` to a different date than the SMS text is worth doing
throughout — with both equal, a regression to the fallback path would still pass.

---

## New regression introduced by the fixes

### B5 — Counterparty VPA matching widened from exact to substring

**Severity:** MAJOR
**Location:** `lib/data/repositories/transaction_repository.dart:702-707`

The counterparty branch changed from `equals` only to:

```dart
row.counterpartyVpa.lower().equals(expected) |
row.counterpartyVpa.lower().like('%$needle%', escape: '\\')
```

M1/M2 were about the **merchant** branch. VPAs are exact identifiers, and
substring matching over-matches badly. Verified:

```
needle 'abc@ybl' now also matches:
  'xabc@ybl2'      ❌
  'abc@ybl.fraud'  ❌
  'notabc@ybl'     ❌
```

A user correcting one payee's category retro-writes every transaction whose VPA
merely contains that string. The original `equals` was correct.

**Suggested fix** — revert this branch:

```dart
if (ruleInput.matchType == 'counterparty') {
  // VPAs are exact identifiers: substring matching would sweep in
  // 'notabc@ybl' and 'abc@ybl.fraud' when correcting 'abc@ybl'.
  query.where((row) => row.counterpartyVpa.lower().equals(expected));
}
```

---

### B6 — ~100 OR'd LIKE clauses per correction query

**Severity:** MAJOR (performance)
**Location:** `lib/data/repositories/transaction_repository.dart:709-719`

The nested boundary loop over 9 delimiters generates `9×2 + 9×9 = 99` LIKE
predicates OR'd together, evaluated per row. The expression indexes from B2 can
only serve the `equals` and the 9 prefix (`needle + delim + %`) arms; the 90
leading-`%` arms force a full scan and each runs its own pattern match.

This is measurably slower than the in-memory `contains` it replaced, which was
one pass with one substring check.

The `token_match` SQLite function in B1 collapses all 99 clauses into a single
predicate with identical semantics — that is the recommended route.

---

## Verified fixed

Re-executed the relevant logic; these are correct.

| Finding | Status | Evidence |
|---|---|---|
| **C1** date format | ✅ | `dd-MMM-yy`/`dd/MMM/yy` branch added; `15-Jul-26 → 2026-07-15`, `31-Dec-99 → 1999-12-31`, unknown month falls back without throwing. Bonus: numeric branch hardened `int.parse` → `int.tryParse`. |
| **C1b** fast-fail | ✅ | `SmsTemplate.fromJson` rejects unsupported `date_format`. |
| **C2** provenance | ✅ | All 8 entries now `"public"` → capped at 0.85, review band. |
| **C3** select-all | ✅ | `_searchQuery` hoisted to `_WeeklyReviewScreenState`; `_selectAll`/`_confirm` scoped to `_filtered(value)`. Three new widget tests at `:436,:478,:524`. |
| **M1** boundary match | ✅ | Now **8/8 agreement** with `RuleRepository`, including `PAYTM*SWIGGY`, `UPI-SWIGGY-9876`, `Order from Swiggy`; `SwiggyPayLater` correctly excluded. (Semantics correct — blocked on B1/B6.) |
| **M4** import floor | ✅ | `importBytes` now only rejects empty; legacy archives restorable. |
| **M5** constant | ✅ | `EncryptedBackupService.minimumPassphraseLength`, rune-counted, export-only. |
| **M6** CSV injection | ✅ | `=+-@\t\r` prefixed with `'`; `\r` added to the quote trigger. |
| **M7** wiring | ✅ | `transactionCsvExportProvider` exposed with privacy contract. |
| **M8** formatting | ✅ | `toStringAsFixed(2)`, local calendar date, CRLF, UTF-8 BOM. |
| **M9** merchant/balance | ⚠️ mostly | `AMAZON.IN` now survives; balance template ordered first and captures correctly. Residual: `M/S. RELIANCE FRESH` → `M/S` in the ICICI card template (`. ` triggers the lookahead). Acceptable; note it. |
| **M11** autoDispose | ✅ | `StreamProvider.autoDispose.family`. |
| **M12** kDebugMode | ✅ | Source watch and all three evidence rows gated; JSON pretty-printed and selectable. |
| **M13** classifier | ✅ | **7/7** cases now correct, including the three balance messages and the two "login"/"password" footers. |
| **M14** AsyncValue | ✅ | `Provider.autoDispose<AsyncValue<...>>` with `whenData`, stable tie-break sort, loading/error rendered. |
| **M15** backoff | ✅ | Exponential with full jitter and `maxDelay` cap. (Blocked on B3.) |
| **M18** backfill state | ✅ | `markRunning()` before await; `markCompleted(processed:, failed:)` takes the result, not the last tick. |
| **M19** comments | ✅ | Both restored verbatim. |
| **M20** clear button | ✅ | Controllers + `dispose()` on both screens; payee predicate now `userLabel?.trim()`. |
| **M22** privacy assert | ✅ | `expect(copyCalls, 0)` restored. |
| **M23** shared helper | ✅ | `lib/data/confidence_payload.dart`; narrow `on FormatException`/`on TypeError`; per-source breakdown. |

---

## Claims in the summary not supported by the tree

- **"Regression widget tests ... clear button taps"** for payee labels —
  `test/features/settings/payee_labels_screen_test.dart` is **unmodified**. The
  review-screen clear test exists (`:524`); the payee one does not.
- **"Unit and widget test suite assertions updated and passing"** — four files do
  not compile (B1–B4), so the suite cannot have run.
- **No tests added** for the highest-risk fixes:
  - `test/data/repositories/transaction_repository_test.dart` — unmodified; the new
    boundary semantics (M1) and escaping (M2) are untested, and the counterparty
    widening (B5) would have been caught by one.
  - `test/features/backup/encrypted_backup_service_test.dart` — unmodified; no test
    that a short-passphrase archive still restores (M4), which is the whole point.
  - `test/intelligence/llm/llm_runtime_test.dart` — unmodified; backoff still
    untested, and `_FakeLlmRuntime` still overrides `downloadModelWithRetry`
    (`settings_test.dart:52-58`), so the retry path remains unexercised end to end.
  - `test/capture/sms_backfill_test.dart` — unmodified; `markRunning`/`markFailed`
    and the stale-count-on-rerun scenario untested.
  - `test/features/dev/model_metrics_screen_test.dart` — unmodified.

- **C2 is only half satisfied.** ADR 0005 admits the `public` tier *"into
  `test/fixtures/sms/` with `provenance: public` in the expected JSON **and** in
  the template entry."* The template entries are done; there is still no
  `test/fixtures/sms/hdfcbk/` or `icicib/` directory and no
  `sms_t108_bank_fixture_coverage_test.dart`. The safety-critical half (0.85 cap,
  no silent auto-label) **is** in place, so this is no longer a blocker — but the
  fixture-first law (T-024) remains unmet for these two banks.

- **M23 duplication partially remains** — `transaction_repository.dart:736`
  still has its own `_parseConfidenceOf`. Three copies became two; point it at
  `parseConfidenceFromJson`.

---

## Recommended next steps

1. Run `flutter analyze` — it will surface B1–B4 immediately, and likely a few
   cascading errors I haven't enumerated.
2. Fix B1/B2 together (the `token_match` function removes the need for both
   `_escapeLike` and the 99-clause OR), then B3, then B4.
3. Revert B5 (counterparty back to `equals`).
4. Run `flutter test`. B4 is the gate for C1 — confirm it fails before the
   `field_normalizer` fix and passes after.
5. Add the five missing test files listed above; the boundary-matching and
   short-passphrase-restore tests are the two that protect real user data.
6. Optional follow-up: HDFC/ICICI fixtures + coverage gate to close ADR 0005.
