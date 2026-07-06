import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/result.dart';
import '../data/db/database.dart';
import '../data/db/database_provider.dart';
import '../data/models/normalized_transaction_record.dart';
import '../data/models/raw_sms.dart';
import 'captured_sms_source.dart';
import 'duplicate_suppressor.dart';
import 'parser_cascade.dart';
import 'permissions/sms_permission.dart';
import 'permissions/sms_permission_provider.dart';
import 'template_engine/template_matcher.dart';
import 'template_engine/template_registry.dart';

/// Parser cascade used by live SMS ingestion.
final parserCascadeProvider = FutureProvider<ParserCascade>((ref) async {
  final registries = await Future.wait(
    const [
      'assets/templates/axisbk.json',
      'assets/templates/indusind.json',
      'assets/templates/paytmb.json',
      'assets/templates/sbi.json',
    ].map((path) async {
      final source = await rootBundle.loadString(path);
      return TemplateRegistry.fromJson(source);
    }),
  );

  return ParserCascade(
    templateMatcher: TemplateMatcher(registries: registries),
  );
});

/// Coordinates live Android SMS events into raw capture rows and transactions.
final smsCaptureBootstrapProvider = Provider<void>((ref) {
  final permission = ref.watch(smsPermissionControllerProvider);
  final database = ref.watch(appDatabaseProvider).valueOrNull;
  if (permission.valueOrNull != SmsPermissionStatus.granted ||
      database == null) {
    return;
  }

  final source = ref.watch(capturedSmsSourceProvider);
  final parser = ref.watch(parserCascadeProvider).valueOrNull;
  if (parser == null) {
    return;
  }
  final ingestor = SmsIngestor(database: database, parser: parser);
  final subscription = source.messages().listen(
    (sms) => unawaited(_ingestSafely(ingestor, sms)),
    onError: (Object error, StackTrace stackTrace) {
      // Keep capture alive even if one native payload is malformed.
    },
  );
  ref.onDispose(subscription.cancel);
});

/// Runs a single ingest, absorbing failures so one bad write cannot become an
/// unhandled zone error or tear down the capture stream. The message stays
/// uncaptured and is recovered later by inbox backfill (T-023).
Future<void> _ingestSafely(SmsIngestor ingestor, RawSms sms) async {
  try {
    await ingestor.ingest(sms);
  } catch (_) {
    // Intentionally swallowed: no raw SMS content is logged on this path.
  }
}

/// Persists raw SMS rows and emits transactions when parsing succeeds.
class SmsIngestor {
  SmsIngestor({
    required AppDatabase database,
    required ParserCascade parser,
    DuplicateSuppressor duplicateSuppressor = const DuplicateSuppressor(),
    DateTime Function()? now,
  })  : _database = database,
        _parser = parser,
        _duplicateSuppressor = duplicateSuppressor,
        _now = now ?? DateTime.now;

  final AppDatabase _database;
  final ParserCascade _parser;
  final DuplicateSuppressor _duplicateSuppressor;
  final DateTime Function() _now;

  /// Inserts the raw SMS, attempts parsing, and stores a transaction on success.
  Future<void> ingest(RawSms sms) async {
    await _database.transaction(() async {
      await _database.into(_database.rawSms).insertOnConflictUpdate(
            RawSmsCompanion.insert(
              id: sms.id,
              sender: sms.sender,
              body: sms.body,
              receivedAt: sms.receivedAt,
              purgeAfter: sms.receivedAt.add(
                const Duration(days: AppConstants.rawSmsRetentionDays),
              ),
            ),
          );

      final parseResult = await _parser.parse(sms);
      switch (parseResult) {
        case Ok<NormalizedTransactionRecord, ParseFailure>(:final value):
          final duplicateOfTxnId = await _findDuplicateOfExisting(value);
          await _database.into(_database.transactions).insertOnConflictUpdate(
                _transactionCompanionFor(
                  smsId: sms.id,
                  record: value,
                  duplicateOfTxnId: duplicateOfTxnId,
                ),
              );
          await _markRawSmsProcessed(sms.id, processed: true);
        case Err<NormalizedTransactionRecord, ParseFailure>():
          await _markRawSmsProcessed(sms.id, processed: false);
      }
    });
  }

  /// Id of an already-stored transaction describing the same real-world
  /// payment as [record] (e.g. a bank SMS and its wallet/UPI echo, T-025),
  /// or null if none is found. Suppressed/deleted rows are never candidates.
  Future<String?> _findDuplicateOfExisting(
    NormalizedTransactionRecord record,
  ) async {
    final window = _duplicateSuppressor.window;
    final windowStart = record.ts.toUtc().subtract(window);
    final windowEnd = record.ts.toUtc().add(window);
    final candidates = await (_database.select(_database.transactions)
          ..where(
            (row) =>
                row.direction.equals(record.direction.wireName) &
                row.isDeleted.equals(false) &
                row.duplicateOfTxnId.isNull() &
                row.ts.isBiggerOrEqualValue(
                  windowStart.millisecondsSinceEpoch,
                ) &
                row.ts.isSmallerOrEqualValue(
                  windowEnd.millisecondsSinceEpoch,
                ),
          ))
        .get();
    for (final existing in candidates) {
      if (_duplicateSuppressor.isDuplicate(record, existing)) {
        return existing.id;
      }
    }
    return null;
  }

  TransactionsCompanion _transactionCompanionFor({
    required String smsId,
    required NormalizedTransactionRecord record,
    required String? duplicateOfTxnId,
  }) {
    final timestamp = _now().toUtc();
    return TransactionsCompanion.insert(
      id: 'txn_$smsId',
      ts: record.ts.toUtc().millisecondsSinceEpoch,
      amount: record.amount,
      direction: record.direction.wireName,
      channel: record.channel.wireName,
      accountHint: Value(record.accountHint),
      merchantRaw: Value(record.merchantRaw),
      counterpartyVpa: Value(record.counterpartyVpa),
      balanceAfter: Value(record.balanceAfter),
      refId: Value(record.refId),
      parseSource: record.parseSource.wireName,
      smsId: Value(smsId),
      confidenceJson: jsonEncode({
        'parser': {
          'c': record.parseConfidence,
          'src': record.parseSource.wireName,
        },
      }),
      status: 'auto',
      duplicateOfTxnId: Value(duplicateOfTxnId),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  Future<void> _markRawSmsProcessed(
    String smsId, {
    required bool processed,
  }) {
    return (_database.update(_database.rawSms)
          ..where((row) => row.id.equals(smsId)))
        .write(RawSmsCompanion(processed: Value(processed)));
  }
}
