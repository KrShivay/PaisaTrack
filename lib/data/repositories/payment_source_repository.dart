import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

const _ownedTransferWindowMs = 10 * 60 * 1000;
const _ownedTransferLinkDeleteBatchSize = 500;

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
      paymentSourceDisplayName(nickname, maskedIdentifier);
}

/// The user's nickname for a payment source, else its stored masked id.
String paymentSourceDisplayName(String? nickname, String maskedIdentifier) =>
    nickname?.trim().isNotEmpty == true ? nickname!.trim() : maskedIdentifier;

class PaymentSourceRepository {
  const PaymentSourceRepository(this._database);

  final AppDatabase _database;

  /// Watches the display name of one source; null when it does not exist.
  Stream<String?> watchDisplayName(String id) {
    return (_database.select(_database.paymentSources)
          ..where((row) => row.id.equals(id)))
        .watchSingleOrNull()
        .map(
          (source) => source == null
              ? null
              : paymentSourceDisplayName(
                  source.nickname,
                  source.maskedIdentifier,
                ),
        );
  }

  Stream<List<PaymentSourceSummary>> watchSources() {
    final query = _database.select(_database.paymentSources).join([
      leftOuterJoin(
        _database.transactions,
        _database.transactions.paymentSourceId
                .equalsExp(_database.paymentSources.id) &
            _database.transactions.isNotTransaction.equals(false),
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
    if (isOwned.present || isActive.present) {
      await reconcileOwnedTransfers(clock: clock);
    }
  }

  /// Links only unambiguous opposite-direction pairs between owned sources.
  Future<int> reconcileOwnedTransfers({
    DateTime Function() clock = DateTime.now,
  }) {
    return _database.transaction(() async {
      final rows = await _database.customSelect(
        '''
-- The eligible source facts intentionally ignore prior owned_transfer_id flags.
WITH eligible AS NOT MATERIALIZED (
  SELECT t.id, t.ts, t.amount, t.direction, t.currency_code,
         t.currency_symbol, t.payment_source_id
  FROM transactions t
  JOIN payment_sources ps ON ps.id = t.payment_source_id
  WHERE ps.is_owned = 1 AND ps.is_active = 1
    AND t.is_deleted = 0 AND t.is_not_transaction = 0
    AND t.duplicate_of_txn_id IS NULL AND t.lifecycle_state = 'settled'
    AND t.direction IN ('debit', 'credit')
), neighbors AS MATERIALIZED (
  SELECT t.id, t.direction,
    (${_ownedTransferCandidateProbe(offset: 0)}) AS neighbor_id,
    (${_ownedTransferCandidateProbe(offset: 1)}) AS second_neighbor_id
  FROM eligible t
), unique_neighbors AS MATERIALIZED (
  SELECT id, direction, neighbor_id
  FROM neighbors
  WHERE neighbor_id IS NOT NULL AND second_neighbor_id IS NULL
)
SELECT debit.id AS debit_id, credit.id AS credit_id
FROM unique_neighbors debit_neighbor
JOIN eligible debit ON debit.id = debit_neighbor.id
JOIN eligible credit ON credit.id = debit_neighbor.neighbor_id
JOIN unique_neighbors credit_neighbor
  ON credit_neighbor.id = credit.id
 AND credit_neighbor.neighbor_id = debit.id
WHERE debit.direction = 'debit' AND credit.direction = 'credit'
ORDER BY debit.id, credit.id
''',
        readsFrom: {_database.transactions, _database.paymentSources},
      ).get();

      final pairIdsByTransaction = <String, String>{};
      final desiredLinksByPair = <String, _OwnedTransferLink>{};
      for (final row in rows) {
        final debitId = row.read<String>('debit_id');
        final creditId = row.read<String>('credit_id');
        final pairParts = [debitId, creditId]..sort();
        final pairKey = _ownedTransferPairKey(pairParts[0], pairParts[1]);
        final transferId = 'owned_transfer_$pairKey';
        pairIdsByTransaction[debitId] = transferId;
        pairIdsByTransaction[creditId] = transferId;
        desiredLinksByPair[pairKey] = _OwnedTransferLink(
          debitId: debitId,
          creditId: creditId,
        );
      }

      // Re-derive the complete projection from source evidence. Old flags must
      // not hide a newly valid pair or keep a pair that has become stale.
      final currentTransfers = await (_database.select(
        _database.transactions,
      )..where((row) => row.ownedTransferId.isNotNull()))
          .get();
      final currentIdsByTransaction = {
        for (final row in currentTransfers) row.id: row.ownedTransferId,
      };
      final now = clock().toUtc();
      for (final entry in pairIdsByTransaction.entries) {
        if (currentIdsByTransaction[entry.key] == entry.value) continue;
        await (_database.update(_database.transactions)
              ..where((row) => row.id.equals(entry.key)))
            .write(
          TransactionsCompanion(
            ownedTransferId: Value(entry.value),
            updatedAt: Value(now),
          ),
        );
      }
      for (final entry in currentIdsByTransaction.entries) {
        if (pairIdsByTransaction.containsKey(entry.key)) continue;
        await (_database.update(_database.transactions)
              ..where((row) => row.id.equals(entry.key)))
            .write(
          TransactionsCompanion(
            ownedTransferId: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }

      final existingGeneratedLinks = await (_database.select(
        _database.transactionLinks,
      )
            ..where(
              (link) =>
                  link.createdBy.equals('system') &
                  link.basis.equals('indexed_owned_transfer') &
                  link.linkType.equals('transfer_leg'),
            )
            ..orderBy([(link) => OrderingTerm.asc(link.id)]))
          .get();
      final retainedByPair = <String, TransactionLink>{};
      final deleteLinkIds = <String>[];
      for (final link in existingGeneratedLinks) {
        final endpointIds = [link.fromTxnId, link.toTxnId]..sort();
        final key = _ownedTransferPairKey(endpointIds[0], endpointIds[1]);
        if (desiredLinksByPair.containsKey(key) &&
            !retainedByPair.containsKey(key)) {
          retainedByPair[key] = link;
        } else {
          deleteLinkIds.add(link.id);
        }
      }
      // Keep parameter lists below SQLite builds' commonly supported 999 bind
      // variables while all chunks remain inside this outer transaction.
      for (var offset = 0;
          offset < deleteLinkIds.length;
          offset += _ownedTransferLinkDeleteBatchSize) {
        final batch = deleteLinkIds
            .skip(offset)
            .take(_ownedTransferLinkDeleteBatchSize)
            .toList();
        await (_database.delete(_database.transactionLinks)
              ..where((link) => link.id.isIn(batch)))
            .go();
      }

      final occupiedIds = await (_database.selectOnly(
        _database.transactionLinks,
      )..addColumns([_database.transactionLinks.id]))
          .get();
      final occupiedLinkIds = occupiedIds
          .map((row) => row.read(_database.transactionLinks.id))
          .whereType<String>()
          .toSet();
      for (final entry in desiredLinksByPair.entries) {
        if (retainedByPair.containsKey(entry.key)) continue;
        final pair = entry.value;
        final preferredId = 'link_${pair.debitId}_${pair.creditId}';
        var linkId = preferredId;
        var suffix = 1;
        while (occupiedLinkIds.contains(linkId)) {
          linkId =
              'system_owned_transfer_${pair.debitId}_${pair.creditId}_$suffix';
          suffix += 1;
        }
        final link = TransactionLink(
          id: linkId,
          fromTxnId: pair.debitId,
          toTxnId: pair.creditId,
          linkType: 'transfer_leg',
          confidence: 1,
          basis: 'indexed_owned_transfer',
          createdBy: 'system',
          createdAt: now.millisecondsSinceEpoch,
        );
        await _database.into(_database.transactionLinks).insert(link);
        occupiedLinkIds.add(linkId);
      }
      return desiredLinksByPair.length;
    });
  }

  String _ownedTransferCandidateProbe({required int offset}) => '''
SELECT c.id
FROM transactions c INDEXED BY idx_transactions_ts
JOIN payment_sources cps ON cps.id = c.payment_source_id
WHERE c.ts BETWEEN t.ts - $_ownedTransferWindowMs
      AND t.ts + $_ownedTransferWindowMs
  AND c.amount = t.amount AND c.direction != t.direction
  AND c.direction IN ('debit', 'credit')
  AND c.payment_source_id != t.payment_source_id
  AND c.currency_code IS t.currency_code
  AND c.currency_symbol IS t.currency_symbol
  AND cps.is_owned = 1 AND cps.is_active = 1
  AND c.is_deleted = 0 AND c.is_not_transaction = 0
  AND c.duplicate_of_txn_id IS NULL AND c.lifecycle_state = 'settled'
-- Ordering is unnecessary: one candidate is a singleton; a second is ambiguous.
LIMIT 1 OFFSET $offset
''';
}

String _ownedTransferPairKey(String firstId, String secondId) =>
    '${firstId.length}:$firstId${secondId.length}:$secondId';

class _OwnedTransferLink {
  const _OwnedTransferLink({
    required this.debitId,
    required this.creditId,
  });

  final String debitId;
  final String creditId;
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
