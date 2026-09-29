import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';
import 'recurring_status_memory.dart';

class RecurringRepository {
  const RecurringRepository(this._database);

  final AppDatabase _database;

  /// Updates the status of a recurring series (e.g. 'active', 'cancelled').
  Future<void> setStatus({
    required String seriesId,
    required String status,
    DateTime Function() clock = DateTime.now,
  }) async {
    await _database.transaction(() async {
      await (_database.update(_database.recurringSeries)
            ..where((row) => row.id.equals(seriesId)))
          .write(RecurringSeriesCompanion(status: Value(status)));
      final series = await (_database.select(_database.recurringSeries)
            ..where((row) => row.id.equals(seriesId)))
          .getSingleOrNull();
      if (series != null) {
        await RecurringStatusMemory.set(
          _database,
          series: series,
          status: status,
        );
      }
    });
  }
}

final recurringRepositoryProvider =
    FutureProvider<RecurringRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return RecurringRepository(database);
});
