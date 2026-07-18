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
      final ownedSourceIds = (await (_database.select(_database.paymentSources)
                ..where((row) => row.isOwned.equals(true)))
              .get())
          .map((row) => row.id)
          .toSet();
      if (ownedSourceIds.length < 2) return 0;
      final rows = await (_database.select(_database.transactions)
            ..where(
              (row) =>
                  row.paymentSourceId.isIn(ownedSourceIds) &
                  row.isDeleted.equals(false) &
                  row.duplicateOfTxnId.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.ts)]))
          .get();
      final used = <String>{};
      var pairs = 0;

      List<Transaction> candidatesFor(Transaction source) {
        return rows.where((candidate) {
          if (candidate.id == source.id || used.contains(candidate.id)) {
            return false;
          }
          if (candidate.paymentSourceId == source.paymentSourceId) return false;
          if (candidate.direction == source.direction) return false;
          if ((candidate.amount - source.amount).abs() > 0.005) return false;
          return (candidate.ts - source.ts).abs() <=
              const Duration(minutes: 10).inMilliseconds;
        }).toList(growable: false);
      }

      for (final row in rows) {
        if (used.contains(row.id)) continue;
        final candidates = candidatesFor(row);
        if (candidates.length != 1) continue;
        final match = candidates.single;
        final reverse = candidatesFor(match)
            .where((candidate) => candidate.id == row.id)
            .toList(growable: false);
        if (reverse.length != 1) continue;
        final ids = [row.id, match.id]..sort();
        final pairId = 'owned_transfer_${ids.join('_')}';
        await (_database.update(_database.transactions)
              ..where((transaction) => transaction.id.isIn(ids)))
            .write(
          TransactionsCompanion(
            ownedTransferId: Value(pairId),
            updatedAt: Value(clock().toUtc()),
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
