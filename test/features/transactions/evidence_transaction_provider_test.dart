import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/core/widgets/transaction_filter_sheet.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

void main() {
  test('equal filters share one watch and disposal closes it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repository = _WatchRepository(db);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => db),
        transactionRepositoryProvider.overrideWith((ref, _) => repository),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await container.read(appDatabaseProvider.future);
    const first = TransactionFilters(ids: {'a', 'b'});
    const equal = TransactionFilters(ids: {'b', 'a'});
    final firstSubscription = container.listen(
      evidenceTransactionPageProvider(first),
      (_, __) {},
    );
    final secondSubscription = container.listen(
      evidenceTransactionPageProvider(equal),
      (_, __) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(repository.watchCount, 1);

    firstSubscription.close();
    await Future<void>.delayed(Duration.zero);
    expect(repository.cancelCount, 0);
    secondSubscription.close();
    await container.pump();
    expect(repository.cancelCount, 1);
  });
}

class _WatchRepository extends TransactionRepository {
  _WatchRepository(super.database);

  var watchCount = 0;
  var cancelCount = 0;

  @override
  Stream<ActivityTransactionPage> watchTransactionPage({
    int limit = 100,
    DateTime? start,
    DateTime? end,
    ActivityTransactionCursor? cursor,
    Set<String>? transactionIds,
  }) {
    watchCount++;
    return StreamController<ActivityTransactionPage>(
      onCancel: () => cancelCount++,
    ).stream;
  }
}
