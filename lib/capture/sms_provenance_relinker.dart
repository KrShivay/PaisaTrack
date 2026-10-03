import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/confidence_payload.dart';
import '../data/db/database.dart';
import '../data/db/database_provider.dart';
import '../data/models/raw_sms.dart';
import '../data/repositories/feature_flag_repository.dart';
import '../features/settings/app_settings.dart';
import 'sms_backfill.dart';

/// Outcome counts of one provenance re-link run. Contains no message content.
class SmsProvenanceRelinkResult {
  const SmsProvenanceRelinkResult({
    this.relinked = 0,
    this.skippedAmbiguous = 0,
    this.notFound = 0,
  });

  /// Transactions whose source SMS was restored and linked again.
  final int relinked;

  /// Inbox matches that could not be verified exactly and were left alone.
  final int skippedAmbiguous;

  /// Transactions whose source SMS is no longer in the inbox (or is from a
  /// sender the user paused).
  final int notFound;
}

/// Restores source-SMS provenance removed by the pre-ADR-0021 purge.
///
/// Reads the inbox through the history-import [SmsInboxReader] (no new
/// permission). A message is linked only on an exact deterministic match:
/// the transaction id is `txn_<provider id>`, it has no source yet, the
/// provider id appears once, no other transaction claims it, and every stored
/// evidence span equals the same characters of the message body. Never
/// creates transactions and never changes amounts, categories, or any other
/// transaction field. Paused senders and paused capture are respected.
class SmsProvenanceRelinker {
  SmsProvenanceRelinker({
    required AppDatabase database,
    required SmsInboxReader reader,
    int pageSize = AppConstants.smsHistoryImportPageSize,
    bool Function()? isCapturePaused,
    bool Function(String sender)? isSenderPaused,
  })  : _database = database,
        _reader = reader,
        _pageSize = pageSize,
        _isCapturePaused = isCapturePaused,
        _isSenderPaused = isSenderPaused;

  final AppDatabase _database;
  final SmsInboxReader _reader;
  final int _pageSize;
  final bool Function()? _isCapturePaused;
  final bool Function(String sender)? _isSenderPaused;
  Future<SmsProvenanceRelinkResult>? _active;

  static const _transactionIdPrefix = 'txn_';
  static const _smsParseSources = {'template', 'generic', 'local_llm'};

  /// Runs once at a time; a second call joins the active run.
  Future<SmsProvenanceRelinkResult> run() =>
      _active ??= _run().whenComplete(() => _active = null);

  Future<SmsProvenanceRelinkResult> _run() async {
    if (_isCapturePaused?.call() == true) {
      return const SmsProvenanceRelinkResult();
    }
    final candidates = await _unlinkedSmsTransactions();
    if (candidates.isEmpty) return const SmsProvenanceRelinkResult();

    final seen = <String, RawSms?>{};
    await for (final page in readInboxPages(_reader, pageSize: _pageSize)) {
      for (final sms in page.messages) {
        if (!candidates.containsKey(sms.id)) continue;
        if (_isSenderPaused?.call(sms.sender) == true) continue;
        // A repeated provider id is ambiguous; null marks it.
        seen[sms.id] = seen.containsKey(sms.id) ? null : sms;
      }
      await Future<void>.delayed(Duration.zero);
    }

    var relinked = 0;
    var skipped = 0;
    for (final MapEntry(key: smsId, value: sms) in seen.entries) {
      final transaction = candidates[smsId]!;
      if (sms != null &&
          _evidenceMatches(transaction, sms.body) &&
          await _link(transaction, sms)) {
        relinked++;
      } else {
        skipped++;
      }
    }
    return SmsProvenanceRelinkResult(
      relinked: relinked,
      skippedAmbiguous: skipped,
      notFound: candidates.length - seen.length,
    );
  }

  /// SMS-derived, non-deleted transactions with no source SMS, by provider id.
  Future<Map<String, Transaction>> _unlinkedSmsTransactions() async {
    final rows = await (_database.select(_database.transactions)
          ..where(
            (row) =>
                row.smsId.isNull() &
                row.isDeleted.equals(false) &
                row.parseSource.isIn(_smsParseSources),
          ))
        .get();
    return {
      for (final row in rows)
        if (row.id.startsWith(_transactionIdPrefix))
          row.id.substring(_transactionIdPrefix.length): row,
    };
  }

  bool _evidenceMatches(Transaction transaction, String body) {
    final evidence = parseEvidenceFromJson(transaction.evidenceJson);
    if (evidence == null || !evidence.any((item) => item.field == 'amount')) {
      return false;
    }
    return evidence.every(
      (item) =>
          item.start >= 0 &&
          item.end > item.start &&
          item.end <= body.length &&
          body.substring(item.start, item.end) == item.verbatim,
    );
  }

  /// Restores the raw row and links it atomically; false leaves no trace.
  Future<bool> _link(Transaction transaction, RawSms sms) async {
    try {
      await _database.transaction(() async {
        final existing = await (_database.select(_database.rawSms)
              ..where((row) => row.id.equals(sms.id)))
            .getSingleOrNull();
        if (existing != null && existing.body != sms.body) {
          throw const _RelinkConflict();
        }
        final claimed = await (_database.select(_database.transactions)
              ..where((row) => row.smsId.equals(sms.id))
              ..limit(1))
            .getSingleOrNull();
        if (claimed != null) throw const _RelinkConflict();
        if (existing == null) {
          await _database.into(_database.rawSms).insert(
                RawSmsCompanion.insert(
                  id: sms.id,
                  sender: sms.sender,
                  body: sms.body,
                  receivedAt: sms.receivedAt,
                  processed: const Value(true),
                  // Linked rows are never purged; the deadline only matters
                  // if the transaction link is later removed.
                  purgeAfter: sms.receivedAt.add(
                    const Duration(days: AppConstants.rawSmsRetentionDays),
                  ),
                ),
              );
        }
        final changed = await (_database.update(_database.transactions)
              ..where(
                (row) => row.id.equals(transaction.id) & row.smsId.isNull(),
              ))
            .write(TransactionsCompanion(smsId: Value(sms.id)));
        if (changed != 1) throw const _RelinkConflict();
      });
      return true;
    } on _RelinkConflict {
      return false;
    }
  }
}

class _RelinkConflict implements Exception {
  const _RelinkConflict();
}

/// Kept alive so concurrent taps join the same run.
final smsProvenanceRelinkerProvider =
    FutureProvider<SmsProvenanceRelinker>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final flags = await FeatureFlagRepository(database).getFlags();
  return SmsProvenanceRelinker(
    database: database,
    reader: ref.watch(smsInboxReaderProvider),
    pageSize: flags.smsHistoryImportPageSize,
    isCapturePaused: () =>
        ref.read(appSettingsControllerProvider).valueOrNull?.isCapturePaused ??
        false,
    isSenderPaused: (sender) {
      final paused =
          ref.read(appSettingsControllerProvider).valueOrNull?.pausedSenders ??
              const <String>[];
      return paused.contains(sender.trim().toUpperCase());
    },
  );
});
