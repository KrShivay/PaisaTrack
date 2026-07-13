import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    data: (database) => (database.select(database.insights)
          ..where((row) => row.kind.equals('anomaly')))
        .watch()
        .map((rows) {
      final ids = <String>{};
      for (final row in rows) {
        try {
          final payload = jsonDecode(row.payloadJson);
          if (payload is! Map<String, Object?>) continue;
          final transactionIds = payload['top_transaction_ids'];
          if (transactionIds is! List) continue;
          ids.addAll(transactionIds.whereType<String>());
        } on FormatException {
          continue;
        }
      }
      return ids;
    }),
    loading: () => const Stream<Set<String>>.empty(),
    error: (error, stackTrace) => Stream<Set<String>>.error(error, stackTrace),
  );
});
