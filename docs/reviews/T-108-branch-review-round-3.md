# Review Round 3 — `codex/t108-bank-capture-coverage`

**Scope:** verification of the round-2 blockers (B1–B6) plus the new Keystore work.

**Verdict:** **Request Changes** — one new CRITICAL. B2, B3, B4, B5 are cleanly
resolved and the missing tests were added. But the B1 fix introduced a **SQL
injection vulnerability** reachable from any received SMS, and it also crashes on
ordinary merchant names containing an apostrophe.

`flutter analyze` reporting 0 errors is consistent with this — `_likeEscaped`
is valid Dart. Analyze does not inspect the contents of hand-built SQL strings,
so it cannot see this class of defect.

---

## CRITICAL — SQL injection via `_likeEscaped`

**Severity:** CRITICAL
**Location:** `lib/data/repositories/transaction_repository.dart:727-735`

```dart
static Expression<bool> _likeEscaped(
  Expression<String> column,
  String pattern,
) {
  return CustomExpression<bool>(
    "lower(merchant_raw) LIKE '$pattern' ESCAPE '\\'",
  );
}
```

`pattern` embeds `needle` = `_escapeLike(expected)`, and `expected` comes from
`ruleInput.matchValue` → `merchantRaw` → **the body of an SMS sent by a third
party**. It is interpolated directly into a single-quoted SQL literal.

`_escapeLike` neutralizes `\`, `%`, and `_`. It does **not** escape the single
quote, so the literal can be terminated.

### It breaks on ordinary merchant names

Apostrophes are common in Indian merchant strings — `DOMINO'S`, `MCDONALD'S`,
`LEVI'S`, `HARDEE'S`. Verified against SQLite:

```
matchValue "domino's pizza"
  → lower(merchant_raw) LIKE '% domino's pizza' ESCAPE '\'
  → OperationalError: near "s": syntax error
```

Every "existing and future" correction on such a merchant throws. Because the
statement runs inside `_database.transaction(...)` alongside the rule insert, the
user's correction is silently rolled back.

### It is exploitable

Verified end to end against SQLite with a 4-row table:

```
matchValue "x' OR 1=1 --"
  → lower(merchant_raw) LIKE '% x' OR 1=1 --' ESCAPE '\'
  → rows returned: ['t1','t2','t3','t4']   ← entire table
