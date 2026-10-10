// TEMPORARY STUB: replaced by the real implementation at merge.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

enum RecurringOverride { automatic, recurring, notRecurring }

class RecurringOverrideRepository {
  RecurringOverrideRepository(this._db);

  // ignore: unused_field
  final AppDatabase _db;

  Future<void> setOverride(
    String transactionId,
    RecurringOverride value,
  ) async {}

  Future<RecurringOverride> overrideFor(String transactionId) async =>
      RecurringOverride.automatic;
}

final recurringOverrideRepositoryProvider =
    FutureProvider<RecurringOverrideRepository>(
  (ref) async => RecurringOverrideRepository(
    await ref.watch(appDatabaseProvider.future),
  ),
);

final transactionRecurringOverrideProvider =
    StreamProvider.family<RecurringOverride, String>(
  (ref, transactionId) => Stream.value(RecurringOverride.automatic),
);

final transactionDetectedRecurringProvider =
    FutureProvider.family<bool, String>((ref, transactionId) async => false);
