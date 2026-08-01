import 'dart:async';
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

/// Bounded Activity page with explicit continuation state. Dashboard and
/// other aggregate consumers keep using `transactionListProvider` until they
/// are migrated to their own query contracts.
final activityTransactionPageProvider = AsyncNotifierProvider<
    ActivityTransactionPageController,
    ActivityTransactionPage>(ActivityTransactionPageController.new);

/// Retains only the pages the user has explicitly opened. Each page has a
/// strict `(ts,id)` boundary, so inserts/deletes before that boundary do not
/// shift the next page or cause duplicate/gapped rows.
class ActivityTransactionPageController
    extends AsyncNotifier<ActivityTransactionPage> {
  final _pages = <_ActivityLoadedPage>[];
  final _subscriptions = <StreamSubscription<ActivityTransactionPage>>[];
  TransactionRepository? _repository;
  bool _isReady = false;
  bool _isLoadingMore = false;

  @override
  Future<ActivityTransactionPage> build() async {
    final database = await ref.watch(appDatabaseProvider.future);
    _repository = ref.read(transactionRepositoryProvider(database));
    ref.onDispose(() {
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
      _subscriptions.clear();
    });

    await _watchPage(null);
    _isReady = true;
    return _aggregate();
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_isReady) return;
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.nextCursor == null) {
      return;
    }

    final cursor = current.nextCursor!;
    if (_pages.any((page) => page.cursor == cursor)) return;

    _isLoadingMore = true;
    try {
      await _watchPage(cursor);
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<ActivityTransactionPage> _watchPage(
    ActivityTransactionCursor? cursor,
  ) {
    final repository = _repository;
    if (repository == null) {
      return Future.error(StateError('Activity repository is not ready'));
    }

    final completer = Completer<ActivityTransactionPage>();
    late final StreamSubscription<ActivityTransactionPage> subscription;
    subscription = repository
        .watchTransactionPage(limit: transactionPageSize, cursor: cursor)
        .listen(
      (page) {
        final index = _pages.indexWhere((loaded) => loaded.cursor == cursor);
        if (index == -1) {
          _pages.add(_ActivityLoadedPage(cursor: cursor, page: page));
        } else if (_sameRowMembership(_pages[index].page, page)) {
          _pages[index] = _ActivityLoadedPage(cursor: cursor, page: page);
        } else {
          // A live insert/delete would move the page boundary. Keep the
          // snapshot used by the cursor stable until the user reopens the
          // Activity page, otherwise the next fetch could gap or duplicate.
          return;
        }
        if (!completer.isCompleted) completer.complete(page);
        if (_isReady) state = AsyncData(_aggregate());
      },
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'Activity transaction page query failed',
          name: 'paisatrack.transactions',
          error: error,
          stackTrace: stackTrace,
        );
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        } else if (_isReady) {
          state = AsyncError(error, stackTrace);
        }
      },
    );
    _subscriptions.add(subscription);
    return completer.future;
  }

  ActivityTransactionPage _aggregate() {
    final rows = <TransactionListItem>[];
    for (final loaded in _pages) {
      rows.addAll(loaded.page.rows);
    }
    final lastPage = _pages.last.page;
    return ActivityTransactionPage(
      rows: List.unmodifiable(rows),
      hasMore: lastPage.hasMore,
      nextCursor: lastPage.nextCursor,
    );
  }

  bool _sameRowMembership(
    ActivityTransactionPage previous,
    ActivityTransactionPage next,
  ) {
    if (previous.rows.length != next.rows.length) return false;
    for (var index = 0; index < previous.rows.length; index++) {
      if (previous.rows[index].id != next.rows[index].id) return false;
    }
    return true;
  }
}

class _ActivityLoadedPage {
  const _ActivityLoadedPage({required this.cursor, required this.page});

  final ActivityTransactionCursor? cursor;
  final ActivityTransactionPage page;
}

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
final transactionSourceProvider = StreamProvider.autoDispose
    .family<TransactionSourceInfo?, String>((ref, txnId) {
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
