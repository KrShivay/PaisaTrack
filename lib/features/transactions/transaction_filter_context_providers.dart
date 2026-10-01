import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/analytics/financial_eligibility.dart';
import '../../data/db/database_provider.dart';

final recurringMerchantIdsProvider = StreamProvider<Set<String>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) => (database.select(database.recurringSeries)
          ..where((row) => row.status.equals('active')))
        .watch()
        .map((rows) => {for (final row in rows) row.merchantId}),
    loading: () => const Stream<Set<String>>.empty(),
    error: (error, stackTrace) => Stream<Set<String>>.error(error, stackTrace),
  );
});

final anomalyTransactionIdsProvider = StreamProvider<Set<String>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) => Stream.multi((controller) {
      var active = true;
      Future<void> emitEligibleIds() async {
        final rows = await (database.select(database.insights)
              ..where((row) => row.kind.equals('anomaly')))
            .get();
        final candidates = <String>{};
        for (final row in rows) {
          try {
            final payload = jsonDecode(row.payloadJson);
            if (payload is! Map<String, Object?>) continue;
            final transactionIds = payload['top_transaction_ids'];
            if (transactionIds is List) {
              candidates.addAll(transactionIds.whereType<String>());
            }
          } on FormatException {
            continue;
          }
        }
        final eligible = candidates.isEmpty
            ? <String>{}
            : (await (database.select(database.transactions)
                      ..where(
                        (row) =>
                            row.id.isIn(candidates) &
                            FinancialEligibility.spendingDebit(
                              row,
                              database.categories,
                            ),
                      ))
                    .get())
                .map((row) => row.id)
                .toSet();
        if (active) controller.add(eligible);
      }

      unawaited(emitEligibleIds());
      final updates = database
          .tableUpdates(
            TableUpdateQuery.onAllTables([
              database.insights,
              database.transactions,
              database.categories,
            ]),
          )
          .listen((_) => unawaited(emitEligibleIds()));
      controller.onCancel = () {
        active = false;
        return updates.cancel();
      };
    }),
    loading: () => const Stream<Set<String>>.empty(),
    error: (error, stackTrace) => Stream<Set<String>>.error(error, stackTrace),
  );
});
