---
name: flutter-conventions
description: >
  Use when writing or reviewing any Dart code in lib/ (widgets, providers,
  repositories, models). Use when: creating a new screen, adding a Riverpod
  provider, defining a data model, touching anything under lib/experience,
  lib/data/models, or lib/data/repositories, or reviewing a PR that adds/edits
  .dart files outside test/. Covers Riverpod patterns, freezed models, the
  Result type, folder placement, and lint expectations for this repo.
checklist:
  - No business logic lives inside a Widget class — only layout, event
    wiring, and reading provider state.
  - Every repository call from a widget goes through a Riverpod provider,
    never instantiated inline with `RepositoryX()` inside build().
  - Provider names follow `<noun>Provider` / `<noun>NotifierProvider`
    (e.g. `transactionListProvider`, not `getTransactionsProvider`).
  - No function that can fail returns a bare value or throws across a layer
    boundary — it returns `Result<T, E>` (lib/core/result.dart).
  - No `try/catch` at a UI call site to route control flow — that belongs
    inside the repository/service that produced the Result.
  - Data models are `freezed` classes (or, for the transaction record
    contract, hand-written immutable classes matching plan §6.2 exactly).
  - New files land in the folder plan §3 specifies — no ad hoc top-level
    files under lib/.
  - No `dynamic` anywhere in new code. Use a concrete type, a generic, or
    `Object?` plus a type check.
  - Every `enum` is switched on exhaustively (no `default:` catch-all that
    silently swallows a new case) — let the analyzer catch missing cases.
  - Every widget/model constructor that can be `const` is `const`.
  - No magic numbers/strings for thresholds, budgets, or flags — they live
    in `lib/core/constants.dart` (`AppConstants`).
  - `flutter analyze` is clean (zero warnings) before marking the task done.
---

# Flutter Conventions for PaisaTrack

This is the how-to layer over `PLAN.md`. The plan defines the folder
structure (§3), the feature list (§4), and the data model (§6). This skill
tells you how to write idiomatic, senior-quality Dart against that spec.
When in doubt about *where* something goes, `PLAN.md §3` wins; this file is
about *how* to write it once you know where.

## 1. Riverpod patterns

**Provider naming.** `<domain><Kind>Provider`:
- Read-only derived state: `monthSummaryProvider`, `unparsedSmsCountProvider`
- Mutable state machines: `transactionListNotifierProvider`,
  `askBudgetNotifierProvider`
- Repository singletons: `transactionRepositoryProvider`,
  `merchantRepositoryProvider`

Never name a provider after its implementation (`transactionRepositoryImplProvider`)
or its return type alone (`listProvider`) — a reviewer must be able to guess
what a provider does from its name without opening the file.

**No logic in widgets.** A widget's `build()` method may: read providers,
lay out other widgets, wire callbacks to methods on a notifier. It may NOT:
compute a derived value with more than a one-line expression, call a
repository directly, branch on a `Result` with more than a single
`switch`/`if` that immediately delegates to a small private method, or hold
mutable state that isn't `ValueNotifier`/Riverpod state.

```dart
// BAD — logic embedded in the widget
class DashboardCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionListProvider);
    var total = 0.0;
    for (final t in txns) {
      if (t.direction == Direction.debit && !t.isTransfer) total += t.amount;
    }
    return Text(total.toStringAsFixed(2));
  }
}

// GOOD — derived value computed by a provider, widget just renders
final monthSpendProvider = Provider<double>((ref) {
  final txns = ref.watch(transactionListProvider);
  return txns
      .where((t) => t.direction == Direction.debit && !t.isTransfer)
      .fold(0.0, (sum, t) => sum + t.amount);
});

class DashboardCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(monthSpendProvider);
    return Text(total.toStringAsFixed(2));
  }
}
```

**Repository injection.** Repositories are constructed once, behind a
provider, and injected — never `new`'d inside a widget or another repository.
This is what makes the fixture-driven and unit test story in
`testing-discipline` possible (tests override the provider with a fake).

```dart
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return DriftTransactionRepository(ref.watch(databaseProvider));
});
```

Enrichers, the parser cascade, and the decision policy are also injected via
providers — not instantiated ad hoc in `pipeline.dart`. This is what lets
`intelligence-modules` tests substitute fakes for the classifier/embedder.

## 2. The Result type — no thrown exceptions across layer boundaries

