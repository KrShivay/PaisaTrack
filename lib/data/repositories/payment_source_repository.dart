import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

class PaymentSourceSummary {
  const PaymentSourceSummary({
    required this.id,
    required this.kind,
    required this.maskedIdentifier,
    required this.includeInAnalytics,
    required this.isOwned,
    required this.isActive,
    required this.transactionCount,
    required this.transferCount,
    this.nickname,
    this.institution,
  });

  final String id;
  final String kind;
  final String maskedIdentifier;
  final String? nickname;
  final String? institution;
  final bool includeInAnalytics;
  final bool isOwned;
  final bool isActive;
  final int transactionCount;
  final int transferCount;

  String get displayName =>
      nickname?.trim().isNotEmpty == true ? nickname!.trim() : maskedIdentifier;
}

class PaymentSourceRepository {
  const PaymentSourceRepository(this._database);

  final AppDatabase _database;

  Stream<List<PaymentSourceSummary>> watchSources() {
    final query = _database.select(_database.paymentSources).join([
      leftOuterJoin(
        _database.transactions,
        _database.transactions.paymentSourceId
            .equalsExp(_database.paymentSources.id),
      ),
    ]);
    return query.watch().map((rows) {
      final builders = <String, _PaymentSourceSummaryBuilder>{};
      for (final row in rows) {
        final source = row.readTable(_database.paymentSources);
        final builder = builders.putIfAbsent(
          source.id,
          () => _PaymentSourceSummaryBuilder(source),
        );
        final transaction = row.readTableOrNull(_database.transactions);
        if (transaction != null) {
          builder.transactionCount += 1;
          if (transaction.ownedTransferId != null) {
            builder.transferIds.add(transaction.ownedTransferId!);
          }
        }
      }
      final sources = builders.values.map((value) => value.build()).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      return sources;
    });
  }

  Future<void> updateSource({
    required String sourceId,
    Value<String?> nickname = const Value.absent(),
    Value<String?> institution = const Value.absent(),
    Value<bool> includeInAnalytics = const Value.absent(),
    Value<bool> isOwned = const Value.absent(),
    Value<bool> isActive = const Value.absent(),
    DateTime Function() clock = DateTime.now,
  }) async {
    final now = clock().toUtc();
    await _database.transaction(() async {
      await (_database.update(_database.paymentSources)
            ..where((row) => row.id.equals(sourceId)))
          .write(
        PaymentSourcesCompanion(
          nickname: nickname,
          institution: institution,
          includeInAnalytics: includeInAnalytics,
          isOwned: isOwned,
          isActive: isActive,
          updatedAt: Value(now),
        ),
      );
      if (includeInAnalytics.present) {
        await (_database.update(_database.transactions)
              ..where((row) => row.paymentSourceId.equals(sourceId)))
            .write(
          TransactionsCompanion(
            isAnalyticsExcluded: Value(!includeInAnalytics.value),
            updatedAt: Value(now),
          ),
        );
      }
    });
    if (isOwned.present) await reconcileOwnedTransfers(clock: clock);
  }

  /// Links only unambiguous opposite-direction pairs between owned sources.
  Future<int> reconcileOwnedTransfers({
    DateTime Function() clock = DateTime.now,
  }) {
    return _database.transaction(() async {
      await _database.update(_database.transactions).write(
            const TransactionsCompanion(ownedTransferId: Value(null)),
          );
      final ownedSources = await (_database.select(_database.paymentSources)
            ..where((row) => row.isOwned.equals(true) & row.isActive.equals(true)))
          .get();
      final ownedSourceIds = ownedSources.map((row) => row.id).toSet();
      if (ownedSourceIds.length < 2) return 0;

      final rows = await _database.customSelect(
        '''
SELECT t1.id AS id1, t2.id AS id2
FROM transactions t1
JOIN transactions t2 ON t1.amount = t2.amount
  AND t1.direction != t2.direction
  AND t1.payment_source_id != t2.payment_source_id
  AND ABS(t1.ts - t2.ts) <= 600000
  AND t1.payment_source_id IN (SELECT id FROM payment_sources WHERE is_owned = 1 AND is_active = 1)
  AND t2.payment_source_id IN (SELECT id FROM payment_sources WHERE is_owned = 1 AND is_active = 1)
WHERE t1.is_deleted = 0 AND t1.duplicate_of_txn_id IS NULL AND t1.owned_transfer_id IS NULL
  AND t2.is_deleted = 0 AND t2.duplicate_of_txn_id IS NULL AND t2.owned_transfer_id IS NULL
ORDER BY t1.ts ASC
''',
        readsFrom: {_database.transactions, _database.paymentSources},
      ).get();

      final used = <String>{};
      var pairs = 0;

      for (final row in rows) {
        final id1 = row.read<String>('id1');
        final id2 = row.read<String>('id2');
        if (used.contains(id1) || used.contains(id2)) continue;

        final ids = [id1, id2]..sort();
        final pairId = 'owned_transfer_${ids.join('_')}';
        final nowMs = clock().toUtc().millisecondsSinceEpoch;

        await (_database.update(_database.transactions)
              ..where((transaction) => transaction.id.isIn(ids)))
            .write(
          TransactionsCompanion(
            ownedTransferId: Value(pairId),
            updatedAt: Value(clock().toUtc()),
          ),
        );

        await _database.into(_database.transactionLinks).insertOnConflictUpdate(
              TransactionLinksCompanion.insert(
                id: 'link_${ids.join('_')}',
                fromTxnId: id1,
                toTxnId: id2,
                linkType: 'transfer_leg',
                basis: 'indexed_owned_transfer',
                createdAt: nowMs,
              ),
            );

        used.addAll(ids);
        pairs += 1;
      }
      return pairs;
    });
  }
}

class _PaymentSourceSummaryBuilder {
  _PaymentSourceSummaryBuilder(this.source);

  final PaymentSource source;
  final Set<String> transferIds = {};
  int transactionCount = 0;

  PaymentSourceSummary build() => PaymentSourceSummary(
        id: source.id,
        kind: source.kind,
        maskedIdentifier: source.maskedIdentifier,
        nickname: source.nickname,
        institution: source.institution,
        includeInAnalytics: source.includeInAnalytics,
        isOwned: source.isOwned,
        isActive: source.isActive,
        transactionCount: transactionCount,
        transferCount: transferIds.length,
      );
}

final paymentSourceRepositoryProvider = FutureProvider<PaymentSourceRepository>(
  (ref) async =>
      PaymentSourceRepository(await ref.watch(appDatabaseProvider.future)),
);

final paymentSourcesProvider = StreamProvider<List<PaymentSourceSummary>>(
  (ref) async* {
    final repository = await ref.watch(paymentSourceRepositoryProvider.future);
    await repository.reconcileOwnedTransfers();
    yield* repository.watchSources();
  },
);
