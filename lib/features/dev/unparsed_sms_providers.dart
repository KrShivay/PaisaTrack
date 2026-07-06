import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../data/repositories/raw_sms_repository.dart';

/// Live-updating list of raw SMS that have not produced a transaction.
///
/// Stays in the loading state until the app database has finished opening;
/// rebuilds automatically once it resolves since it watches
/// `appDatabaseProvider` directly.
final unparsedSmsListProvider = StreamProvider<List<UnparsedSms>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) =>
        ref.watch(rawSmsRepositoryProvider(database)).watchUnparsed(),
    loading: () => const Stream<List<UnparsedSms>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<UnparsedSms>>.error(error, stackTrace),
  );
});
