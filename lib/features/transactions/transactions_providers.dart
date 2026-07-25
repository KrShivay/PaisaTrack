import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../data/repositories/transaction_source_repository.dart';

const transactionPageSize = 100;
const reviewPageSize = 100;

final transactionListLimitProvider = StateProvider<int>(
  (ref) => transactionPageSize,
);

final reviewQueueLimitProvider = StateProvider<int>((ref) => reviewPageSize);

/// Live-updating list of non-deleted transactions, newest first.
///
/// Stays in the loading state until the app database has finished opening;
/// rebuilds automatically once it resolves since it watches
/// `appDatabaseProvider` directly.
final transactionListProvider =
    StreamProvider<List<TransactionListItem>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  final limit = ref.watch(transactionListLimitProvider);
  return databaseAsync.when(
    data: (database) => ref
        .watch(transactionRepositoryProvider(database))
        .watchTransactions(limit: limit)
        .handleError((Object error, StackTrace stackTrace) {
      developer.log(
        'Transaction list query failed',
        name: 'paisatrack.transactions',
        error: error,
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }),
    loading: () => const Stream<List<TransactionListItem>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<TransactionListItem>>.error(error, stackTrace),
  );
});

/// Live-updating detail of one transaction (null when the id is unknown),
/// for the detail screen (T-038).
final transactionDetailProvider =
    StreamProvider.family<TransactionDetail?, String>((ref, txnId) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) =>
        ref.watch(transactionRepositoryProvider(database)).watchDetail(txnId),
    loading: () => const Stream<TransactionDetail?>.empty(),
    error: (error, stackTrace) =>
        Stream<TransactionDetail?>.error(error, stackTrace),
  );
});

/// Copy/view provenance actions load independently from the main transaction
/// model so raw SMS retention does not complicate every list and review row.
final transactionSourceProvider =
    StreamProvider.autoDispose.family<TransactionSourceInfo?, String>(
        (ref, txnId) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) => TransactionSourceRepository(database).watch(txnId),
    loading: () => const Stream<TransactionSourceInfo?>.empty(),
    error: (error, stackTrace) =>
        Stream<TransactionSourceInfo?>.error(error, stackTrace),
  );
});

/// Live queue of transactions waiting for weekly batch review.
final reviewQueueProvider = StreamProvider<List<TransactionReviewItem>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  final limit = ref.watch(reviewQueueLimitProvider);
  return databaseAsync.when(
    data: (database) => ref
        .watch(transactionRepositoryProvider(database))
        .watchReviewQueue(limit: limit),
    loading: () => const Stream<List<TransactionReviewItem>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<TransactionReviewItem>>.error(error, stackTrace),
  );
});

final reviewQueueSummaryProvider = StreamProvider<ReviewQueueSummary>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) => ref
        .watch(transactionRepositoryProvider(database))
        .watchReviewQueueSummary(),
    loading: () => const Stream<ReviewQueueSummary>.empty(),
    error: (error, stackTrace) =>
        Stream<ReviewQueueSummary>.error(error, stackTrace),
  );
});

/// Live queue of transactions waiting for ask-now notification answers.
final askQueueProvider = StreamProvider<List<TransactionReviewItem>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) =>
        ref.watch(transactionRepositoryProvider(database)).watchAskQueue(),
    loading: () => const Stream<List<TransactionReviewItem>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<TransactionReviewItem>>.error(error, stackTrace),
  );
});

/// Live-updating list of all categories in seed sort order, for the manual
/// entry form's picker (T-037) and later category surfaces.
final categoryListProvider = StreamProvider<List<Category>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) =>
        ref.watch(categoryRepositoryProvider(database)).watchAll(),
    loading: () => const Stream<List<Category>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<Category>>.error(error, stackTrace),
  );
});
