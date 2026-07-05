---
name: db-and-migrations
description: >
  Use when touching lib/data/db/ (drift tables, database.dart, migrations/)
  or making any change that affects the on-disk schema, including adding a
  column, index, or table. Use when reviewing a PR that includes a schema
  change without a matching migration.
checklist:
  - Every schema change ships as a drift migration (schemaVersion bump +
    onUpgrade step) in the same PR as the table change — never a
    hand-edited DB or "just delete the app data" instruction.
  - A migration test exists that creates the DB at the previous version,
    applies the migration, and asserts data survives and the new shape is
    correct.
  - docs/schema.md is updated in the same PR: new tables/columns/indexes and
    a dated migration-log line.
  - The normalized transaction record contract (plan §6.2) is untouched, OR
    an ADR in docs/decisions/ proposes the change and records @human
    approval before it's implemented (plan §12, COLLABORATION.md §2).
  - New query patterns for list screens are checked against the index list
    in plan §6.1 — no full-table scan added for a screen that will be hit
    on every dashboard load.
  - No N+1: list screens fetch merchant/category joins in one query (drift
    joins or a single denormalized read), not one query per row.
  - SQLCipher key handling stays inside lib/core/crypto/ — no code outside
    that folder touches the raw key, derives it, or logs it.
  - Seed data (categories, category_seed) is loaded idempotently — re-running
    seed on an existing DB does not duplicate or clobber user edits.
---

# DB & Migrations Conventions

Plan references: PLAN.md §6 (full schema + the frozen record contract),
§8 (privacy/security — SQLCipher key handling), §3 (`lib/data/db/` layout).

## 1. Drift table conventions

One file per table under `lib/data/db/tables/`, named for the table
(`transactions_table.dart`, `raw_sms_table.dart`, ...). Column names match
plan §6.1 exactly — don't "improve" naming during implementation; if a name
genuinely needs to change, that's a plan discussion, not a silent rename.

```dart
// lib/data/db/tables/transactions_table.dart
class Transactions extends Table {
  TextColumn get id => text()();
  IntColumn get ts => integer()();
  RealColumn get amount => real()();
  TextColumn get direction => text()();
  TextColumn get channel => text()();
  TextColumn get accountHint => text().nullable()();
  TextColumn get merchantRaw => text().nullable()();
  TextColumn get merchantId =>
      text().nullable().references(Merchants, #id)();
  TextColumn get categoryId =>
      text().nullable().references(Categories, #id)();
  TextColumn get description => text().nullable()();
  RealColumn get balanceAfter => real().nullable()();
  TextColumn get refId => text().nullable()();
  TextColumn get parseSource => text()();
  TextColumn get smsId => text().nullable().references(RawSms, #id)();
  TextColumn get confidenceJson => text()();
  TextColumn get status => text()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

Indexes from plan §6.1 (`ts`, `merchant_id`, `category_id`, `ref_id`,
`status`) are declared as drift `Index` definitions in the same table file,
not added later as an afterthought migration — bake them into the initial
table definition for any table you're creating fresh, and add them via
migration for existing tables.

## 2. The frozen record contract — read this before touching schema

`NormalizedTransactionRecord` (plan §6.2) is the one shape every parser path
must produce. It is deliberately hand-written, not derived from the drift
table, so a schema refactor can't silently change what parsers emit. If your
change would alter this record's fields:

1. Stop. Write an ADR in `docs/decisions/` (Context/Decision/Consequences).
2. It needs explicit @human approval noted in the ADR before you implement
   (COLLABORATION.md §2, plan §12).
3. Only after approval: update the model, every parser path, every
   consumer, and the fixture expectations in `test/fixtures/sms/*.expected.json`.

Do not treat this as bureaucracy to route around — two agents editing this
contract independently without a shared ADR is exactly the drift the
two-agent protocol exists to prevent.

## 3. Migration checklist (do all three in one PR)

1. **Write the migration.** Bump `schemaVersion` in `database.dart`, add a
   step in `onUpgrade` (or `MigrationStrategy`) for the new version.
2. **Write the migration test.** Under `test/data/db/`, build the DB at
   `oldVersion`, seed representative rows, run the upgrade, assert both
   that old rows survived (values intact) and the new column/table/index
   exists and behaves (e.g. a `NOT NULL DEFAULT` backfilled correctly).
3. **Update `docs/schema.md`.** Add the new table/column, and append a
   dated line to the migration log — this file plus PLAN.md §6 is the
   only place a future session should need to look to understand current
   shape.

A PR touching `lib/data/db/` without all three is not done — flag it in
review (`code-review` skill) as CHANGES, not a nit.

## 4. SQLCipher key handling — do / don't

- **Do** generate the key once on first run and store it via
  `lib/core/crypto/` using Android Keystore (StrongBox where available).
- **Do** derive the drift `NativeDatabase`/`QueryExecutor` with the key read
  from `lib/core/crypto/`, never a literal or an env var.
- **Don't** log the key, a derived key, or any passphrase — not even at
  debug level.
- **Don't** read or cache the key anywhere outside `lib/core/crypto/`; every
  other module asks that module for an already-opened database connection,
  not the key itself.
- **Don't** weaken this for "easier local debugging" — if you need to
  inspect the DB during development, add a documented, flag-gated debug
  export path, don't disable encryption.

## 5. Query performance rules

- List screens (`transactions`, `recurring`, `review`) fetch merchant name
  and category name via a single joined query or view — never loop rows in
  Dart issuing one repository call per row.
- Any new query that filters/sorts by a column not in the plan §6.1 index
  list needs either: reuse of an existing index, or a new index added via
  migration with justification in the PR description.
- Aggregation queries (dashboard summary, insights) push the aggregation
  into SQL (`SUM`, `COUNT`, `GROUP BY`) rather than pulling all rows into
  Dart and summing in memory, once transaction counts grow past a few
  thousand.

## 6. Seed data handling

`assets/seed/categories.json` and `category_seed.json` load into
`categories`/seed mappings on first run via an idempotent upsert (match by
stable `id`, not by name) so re-seeding after an app update adds new seed
categories without duplicating or overwriting a user's rename of an
existing one.

## Related

- `flutter-conventions` — repository/provider patterns wrapping these tables.
- `sms-template-authoring` — how `raw_sms` rows are produced upstream.
- `intelligence-modules` — how `feedback`, `baselines`, `model_meta` are
  written by the learning loop.
