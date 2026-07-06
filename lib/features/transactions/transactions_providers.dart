import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../data/repositories/transaction_repository.dart';

/// Live-updating list of non-deleted transactions, newest first.
///
/// Stays in the loading state until the app database has finished opening;
/// rebuilds automatically once it resolves since it watches
/// `appDatabaseProvider` directly.
final transactionListProvider = StreamProvider<List<TransactionListItem>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) =>
        ref.watch(transactionRepositoryProvider(database)).watchTransactions(),
    loading: () => const Stream<List<TransactionListItem>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<TransactionListItem>>.error(error, stackTrace),
  );
});
