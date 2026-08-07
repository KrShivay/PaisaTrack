import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../dedup/duplicate_match_rule.dart';
import '../../enrichment/payee_identity_key.dart';
import 'tables/baselines_table.dart';
import 'tables/categories_table.dart';
import 'tables/counterparties_table.dart';
import 'tables/expected_events_table.dart';
import 'tables/feature_flags_table.dart';
import 'tables/feedback_table.dart';
import 'tables/financial_events_table.dart';
import 'tables/insights_table.dart';
import 'tables/merchant_aliases_table.dart';
import 'tables/merchants_table.dart';
import 'tables/model_meta_table.dart';
import 'tables/payment_sources_table.dart';
import 'tables/payee_evidence_table.dart';
import 'tables/raw_sms_table.dart';
import 'tables/recurring_series_table.dart';
import 'tables/rules_table.dart';
import 'tables/shadow_transactions_table.dart';
import 'tables/transaction_links_table.dart';
import 'tables/transactions_table.dart';

part 'database.g.dart';

/// Drift database for PaisaTrack's local-first encrypted store.
///
/// Schema changes must update `schemaVersion`, add a migration test, and update
/// `docs/schema.md` in the same change.
@DriftDatabase(
  tables: [
    Baselines,
    Categories,
    Counterparties,
    ExpectedEvents,
    FeatureFlags,
    Feedback,
    FinancialEvents,
    Insights,
    MerchantAliases,
    Merchants,
    ModelMeta,
    PaymentSources,
    PayeeEvidence,
    RawSms,
    RecurringSeries,
    Rules,
    ShadowTransactions,
    TransactionLinks,
    Transactions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Loads bundled default categories without overwriting user customizations.
  ///
  /// The seed is safe to run repeatedly. Existing category ids are ignored so
  /// user-edited names and icons survive app upgrades and restarts.
  Future<void> seedDefaultCategories({AssetBundle? bundle}) async {
    final source = await (bundle ?? rootBundle).loadString(
      _defaultCategoriesAsset,
    );
    final decoded = jsonDecode(source) as List<Object?>;
    final rows = decoded
        .cast<Map<String, Object?>>()
        .map(_categorySeedToCompanion)
        .toList(growable: false);

    await batch((batch) {
      batch.insertAll(
        categories,
        rows,
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Seeds the current feature-flag defaults without overwriting overrides.
  ///
  /// The values are stored as strings because feature flags are intentionally
  /// a small key/value surface. Missing rows still resolve through
  /// [AppConstants] for test databases and older callers.
  Future<void> seedDefaultFeatureFlags() async {
    await batch((batch) {
      batch.insertAll(
        featureFlags,
        AppConstants.featureFlagDefaults.entries
            .map(
              (entry) => FeatureFlagsCompanion.insert(
                key: entry.key,
                value: entry.value.toString(),
              ),
            )
            .toList(growable: false),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Current local schema version.
  @override
  int get schemaVersion => 16;

  /// Creates the initial schema and enables SQLite foreign-key enforcement.
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_transactions_merchant_raw_lower '
          'ON transactions (lower(merchant_raw));',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_transactions_counterparty_vpa_lower '
          'ON transactions (lower(counterparty_vpa));',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_transactions_lifecycle_state '
          'ON transactions (lifecycle_state);',
        );
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.addColumn(transactions, transactions.counterpartyVpa);
          await migrator.addColumn(transactions, transactions.duplicateOfTxnId);
          await migrator.createIndex(idxTransactionsDuplicateOfTxnId);
        }
        if (from < 3) {
          await migrator.createTable(baselines);
          await migrator.createTable(insights);
          await migrator.createTable(modelMeta);
          await migrator.createTable(recurringSeries);
          await migrator.createIndex(idxInsightsPeriod);
          await migrator.createIndex(idxRecurringSeriesMerchantId);
          await migrator.createIndex(idxRecurringSeriesNextExpectedDate);
        }
        if (from < 4) {
          await migrator.addColumn(merchants, merchants.userLabel);
        }
        if (from < 5) {
          await migrator.createTable(paymentSources);
          await migrator.addColumn(
            transactions,
            transactions.paymentSourceId,
          );
          await migrator.addColumn(
            transactions,
            transactions.ownedTransferId,
          );
          await migrator.addColumn(
            transactions,
            transactions.isAnalyticsExcluded,
          );
          await migrator.createIndex(idxTransactionsPaymentSourceId);
          await migrator.createIndex(idxTransactionsOwnedTransferId);
          await _backfillPaymentSources();
        }
        if (from >= 5 && from < 7) {
          // Early payment_sources tables were shipped with more than one
          // physical shape. Besides nullable required values and millisecond
          // datetimes, some v6 devices lack later optional columns such as
          // institution entirely. Repair the table shape and rows in place —
          // never by clearing app data — then recreate the corrected trigger.
          await _repairPaymentSourcesV6();
        }
        if (from < 8) {
          await migrator.addColumn(transactions, transactions.evidenceJson);
        }
        if (from < 9) {
          await migrator.addColumn(transactions, transactions.lifecycleState);
          await migrator.addColumn(transactions, transactions.lifecycleReason);
          await migrator.addColumn(transactions, transactions.messageKind);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_transactions_lifecycle_state '
            'ON transactions (lifecycle_state);',
          );
        }
        if (from < 10) {
          await migrator.createTable(financialEvents);
          await migrator.createTable(transactionLinks);
        }
        if (from < 11) {
          await migrator.createTable(counterparties);
        }
        if (from < 12) {
          await migrator.createTable(expectedEvents);
        }
        if (from < 13) {
          await migrator.createTable(featureFlags);
        }
        if (from < 14) {
          final rawSmsTables = await customSelect(
            'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
            variables: [
              Variable.withString('table'),
              Variable.withString('raw_sms'),
            ],
          ).get();
          if (rawSmsTables.isEmpty) {
            // raw_sms was introduced after some of the legacy schemas. Create
            // the complete current table for those installs; adding columns
            // to a table that does not exist would abort the whole upgrade.
            await migrator.createTable(rawSms);
          } else {
            final rawSmsColumns = await customSelect(
              'PRAGMA table_info(raw_sms)',
            ).get();
            final columnNames = <String>{};
            for (final row in rawSmsColumns) {
              columnNames.add(row.data['name'] as String);
            }
            if (!columnNames.contains('parser_version')) {
              await migrator.addColumn(rawSms, rawSms.parserVersion);
            }
            if (!columnNames.contains('failure_reason')) {
              await migrator.addColumn(rawSms, rawSms.failureReason);
            }
          }
        }
        if (from < 15) {
          await migrator.createTable(payeeEvidence);
          await _backfillPayeeEvidence();
        }
        if (from < 16) {
          await migrator.createTable(shadowTransactions);
        }
        // Generated row mapping expects the latest non-null/defaulted columns,
        // so legacy data backfills run only after every additive step above.
        if (from < 2) await _backfillDuplicateLinks();
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
        try {
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_transactions_merchant_raw_lower '
            'ON transactions (lower(merchant_raw));',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_transactions_counterparty_vpa_lower '
            'ON transactions (lower(counterparty_vpa));',
          );
        } on Exception catch (_) {
          // Ignore index creation errors during migration from pre-v2 schemas where
          // merchant_raw / counterparty_vpa columns are not yet present.
        }
        await _ensurePaymentSourceTrigger();
      },
    );
  }

  Future<void> _backfillPayeeEvidence() async {
    final rows = await select(transactions).get();
    final evidence = <PayeeEvidenceCompanion>[];
    for (final transaction in rows) {
      _addPayeeEvidence(
        evidence,
        transactionId: transaction.id,
        evidenceType: 'merchant_raw',
        value: transaction.merchantRaw,
      );
      _addPayeeEvidence(
        evidence,
        transactionId: transaction.id,
        evidenceType: 'counterparty_vpa',
        value: transaction.counterpartyVpa,
      );
    }
    if (evidence.isEmpty) return;
    await batch((batch) {
      batch.insertAll(payeeEvidence, evidence);
    });
  }

  void _addPayeeEvidence(
    List<PayeeEvidenceCompanion> rows, {
    required String transactionId,
    required String evidenceType,
    required String? value,
  }) {
    final displayValue = value?.trim();
    if (displayValue == null || displayValue.isEmpty) return;
    final normalizedKey = PayeeIdentityKey.normalize(displayValue);
    if (normalizedKey.isEmpty) return;
    rows.add(
      PayeeEvidenceCompanion.insert(
        transactionId: transactionId,
        evidenceType: evidenceType,
        normalizedKey: normalizedKey,
        displayValue: displayValue,
      ),
    );
  }

  /// v1->v2 (ADR 0003): v1 suppressed cross-source echoes by setting
  /// `is_deleted=1` (the same flag now reserved for user delete). For each
  /// such row, re-run the pairing rule against the other non-suppressed rows
  /// in this database; a unique match converts the row to the new
  /// `duplicate_of_txn_id` link and clears `is_deleted`. No match (or more
  /// than one candidate) is conservative: the row stays hidden
  /// (`is_deleted=1`) rather than guessing, and is logged for manual review.
  Future<void> _backfillDuplicateLinks() async {
    final suppressed = await (select(transactions)
          ..where((t) => t.isDeleted.equals(true)))
        .get();
    if (suppressed.isEmpty) return;

    const rule = DuplicateMatchRule(
      window: Duration(minutes: AppConstants.duplicatePairWindowMinutes),
      amountTolerance: 0.005,
    );
    var unresolved = 0;

    for (final echo in suppressed) {
      final candidates = await (select(transactions)
            ..where(
              (t) => t.id.equals(echo.id).not() & t.isDeleted.equals(false),
            ))
          .get();

      final echoTs = DateTime.fromMillisecondsSinceEpoch(echo.ts, isUtc: true);
      final echoKey = DuplicateMatchRule.counterpartyKeyOf(
        null,
        echo.merchantRaw,
      );
      final matches = candidates.where(
        (existing) => rule.matches(
          direction: echo.direction,
          amount: echo.amount,
          ts: echoTs,
          refId: echo.refId,
          counterpartyKey: echoKey,
          existing: existing,
        ),
      );

      if (matches.length == 1) {
        await (update(transactions)..where((t) => t.id.equals(echo.id))).write(
          TransactionsCompanion(
            duplicateOfTxnId: Value(matches.single.id),
            isDeleted: const Value(false),
          ),
        );
      } else {
        unresolved++;
      }
    }

    if (unresolved > 0) {
      developer.log(
        '$unresolved suppressed row(s) had no unique match during the v2 '
        'duplicate-link backfill; left is_deleted=1',
        name: 'AppDatabase.migration',
      );
    }
  }

  Future<void> _backfillPaymentSources() async {
    await customStatement('''
      INSERT OR IGNORE INTO payment_sources
        (id, kind, masked_identifier, is_active, include_in_analytics, is_owned,
         created_at, updated_at)
      SELECT DISTINCT
        'source_' || lower(replace(replace(replace(trim(account_hint),
          ' ', ''), '*', 'x'), '-', '')) || '_' || lower(channel),
        lower(channel), trim(account_hint), 1, 1, 1,
        CAST(unixepoch() AS INTEGER),
        CAST(unixepoch() AS INTEGER)
      FROM transactions
      WHERE account_hint IS NOT NULL AND trim(account_hint) <> ''
    ''');
    await customStatement('''
      UPDATE transactions
      SET payment_source_id =
        'source_' || lower(replace(replace(replace(trim(account_hint),
          ' ', ''), '*', 'x'), '-', '')) || '_' || lower(channel)
      WHERE payment_source_id IS NULL
        AND account_hint IS NOT NULL AND trim(account_hint) <> ''
    ''');
  }

  /// Repairs legacy `payment_sources` shapes and rows to match the generated
  /// v7 mapper, then normalizes millisecond datetimes written by the old
  /// backfill/trigger back to the second-based values drift expects.
  ///
  /// Idempotent: it only fills NULLs and rescales values that are unambiguously
  /// in milliseconds, so running it on an already-correct table is a no-op.
  /// It also drops the old millisecond-writing trigger; [_ensurePaymentSourceTrigger]
  /// recreates the corrected one in `beforeOpen` after this migration step.
  Future<void> _repairPaymentSourcesV6() async {
    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    // Every non-key column is added defensively. ADD COLUMN is a
    // no-op-by-failure we tolerate so this works across the multiple v5/v6
    // shapes observed on upgraded devices.
    const addColumns = <String>[
      'ALTER TABLE payment_sources ADD COLUMN kind TEXT',
      'ALTER TABLE payment_sources ADD COLUMN masked_identifier TEXT',
      'ALTER TABLE payment_sources ADD COLUMN nickname TEXT',
      'ALTER TABLE payment_sources ADD COLUMN institution TEXT',
      'ALTER TABLE payment_sources ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1',
      'ALTER TABLE payment_sources ADD COLUMN include_in_analytics INTEGER NOT NULL DEFAULT 1',
      'ALTER TABLE payment_sources ADD COLUMN is_owned INTEGER NOT NULL DEFAULT 1',
      'ALTER TABLE payment_sources ADD COLUMN created_at INTEGER',
      'ALTER TABLE payment_sources ADD COLUMN updated_at INTEGER',
    ];
    for (final statement in addColumns) {
      try {
        await customStatement(statement);
      } on Object {
        // Column already exists — expected on correctly-shaped tables.
      }
    }

    // Fill NULLs in every non-null-typed column with a safe default.
    await customStatement('''
      UPDATE payment_sources SET
        kind = COALESCE(NULLIF(trim(kind), ''), 'unknown'),
        masked_identifier =
          COALESCE(NULLIF(trim(masked_identifier), ''), 'unknown'),
        is_active = COALESCE(is_active, 1),
        include_in_analytics = COALESCE(include_in_analytics, 1),
        is_owned = COALESCE(is_owned, 1),
        created_at = COALESCE(created_at, $nowSeconds),
        updated_at = COALESCE(updated_at, $nowSeconds)
    ''');

    // Rescale ms → s. A real second-based timestamp for this app is ~1.7e9;
    // anything past the year-5138 boundary (1e11 seconds) can only be ms.
    await customStatement('''
      UPDATE payment_sources
      SET created_at = created_at / 1000
      WHERE created_at > 100000000000
    ''');
    await customStatement('''
      UPDATE payment_sources
      SET updated_at = updated_at / 1000
      WHERE updated_at > 100000000000
    ''');

    // Drop the old trigger so beforeOpen recreates the corrected (seconds,
    // is_active) version — CREATE TRIGGER IF NOT EXISTS would otherwise keep it.
    await customStatement(
      'DROP TRIGGER IF EXISTS trg_transactions_payment_source',
    );
  }

  Future<void> _ensurePaymentSourceTrigger() async {
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS trg_transactions_payment_source
      AFTER INSERT ON transactions
      WHEN NEW.payment_source_id IS NULL
        AND NEW.account_hint IS NOT NULL AND trim(NEW.account_hint) <> ''
      BEGIN
        INSERT OR IGNORE INTO payment_sources
          (id, kind, masked_identifier, is_active, include_in_analytics,
           is_owned, created_at, updated_at)
        VALUES (
          'source_' || lower(replace(replace(replace(trim(NEW.account_hint),
            ' ', ''), '*', 'x'), '-', '')) || '_' || lower(NEW.channel),
          lower(NEW.channel), trim(NEW.account_hint), 1, 1, 1,
          CAST(unixepoch() AS INTEGER),
          CAST(unixepoch() AS INTEGER)
        );
        UPDATE transactions
        SET payment_source_id =
              'source_' || lower(replace(replace(replace(trim(NEW.account_hint),
                ' ', ''), '*', 'x'), '-', '')) || '_' || lower(NEW.channel),
            is_analytics_excluded = COALESCE((
              SELECT NOT include_in_analytics FROM payment_sources
              WHERE id = 'source_' || lower(replace(replace(replace(
                trim(NEW.account_hint), ' ', ''), '*', 'x'), '-', '')) ||
                '_' || lower(NEW.channel)
            ), 0)
        WHERE id = NEW.id;
      END
    ''');
  }
}

const _defaultCategoriesAsset = 'assets/seed/categories.json';

CategoriesCompanion _categorySeedToCompanion(Map<String, Object?> json) {
  return CategoriesCompanion.insert(
    id: json['id']! as String,
    name: json['name']! as String,
    parentId: Value(json['parent_id'] as String?),
    icon: json['icon']! as String,
    isSpending: json['is_spending']! as bool,
    sortOrder: json['sort_order']! as int,
    isUserCreated: json['is_user_created']! as bool,
  );
}
