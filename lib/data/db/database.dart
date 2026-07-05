import 'package:drift/drift.dart';

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
