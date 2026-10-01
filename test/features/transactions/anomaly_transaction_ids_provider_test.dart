import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/transactions/transaction_filter_context_providers.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'food',
            name: 'Food',
            icon: 'restaurant',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'contributor',
            ts: DateTime.utc(2026, 7, 1).millisecondsSinceEpoch,
            amount: 900,
            direction: 'debit',
            channel: 'test',
            categoryId: const Value('food'),
            parseSource: 'test',
            confidenceJson: '{}',
            status: 'confirmed',
            createdAt: DateTime.utc(2026, 7, 1),
            updatedAt: DateTime.utc(2026, 7, 1),
          ),
        );
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'anomaly:test:2026-07',
            period: '2026-07',
            kind: 'anomaly',
            payloadJson: jsonEncode({
              'top_transaction_ids': ['contributor'],
            }),
          ),
        );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('anomaly contributors disappear immediately when they become ineligible',
      () async {
    final initial = Completer<void>();
    final emptyResult = Completer<void>();
    final subscription =
        container.listen(anomalyTransactionIdsProvider, (previous, next) {
      if (next.valueOrNull?.contains('contributor') == true &&
          !initial.isCompleted) {
        initial.complete();
      }
      if (next.valueOrNull?.isEmpty == true && !emptyResult.isCompleted) {
        emptyResult.complete();
      }
    });
    addTearDown(subscription.close);
    await initial.future.timeout(const Duration(seconds: 2));

    await (database.update(database.transactions)
          ..where((row) => row.id.equals('contributor')))
        .write(const TransactionsCompanion(isNotTransaction: Value(true)));
    await emptyResult.future.timeout(const Duration(seconds: 2));
  });
}
