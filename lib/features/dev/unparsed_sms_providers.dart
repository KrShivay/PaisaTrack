import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/template_engine/template_trust_ledger.dart';
import '../../data/db/database_provider.dart';
import '../../data/repositories/raw_sms_repository.dart';

/// Live-updating list of raw SMS that have not produced a transaction.
final unparsedSmsListProvider =
    StreamProvider.autoDispose<List<UnparsedSms>>((ref) {
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
final templateTrustAlertsProvider =
    StreamProvider.autoDispose<List<TemplateTrustEntry>>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) => TemplateTrustLedger(database)
        .watch()
        .map((snapshot) => snapshot.flaggedEntries),
    loading: () => const Stream<List<TemplateTrustEntry>>.empty(),
    error: (error, stackTrace) =>
        Stream<List<TemplateTrustEntry>>.error(error, stackTrace),
  );
});

/// Groups unparsed raw SMS by sender and sorts them by frequency descending.
final unrecognizedSenderCountsProvider =
    Provider.autoDispose<AsyncValue<List<MapEntry<String, int>>>>((ref) {
  return ref.watch(unparsedSmsListProvider).whenData((unparsed) {
    final counts = <String, int>{};
    for (final item in unparsed) {
      final sender = item.sender.toUpperCase().trim();
      if (sender.isNotEmpty) {
        counts[sender] = (counts[sender] ?? 0) + 1;
      }
    }
    return counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
  });
});

enum UnparsedReason {
  otpAuth('OTP / Authentication'),
  balanceInfo('Balance / Statement info'),
  unmatchedFinancial('Unmatched financial SMS'),
  promo('Non-transactional / Promo');

  const UnparsedReason(this.label);
  final String label;
}

final _otpPattern = RegExp(
  r'\b(otp|secret code|verification code|one[- ]time)\b',
  caseSensitive: false,
);
final _balancePattern = RegExp(
  r'\b(avail(?:able)?\s*bal|a/c bal|balance is|statement|bill due|min(?:imum)? due)\b',
  caseSensitive: false,
);
final _financialPattern = RegExp(
  r'\b(debited|credited|spent|paid|received|transferred|withdrawn)\b',
  caseSensitive: false,
);
final _currencyPattern =
    RegExp(r'(?:\binr\b|\brs\.?\b|₹)', caseSensitive: false);

UnparsedReason categorizeUnparsedSms(String body) {
  if (_otpPattern.hasMatch(body)) return UnparsedReason.otpAuth;
  if (_balancePattern.hasMatch(body)) return UnparsedReason.balanceInfo;
  if (_financialPattern.hasMatch(body) || _currencyPattern.hasMatch(body)) {
    return UnparsedReason.unmatchedFinancial;
  }
  return UnparsedReason.promo;
}

/// Groups unparsed raw SMS by rejection reason and sorts by count descending.
final unparsedReasonCountsProvider =
    Provider.autoDispose<AsyncValue<List<MapEntry<UnparsedReason, int>>>>(
        (ref) {
  return ref.watch(unparsedSmsListProvider).whenData((unparsed) {
    final counts = <UnparsedReason, int>{};
    for (final item in unparsed) {
      final reason = categorizeUnparsedSms(item.body);
      counts[reason] = (counts[reason] ?? 0) + 1;
    }
    return counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.label.compareTo(b.key.label);
      });
  });
});
