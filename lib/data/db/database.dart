import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../dedup/duplicate_match_rule.dart';
import 'tables/categories_table.dart';
import 'tables/feedback_table.dart';
import 'tables/merchant_aliases_table.dart';
import 'tables/merchants_table.dart';
import 'tables/raw_sms_table.dart';
import 'tables/rules_table.dart';
import 'tables/transactions_table.dart';

part 'database.g.dart';

/// Drift database for PaisaTrack's local-first encrypted store.
///
/// Schema changes must update `schemaVersion`, add a migration test, and update
/// `docs/schema.md` in the same change.
@DriftDatabase(
  tables: [
    Categories,
    Feedback,
    MerchantAliases,
    Merchants,
    RawSms,
    Rules,
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

  /// Current local schema version.
  @override
  int get schemaVersion => 2;

  /// Creates the initial schema and enables SQLite foreign-key enforcement.
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.addColumn(transactions, transactions.counterpartyVpa);
          await migrator.addColumn(transactions, transactions.duplicateOfTxnId);
          await migrator.createIndex(idxTransactionsDuplicateOfTxnId);
          await _backfillDuplicateLinks();
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
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
    final suppressed =
        await (select(transactions)..where((t) => t.isDeleted.equals(true)))
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
