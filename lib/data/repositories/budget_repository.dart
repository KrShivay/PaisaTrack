import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

/// Repository for storing and retrieving monetary budget and merchant caps
/// inside the encrypted SQLite database (`AppDatabase`), not in plaintext settings JSON.
///
/// In production, monthly budget is nullable (defaults to null if not set).
/// Visual tests and fixtures can override or seed ₹48,000.
class BudgetRepository {
  const BudgetRepository(this._database);

  final AppDatabase _database;

  static const String monthlyBudgetBaselineKey = 'monthly_budget';

  /// Returns the configured monthly budget from the database, or null if not set.
  Future<double?> getMonthlyBudget() async {
    final row = await (_database.select(_database.baselines)
          ..where((b) => b.key.equals(monthlyBudgetBaselineKey)))
        .getSingleOrNull();
    return row?.mean;
  }

  /// Sets or clears the monthly budget in the encrypted database.
  Future<void> setMonthlyBudget(double? amount) async {
    if (amount == null) {
      await (_database.delete(_database.baselines)
            ..where((b) => b.key.equals(monthlyBudgetBaselineKey)))
          .go();
      return;
    }

    await _database.into(_database.baselines).insertOnConflictUpdate(
          BaselinesCompanion(
            key: const Value(monthlyBudgetBaselineKey),
            mean: Value(amount),
            std: const Value(0.0),
            n: const Value(1),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Returns a merchant cap (e.g. key 'cap_Blinkit') or null if not set.
  Future<double?> getMerchantCap(String merchantName) async {
    final key = 'cap_${merchantName.toLowerCase()}';
    final row = await (_database.select(_database.baselines)
          ..where((b) => b.key.equals(key)))
        .getSingleOrNull();
    return row?.mean;
  }

  /// Sets a cap for a merchant in the encrypted database.
  Future<void> setMerchantCap(String merchantName, double cap) async {
    final key = 'cap_${merchantName.toLowerCase()}';
    await _database.into(_database.baselines).insertOnConflictUpdate(
          BaselinesCompanion(
            key: Value(key),
            mean: Value(cap),
            std: const Value(0.0),
            n: const Value(1),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Removes a merchant cap from the encrypted database.
  Future<void> removeMerchantCap(String merchantName) async {
    final key = 'cap_${merchantName.toLowerCase()}';
    await (_database.delete(_database.baselines)
          ..where((b) => b.key.equals(key)))
        .go();
  }
}

final budgetRepositoryProvider = FutureProvider<BudgetRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return BudgetRepository(database);
});

final monthlyBudgetProvider = FutureProvider<double?>((ref) async {
  final repo = await ref.watch(budgetRepositoryProvider.future);
  return repo.getMonthlyBudget();
});