```

`_correctionTargets` returns every row, and `correctCategory` then writes
`category_id` and `status='confirmed'` to all of them plus one feedback row each.
An attacker who can send the user an SMS controls `merchantRaw`, so a single
crafted message can rewrite the user's entire financial history the next time
they apply a category correction. There is no confirmation step showing the
affected count.

### Fix

`CustomExpression` in drift 2.18.0 takes raw SQL only — there is no variable
binding on it, so this construction cannot be made safe by patching the
escaping. Two options, both verified available in the pinned versions:

**Preferred — register a SQLite function.** This removes the injection surface,
the `_escapeLike` helper, and the 99-clause OR (round-2 B6) in one change, and
makes the retro-application share one definition with `RuleRepository`:

```dart
// database.dart — where the NativeDatabase is constructed
NativeDatabase.createInBackground(
  file,
  setup: (db) {
    db.createFunction(
      functionName: 'token_match',
      argumentCount: const AllowedArgumentCount(2),
      deterministic: true,
      directOnly: false,
      function: (args) {
        final haystack = args[0] as String?;
        final needle = args[1] as String?;
        if (haystack == null || needle == null) return false;
        // Same word-boundary semantics as RuleRepository.findMatch — one
        // definition, so retro-application cannot drift from the rule it
        // creates.
        return RegExp('\\b${RegExp.escape(needle)}\\b', caseSensitive: false)
            .hasMatch(haystack);
      },
    );
  },
);
```

```dart
// transaction_repository.dart — replaces the whole boundary loop
query.where(
  (row) => CustomExpression<bool>(
    // Arguments are bound by the function call, not interpolated.
    'token_match(merchant_raw, ${Variable.withString(expected).toString()})',
  ),
);
```

(If threading the variable through `CustomExpression` is awkward, build the
predicate with `customSelect('... WHERE token_match(merchant_raw, ?)',
variables: [Variable.withString(expected)])` and map the rows — `customSelect`
does support bound variables.)

**Minimal — bind the pattern via `likeExp`.** Drift 2.18 has
`likeExp(Expression<String>)`, and `Variable.withString` is an
`Expression<String>`, so this is a parameterised LIKE with no string building:

```dart
expr = expr | row.merchantRaw.lower().likeExp(Variable.withString('%$l$needle'));
```

This closes the injection immediately. Note it drops the `ESCAPE` clause, so
`_escapeLike` must go too — without `ESCAPE`, backslashes are literal and
escaping actively breaks matching (round-2 B1). Accept `%`/`_` in merchant
strings as a known narrow over-match, or move to the function above.

### Secondary bug in the same helper

`_likeEscaped` accepts a `column` parameter and then ignores it, hardcoding
`lower(merchant_raw)`. It is currently only called with
`row.merchantRaw.lower()`, so it is right by accident. Anyone reusing it for
`counterparty_vpa` gets a silently wrong query. Drop the unused parameter or
honour it.

---

## Verified resolved

| Round-2 finding | Status |
|---|---|
| **B2** `@TableIndex.sql` | ✅ Annotations removed; indexes created via `customStatement`. |
| **B3** mixin `on` violation | ✅ Cleanly resolved — mixin dropped, `downloadModelWithRetry` is now a concrete method on `abstract class LlmRuntime` with `const LlmRuntime()`, and both runtimes `extends`. Better than my suggestion: one implementation, no mixin plumbing. Backoff, jitter and cap preserved. |
| **B4** test won't compile | ✅ Imports `data/models/raw_sms.dart`, uses `RawSms`, phantom `sms_message.dart` gone. |
| **B5** counterparty widened | ✅ Reverted to `equals`, with a comment explaining why. |
| **Missing tests** | ✅ `transaction_repository_test.dart`, `encrypted_backup_service_test.dart`, `sms_backfill_test.dart`, `settings_test.dart` all now modified. |
| **M23 duplication** | ✅ `_parseConfidenceOf` now delegates to `parseConfidenceFromJson`. |

Round-1 fixes re-confirmed unchanged and correct: C1 date parsing, C2 provenance
cap, C3 select-all scoping, M4/M5 passphrase, M6/M7/M8 CSV, M11 autoDispose,
M12 `kDebugMode`, M13 classifier (7/7), M14 `AsyncValue`, M18/M19 backfill,
M20 controllers.

---

## Still open (non-blocking)

- **B6 — 99 OR'd LIKE clauses per correction query.** 90 have a leading `%` and
  cannot use the new expression indexes. The `token_match` function above
  collapses these to one predicate.
- **Index creation lives in `beforeOpen`**, so `CREATE INDEX IF NOT EXISTS` runs
  on every app launch. Move to a versioned migration step and bump
  `schemaVersion`.
- **ADR 0005 fixture gate.** Still no `test/fixtures/sms/hdfcbk|icicib/` and no
  `sms_t108_bank_fixture_coverage_test.dart`. The safety-critical half (0.85 cap,
  no silent auto-label) is in place, so this is follow-up, not a blocker.
- **`M/S. RELIANCE FRESH` → `M/S`** in `icici_card_spent_v1` — the `. `
  lookahead still truncates. Narrow residual from round-1 M9.
- **`_FakeLlmRuntime` still overrides `downloadModelWithRetry`**
  (`settings_test.dart:52`), so the real retry path is not exercised through the
  settings UI.
- **Android Keystore recovery (new, unreviewed).** `DatabasePassphraseStore.kt`
  and `AndroidKeystoreDatabasePassphraseProvider` were not part of the original
  12-task scope and have not been reviewed. Clear-and-regenerate on decryption
  failure is the right recovery shape, but it is worth a focused pass: on a
  Keystore invalidation the regenerated passphrase will not open the existing
  encrypted database, so confirm the flow surfaces that to the user rather than
  silently creating an empty one. Worth its own review before merge.

---

## Next steps

1. Replace `_likeEscaped` — `token_match` preferred, `likeExp` + `Variable` as
   the minimal patch. Delete `_escapeLike` either way.
2. Add a regression test with a hostile and an apostrophe merchant:

```dart
test('correction scope is safe against quotes in merchant text', () async {
  await _insertTxn(database, id: 'txn_dom',   merchantRaw: "DOMINO'S PIZZA");
  await _insertTxn(database, id: 'txn_other', merchantRaw: 'RENT');
  await _insertTxn(database, id: 'txn_inj',   merchantRaw: "x' OR 1=1 --");

  // Apostrophe merchant must correct itself and nothing else.
  final result = await TransactionRepository(database).correctCategory(
    txnId: 'txn_dom',
    categoryId: 'food_dining',
    scope: CorrectionScope.existingAndFuture,
    context: 'historical_cleanup',
  );
  expect(result.affectedTransactionCount, 1);

  // Injection payload must not widen the scope to the whole table.
  final injected = await TransactionRepository(database).correctCategory(
    txnId: 'txn_inj',
    categoryId: 'food_dining',
    scope: CorrectionScope.existingAndFuture,
    context: 'historical_cleanup',
  );
  expect(injected.affectedTransactionCount, 1);
  final rows = await database.select(database.transactions).get();
  expect(rows.singleWhere((r) => r.id == 'txn_other').categoryId, 'other');
});
```

3. Re-run `flutter analyze` and `flutter test`.
4. Book a separate review pass for the Android Keystore recovery changes.
