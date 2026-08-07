import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

class RecurringRepository {
  const RecurringRepository(this._database);

  final AppDatabase _database;

  /// Updates the status of a recurring series (e.g. 'active', 'cancelled').
  Future<void> setStatus({
    required String seriesId,
    required String status,
    DateTime Function() clock = DateTime.now,
  }) {
    return (_database.update(_database.recurringSeries)
          ..where((row) => row.id.equals(seriesId)))
        .write(RecurringSeriesCompanion(status: Value(status)));
  }
}

final recurringRepositoryProvider = FutureProvider<RecurringRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return RecurringRepository(database);
});
