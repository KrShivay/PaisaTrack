import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

class InsightsRepository {
  const InsightsRepository(this._database);

  final AppDatabase _database;

  /// Marks an insight as dismissed so it no longer appears in the active feed.
  Future<void> dismiss({required String id}) {
    return (_database.update(_database.insights)
          ..where((row) => row.id.equals(id)))
        .write(const InsightsCompanion(dismissed: Value(true)));
  }
}

final insightsRepositoryProvider = FutureProvider<InsightsRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return InsightsRepository(database);
});