`lib/core/result.dart` defines `Result<T, E>` (`Ok`/`Err`). Any function
whose failure is expected and part of normal operation (parse failure,
validation failure, DB constraint, network failure in a flagged extractor)
returns `Result`, not a throw.

Exceptions are reserved for truly exceptional, unrecoverable states (out of
memory, programmer error / assertion). If you're tempted to `throw` for
"this SMS didn't match any template" — that's a `Result`, not an exception;
see `ParseFailure` in `lib/capture/parser_cascade.dart` for the existing
pattern to follow.

```dart
// Layer boundary: repository -> provider -> widget.
// Each hop either forwards the Result or unwraps it into UI state —
// it never lets an exception cross the boundary unhandled.
Future<Result<TransactionRecord, RepoError>> confirmCategory(
  String txnId,
  String categoryId,
) async {
  final row = await _db.updateCategory(txnId, categoryId);
  if (row == null) return const Err(RepoError.notFound);
  return Ok(row.toModel());
}
```

Exhaustively handle both branches at the point you consume a `Result` —
prefer a small `switch` over `result.isOk` + unsafe cast:

```dart
switch (result) {
  case Ok(:final value):
    ref.read(transactionListNotifierProvider.notifier).upsert(value);
  case Err(:final error):
    ref.read(snackbarProvider.notifier).showError(error);
}
```

## 3. Freezed model conventions

Use `freezed` for models with multiple fields, optional fields, or that need
`copyWith`/equality (`Merchant`, `RecurringSeries`, `Insight`). Exception:
`NormalizedTransactionRecord` is hand-written (see
`lib/data/models/normalized_transaction_record.dart`) because its shape is
the frozen contract from plan §6.2 and must not silently pick up fields via
codegen drift — every field is explicit and reviewed.

Rules for freezed classes:
- One class per file, file name matches class name (snake_case).
- Nullable fields are nullable because the domain says so (e.g. `merchantId`
  before resolution), never as a shortcut to avoid a default.
- No business logic methods beyond simple derived getters
  (`bool get isSpending`). Anything heavier is a function in the
  repository/enricher that operates on the model.
- Enums used inside models are Dart enums with an explicit `fromString`/
  `toJson` mapping colocated in the same file — never magic strings compared
  ad hoc at call sites.

## 4. Folder placement (plan §3)

Before creating a new file, find its slot:

| You're writing... | Goes in |
|---|---|
| A screen | `lib/experience/screens/<feature>/` |
| A shared widget | `lib/experience/widgets/` |
| A provider that's screen-specific | co-located in the screen's folder, suffix `_providers.dart` |
| A provider used across features | `lib/data/repositories/` (repository provider) or `lib/core/` (app-wide) |
| An Enricher | `lib/intelligence/enrichers/` implementing `Enricher` |
| A parser cascade stage | `lib/capture/` (see `parser_cascade.dart`) |
| A drift table | `lib/data/db/tables/`, one file per table |
| A freezed model | `lib/data/models/` |

If you can't find a slot that fits, that's a signal to raise it in
`planning-and-tasks` grooming, not to invent a new top-level folder solo.

## 5. Lint expectations & senior tells

Run `flutter analyze` — zero warnings is the bar, not "no errors." Specific
tells a reviewer (or Claude, self-reviewing) looks for:

- `const` everywhere it's legal. A widget tree with no `const` on static
  subtrees is a tell of a rushed PR.
- No magic numbers: `0.9`, `500`, `2` for thresholds/budgets are compile
  errors of judgment — they belong in `AppConstants`, even for a "quick"
  change. Grep for bare numeric literals near words like `threshold`,
  `budget`, `confidence` before submitting.
- No `dynamic`. If you don't know the type yet, use a named typedef or a
  small sealed class — not an escape hatch.
- Exhaustive `switch` on every enum (`Direction`, `ParseSource`, `Channel`,
  category kind, etc.) — adding a new enum value should force a compile
  error everywhere it's unhandled, not silently no-op.
- No SMS text, account numbers, or amounts in `print`/`log` calls outside
  the debug-only gated logger (`lib/core/logging.dart`) — see
  `sms-template-authoring` and `intelligence-modules` for the privacy rule
  this enforces.

## Related

- `db-and-migrations` — drift table/model conventions in more depth.
- `intelligence-modules` — the `Enricher` interface and confidence rules.
- `testing-discipline` — what "done" requires per module.
