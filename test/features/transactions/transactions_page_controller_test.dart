import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

Future<void> _insertTransaction(AppDatabase database, String id, DateTime ts) {
  return database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: ts.millisecondsSinceEpoch,
          amount: 100,
          direction: 'debit',
          channel: 'upi',
          categoryId: const Value(null),
          parseSource: 'template',
          confidenceJson: '{}',
          status: 'confirmed',
          createdAt: ts,
          updatedAt: ts,
        ),
      );
}

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('Activity controller loads the next keyset page without offset growth',
      () async {
    final base = DateTime.utc(2026, 1, 1);
    for (var index = 0; index < 201; index++) {
      await _insertTransaction(
        database,
        'controller_${index.toString().padLeft(3, '0')}',
        base.add(Duration(minutes: index % 5, days: index ~/ 5)),
      );
    }

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
      ],
    );
    addTearDown(container.dispose);

    final first = await container.read(activityTransactionPageProvider.future);
    expect(first.rows, hasLength(100));
    expect(first.hasMore, isTrue);

    // This row sorts before the first page's cursor and must not shift the
    // continuation boundary.
    await _insertTransaction(
      database,
      'controller_inserted_between_pages',
      base.add(const Duration(days: 100)),
    );

    await container.read(activityTransactionPageProvider.notifier).loadMore();
    final second = container.read(activityTransactionPageProvider).value!;
    final ids = second.rows.map((row) => row.id).toList();

    expect(ids, hasLength(200));
    expect(ids.toSet(), hasLength(200));
    expect(ids, isNot(contains('controller_inserted_between_pages')));
    expect(second.hasMore, isTrue);

    await container.read(activityTransactionPageProvider.notifier).loadMore();
    final terminal = container.read(activityTransactionPageProvider).value!;
    expect(terminal.rows, hasLength(201));
    expect(terminal.hasMore, isFalse);
    expect(terminal.nextCursor == null, isTrue);
  });
}
