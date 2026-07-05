import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

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
  int get schemaVersion => 1;

  /// Creates the initial schema and enables SQLite foreign-key enforcement.
  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
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
