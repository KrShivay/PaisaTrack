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
import '../data/repositories/rule_repository.dart';
import '../enrichment/categorizer.dart';
import '../enrichment/decision_policy.dart';
import '../features/settings/app_settings.dart';
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
  final categorizer = ref.watch(categorizerProvider).valueOrNull;
  if (parser == null || categorizer == null) {
    return;
  }
  final ingestor = SmsIngestor(
    database: database,
    parser: parser,
    categorizer: categorizer,
    // Deliberately ref.read (lazy, at decision time) — NOT ref.watch.
    // Watching the settings controller here rebuilt this provider on every
    // settings emission (including its initial loading→data transition),
    // cancelling and re-creating the SMS subscription: in-flight messages
    // were droppable on device and single-subscription test streams threw
    // "Stream has already been listened to". The resolver keeps the
    // subscription stable and still picks up ask-budget slider changes
    // immediately on the next ingest.
    askDailyBudgetResolver: () =>
        ref.read(appSettingsControllerProvider).valueOrNull?.askDailyBudget ??
        AppConstants.askNowDailyBudget,
  );
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
    Categorizer? categorizer,
    int askDailyBudget = AppConstants.askNowDailyBudget,
    int Function()? askDailyBudgetResolver,
    DecisionPolicy decisionPolicy = const DecisionPolicy(),
    DuplicateSuppressor duplicateSuppressor = const DuplicateSuppressor(),
    DateTime Function()? now,
  })  : _database = database,
        _parser = parser,
        _categorizer = categorizer,
        _askDailyBudget = askDailyBudgetResolver ?? (() => askDailyBudget),
        _decisionPolicy = decisionPolicy,
        _duplicateSuppressor = duplicateSuppressor,
        _now = now ?? DateTime.now;

  final AppDatabase _database;
  final ParserCascade _parser;

  /// Categorizer ladder (T-039). Nullable so capture-focused tests can run
  /// without one; production wiring always supplies it.
  final Categorizer? _categorizer;

  /// Resolves the daily ask budget at decision time, so a Settings change
  /// applies to the next ingest without rebuilding the capture pipeline
  /// (see smsCaptureBootstrapProvider).
  final int Function() _askDailyBudget;
  final DecisionPolicy _decisionPolicy;
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
          final categorization = await _categorizer?.categorize(value);
          // Suppressed echoes never surface to the user, so they must not
          // enter the ask flow or consume ask budget — keep them 'auto'.
          final status = duplicateOfTxnId != null
              ? DecisionStatus.auto
              : await _decideStatus(
                  value,
                  categorization: categorization,
                );
          await _database.into(_database.transactions).insertOnConflictUpdate(
                _transactionCompanionFor(
                  smsId: sms.id,
                  record: value,
                  duplicateOfTxnId: duplicateOfTxnId,
                  categorization: categorization,
                  status: status,
                ),
              );
          if (categorization?.ruleId != null) {
            await RuleRepository(_database)
                .incrementHitCount(categorization!.ruleId!);
          }
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

  Future<DecisionStatus> _decideStatus(
    NormalizedTransactionRecord record, {
    required CategorizationResult? categorization,
  }) async {
    final askedToday = await _countAskedToday();
    final askBudgetLeft = _askDailyBudget() - askedToday;
    return _decisionPolicy.decide(
      DecisionPolicyInput(
        merchantConfidence: record.parseConfidence,
        categoryConfidence: categorization?.confidence ?? 0,
        amount: record.amount,
        merchantTxnCount: await _countPriorMerchantTransactions(record),
        askBudgetLeft: askBudgetLeft > 0 ? askBudgetLeft : 0,
        counterpartyVpa: record.counterpartyVpa,
        counterpartySeen: await _hasSeenCounterparty(record.counterpartyVpa),
      ),
    );
  }

  Future<int> _countAskedToday() async {
    final now = _now().toUtc();
    final start = DateTime.utc(now.year, now.month, now.day);
    final askedRows = await (_database.select(_database.transactions)
          ..where(
            (row) =>
                row.status.equals(DecisionStatus.asked.wireName) &
                row.isDeleted.equals(false) &
                row.duplicateOfTxnId.isNull() &
                row.createdAt.isBiggerOrEqualValue(start),
          ))
        .get();
    final askedTxnIds = askedRows.map((row) => row.id).toSet();
    final answeredAskFeedback = await (_database.select(_database.feedback)
          ..where(
            (row) =>
                row.context.equals('ask_now') &
                row.createdAt.isBiggerOrEqualValue(start),
          ))
        .get();
    final answeredTxnIds = answeredAskFeedback
        .map((row) => row.txnId)
        .toSet()
        .difference(askedTxnIds);
    if (answeredTxnIds.isEmpty) {
      return askedTxnIds.length;
    }
    final answeredRows = await (_database.select(_database.transactions)
          ..where(
            (row) =>
                row.id.isIn(answeredTxnIds) &
                row.isDeleted.equals(false) &
                row.duplicateOfTxnId.isNull() &
                row.createdAt.isBiggerOrEqualValue(start),
          ))
        .get();
    return askedTxnIds.length + answeredRows.length;
  }

  Future<int> _countPriorMerchantTransactions(
    NormalizedTransactionRecord record,
  ) async {
    final merchantRaw = record.merchantRaw;
    final counterpartyVpa = record.counterpartyVpa;
    if ((merchantRaw == null || merchantRaw.isEmpty) &&
        (counterpartyVpa == null || counterpartyVpa.isEmpty)) {
      return 0;
    }

    final rows = await (_database.select(_database.transactions)
          ..where(
            (row) =>
                row.isDeleted.equals(false) &
                row.duplicateOfTxnId.isNull() &
                _sameKnownCounterparty(
                  row,
                  merchantRaw: merchantRaw,
                  counterpartyVpa: counterpartyVpa,
                ),
          ))
        .get();
    return rows.length;
  }

  Future<bool> _hasSeenCounterparty(String? counterpartyVpa) async {
    if (counterpartyVpa == null || counterpartyVpa.isEmpty) {
      return true;
    }
    final rows = await (_database.select(_database.transactions)
          ..where(
            (row) =>
                row.isDeleted.equals(false) &
                row.duplicateOfTxnId.isNull() &
                row.counterpartyVpa.equals(counterpartyVpa),
          )
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  Expression<bool> _sameKnownCounterparty(
    $TransactionsTable row, {
    required String? merchantRaw,
    required String? counterpartyVpa,
  }) {
    Expression<bool>? expression;
    if (merchantRaw != null && merchantRaw.isNotEmpty) {
      expression = row.merchantRaw.equals(merchantRaw);
    }
    if (counterpartyVpa != null && counterpartyVpa.isNotEmpty) {
      final vpaExpression = row.counterpartyVpa.equals(counterpartyVpa);
      expression =
          expression == null ? vpaExpression : expression | vpaExpression;
    }
    return expression ?? const Constant(false);
  }

  TransactionsCompanion _transactionCompanionFor({
    required String smsId,
    required NormalizedTransactionRecord record,
    required String? duplicateOfTxnId,
    required DecisionStatus status,
    CategorizationResult? categorization,
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
      categoryId: Value(categorization?.categoryId),
      parseSource: record.parseSource.wireName,
      smsId: Value(smsId),
      confidenceJson: jsonEncode({
        'parser': {
          'c': record.parseConfidence,
          'src': record.parseSource.wireName,
          if (record.templateId != null) 'template_id': record.templateId,
          if (record.templateProvenance != null)
            'provenance': record.templateProvenance,
        },
        if (categorization != null)
          'category': {
            'c': categorization.confidence,
            'src': categorization.source,
            if (categorization.ruleId != null) 'rule_id': categorization.ruleId,
          },
      }),
      status: status.wireName,
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
