import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../data/repositories/raw_sms_repository.dart';
import '../../capture/template_engine/template_trust_ledger.dart';

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

/// Watches developer-visible public-template demotion alerts from the ledger.
final templateTrustAlertsProvider = StreamProvider<List<TemplateTrustEntry>>(
  (ref) {
    final databaseAsync = ref.watch(appDatabaseProvider);
    return databaseAsync.when(
      data: (database) => TemplateTrustLedger(database)
          .watch()
          .map((snapshot) => snapshot.flaggedEntries),
      loading: () => const Stream<List<TemplateTrustEntry>>.empty(),
      error: (error, stackTrace) =>
          Stream<List<TemplateTrustEntry>>.error(error, stackTrace),
    );
  },
);

/// Groups unparsed raw SMS by sender and sorts them by frequency descending.
final unrecognizedSenderCountsProvider =
    Provider<List<MapEntry<String, int>>>((ref) {
  final unparsed = ref.watch(unparsedSmsListProvider).valueOrNull ?? const [];
  final counts = <String, int>{};
  for (final item in unparsed) {
    final sender = item.sender.toUpperCase().trim();
    if (sender.isNotEmpty) {
      counts[sender] = (counts[sender] ?? 0) + 1;
    }
  }
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted;
});

