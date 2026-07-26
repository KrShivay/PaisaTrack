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
import '../enrichment/merchant_resolver.dart';
import '../features/settings/app_settings.dart';
import '../intelligence/llm/llm_runtime.dart';
import 'captured_sms_source.dart';
import 'duplicate_suppressor.dart';
import 'llm_field_locator.dart';
import 'message_kind_classifier.dart';
import 'parser_cascade.dart';
import 'permissions/sms_permission.dart';
import 'permissions/sms_permission_provider.dart';
import 'span_verifier.dart';
import 'template_engine/template_matcher.dart';
import 'template_engine/template_registry.dart';
import 'template_engine/template_trust_ledger.dart';

/// Shared high-precision matcher used by live capture and bulk history import.
final templateMatcherProvider = FutureProvider<TemplateMatcher>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final registries = await Future.wait(
    const [
      'assets/templates/axisbk.json',
      'assets/templates/centbk.json',
      'assets/templates/hdfcbk.json',
      'assets/templates/icicib.json',
      'assets/templates/indusind.json',
      'assets/templates/kotak.json',
      'assets/templates/paytmb.json',
      'assets/templates/sbi.json',
    ].map((path) async {
      final source = await rootBundle.loadString(path);
      return TemplateRegistry.fromJson(source);
    }),
  );

  return TemplateMatcher(
    registries: registries,
    trustLedger: TemplateTrustLedger(database),
  );
});

/// Parser cascade used by live SMS ingestion.
final parserCascadeProvider = FutureProvider<ParserCascade>((ref) async {
  return ParserCascade(
    templateMatcher: await ref.watch(templateMatcherProvider.future),
    llmFieldLocator: LlmFieldLocator(ref.watch(llmRuntimeProvider)),
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
    merchantResolver: ref.watch(merchantResolverProvider(database)),
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

class SmsBatchIngestResult {
  const SmsBatchIngestResult({
    required this.succeededIds,
    required this.failed,
    this.createdTxnIds = const {},
    this.alreadyKnownIds = const {},
    this.failedIds = const {},
  });

  final Set<String> succeededIds;
  final Set<String> createdTxnIds;
  final Set<String> alreadyKnownIds;
  final Set<String> failedIds;
  final int failed;
}

/// Persists raw SMS rows and emits transactions when parsing succeeds.
class SmsIngestor {
  SmsIngestor({
    required AppDatabase database,
    required ParserCascade parser,
    Categorizer? categorizer,
    MerchantResolver? merchantResolver,
    int askDailyBudget = AppConstants.askNowDailyBudget,
    int Function()? askDailyBudgetResolver,
    DecisionStatus? fixedStatus,
    Set<String>? knownTransactionIds,
    DecisionPolicy decisionPolicy = const DecisionPolicy(),
    DuplicateSuppressor duplicateSuppressor = const DuplicateSuppressor(),
    DateTime Function()? now,
    MessageKindClassifier? messageKindClassifier,
  })  : _database = database,
        _parser = parser,
        _categorizer = categorizer,
        _merchantResolver = merchantResolver,
        _askDailyBudget = askDailyBudgetResolver ?? (() => askDailyBudget),
        _fixedStatus = fixedStatus,
        _knownTransactionIds = knownTransactionIds,
        _decisionPolicy = decisionPolicy,
        _duplicateSuppressor = duplicateSuppressor,
        _messageKindClassifier = messageKindClassifier,
        _now = now ?? DateTime.now;

  final AppDatabase _database;
  final ParserCascade _parser;

  /// Categorizer ladder (T-039). Nullable so capture-focused tests can run
  /// without one; production wiring always supplies it.
  final Categorizer? _categorizer;
  final MerchantResolver? _merchantResolver;

  /// Resolves the daily ask budget at decision time, so a Settings change
  /// applies to the next ingest without rebuilding the capture pipeline
  /// (see smsCaptureBootstrapProvider).
  final int Function() _askDailyBudget;
  final DecisionStatus? _fixedStatus;
  final Set<String>? _knownTransactionIds;
  final DecisionPolicy _decisionPolicy;
  final DuplicateSuppressor _duplicateSuppressor;
  final MessageKindClassifier? _messageKindClassifier;
  final DateTime Function() _now;

  /// Inserts the raw SMS, attempts parsing, and stores a transaction on success.
  Future<void> ingest(RawSms sms) async {
    final transactionId = 'txn_${sms.id}';
    if (_knownTransactionIds?.contains(transactionId) ?? false) return;
    await _database.transaction(() async {
      // Inbox re-import is intentionally non-destructive. A deterministic SMS
      // id maps to a deterministic transaction id, so an existing row may
      // contain user edits, confirmation state, or a user deletion that must
      // never be overwritten by a newer parser/categorizer result. Check this
      // before the raw upsert so re-import also does not resurrect bodies that
      // the retention job already purged.
      final existingTransaction = await (_database.select(
        _database.transactions,
      )..where((row) => row.id.equals(transactionId)))
          .getSingleOrNull();
      if (existingTransaction != null) return;

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

      final kind = _messageKindClassifier?.classify(sms.body) ?? MessageKind.settledDebit;

      if (kind == MessageKind.reminder || kind == MessageKind.mandate) {
        await _markRawSmsProcessed(sms.id, processed: true);
        return;
      }

      final (lifecycleState, lifecycleReason) = switch (kind) {
        MessageKind.settledDebit || MessageKind.settledCredit => ('settled', null),
        MessageKind.pendingAuth => ('pending', 'authorized'),
        MessageKind.failed => ('failed', 'declined'),
        MessageKind.reversal => ('reversed', 'refund_or_reversal'),
        _ => ('settled', null),
      };

      final parseResult = await _parser.parse(sms);
      switch (parseResult) {
        case Ok<NormalizedTransactionRecord, ParseFailure>(:final value):
          final duplicateOfTxnId = await _findDuplicateOfExisting(value);
          final merchant = await _merchantResolver?.resolve(value);
          final categorization = await _categorizer?.categorize(
            value,
            merchantEmbedding: merchant?.embedding,
          );
          final initialStatus = duplicateOfTxnId != null
              ? DecisionStatus.auto
              : _fixedStatus ??
                  (merchant?.needsReview == true
                      ? DecisionStatus.needsReview
                      : await _decideStatus(
                          value,
                          categorization: categorization,
                        ));
          final status = SpanVerifier.enforceWriteGuard(
            body: sms.body,
            record: value,
            requestedStatus: initialStatus,
          );
          await _database.into(_database.transactions).insertOnConflictUpdate(
                _transactionCompanionFor(
                  smsId: sms.id,
                  record: value,
                  duplicateOfTxnId: duplicateOfTxnId,
                  categorization: categorization,
                  merchant: merchant,
                  status: status,
                  messageKind: kind,
                  lifecycleState: lifecycleState,
                  lifecycleReason: lifecycleReason,
                ),
              );
          if (duplicateOfTxnId != null) {
            await _database.into(_database.transactionLinks).insertOnConflictUpdate(
                  TransactionLinksCompanion.insert(
                    id: 'link_${sms.id}_$duplicateOfTxnId',
                    fromTxnId: 'txn_${sms.id}',
                    toTxnId: duplicateOfTxnId,
                    linkType: 'echo',
                    basis: 'duplicate_suppressor',
                    createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
                  ),
                );
          }
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

  /// Imports one inbox page under a single outer transaction so Drift emits
  /// one coherent change notification instead of rebuilding consumers once
  /// per SMS. Nested per-message transactions preserve failure isolation.
  Future<SmsBatchIngestResult> ingestBatch(List<RawSms> messages) {
    return _database.transaction(() async {
      final succeededIds = <String>{};
      var failed = 0;
      for (final sms in messages) {
        try {
          await ingest(sms);
          succeededIds.add(sms.id);
        } catch (_) {
          failed++;
        }
      }
      return SmsBatchIngestResult(
        succeededIds: succeededIds,
        failed: failed,
      );
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
    final threshold = await AdaptiveThresholdPolicy(_database)
        .thresholdFor(categorization?.categoryId);
    return _decisionPolicy.decide(
      DecisionPolicyInput(
        merchantConfidence: record.parseConfidence,
        categoryConfidence: categorization?.confidence ?? 0,
        amount: record.amount,
        merchantTxnCount: await _countPriorMerchantTransactions(record),
        askBudgetLeft: askBudgetLeft > 0 ? askBudgetLeft : 0,
        counterpartyVpa: record.counterpartyVpa,
        counterpartySeen: await _hasSeenCounterparty(record.counterpartyVpa),
        silentThreshold: threshold,
      ),
    );
  }

  Future<int> _countAskedToday() async {
    final now = _now().toUtc();
    final start = DateTime.utc(now.year, now.month, now.day);
    final askedCount = _database.transactions.id.count();
    final askedQuery = _database.selectOnly(_database.transactions)
      ..addColumns([askedCount])
      ..where(
        _database.transactions.status.equals(DecisionStatus.asked.wireName) &
            _database.transactions.isDeleted.equals(false) &
            _database.transactions.duplicateOfTxnId.isNull() &
            _database.transactions.createdAt.isBiggerOrEqualValue(start),
      );
    final asked = (await askedQuery.getSingle()).read(askedCount) ?? 0;

    final answeredCount = _database.transactions.id.count(distinct: true);
    final answeredQuery = _database.selectOnly(_database.transactions).join([
      innerJoin(
        _database.feedback,
        _database.feedback.txnId.equalsExp(_database.transactions.id),
        useColumns: false,
      ),
    ])
      ..addColumns([answeredCount])
      ..where(
        _database.feedback.context.equals('ask_now') &
            _database.feedback.createdAt.isBiggerOrEqualValue(start) &
            _database.transactions.status
                .equals(DecisionStatus.asked.wireName)
                .not() &
            _database.transactions.isDeleted.equals(false) &
            _database.transactions.duplicateOfTxnId.isNull() &
            _database.transactions.createdAt.isBiggerOrEqualValue(start),
      );
    final answered = (await answeredQuery.getSingle()).read(answeredCount) ?? 0;
    return asked + answered;
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

    final count = _database.transactions.id.count();
    final query = _database.selectOnly(_database.transactions)
      ..addColumns([count])
      ..where(
        _database.transactions.isDeleted.equals(false) &
            _database.transactions.duplicateOfTxnId.isNull() &
            _sameKnownCounterparty(
              _database.transactions,
              merchantRaw: merchantRaw,
              counterpartyVpa: counterpartyVpa,
            ),
      );
    return (await query.getSingle()).read(count) ?? 0;
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
    required MessageKind messageKind,
    required String lifecycleState,
    String? lifecycleReason,
    CategorizationResult? categorization,
    MerchantResolution? merchant,
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
      merchantId: Value(merchant?.merchantId),
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
        'merchant': {
          'v': merchant?.canonicalName ??
              record.merchantRaw ??
              record.counterpartyVpa,
          'c': merchant?.confidence ?? record.parseConfidence,
          'src': merchant?.source ?? record.parseSource.wireName,
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
      evidenceJson: Value(
        record.evidence != null
            ? jsonEncode(record.evidence!.map((e) => e.toJson()).toList())
            : null,
      ),
      lifecycleState: Value(lifecycleState),
      lifecycleReason: Value(lifecycleReason),
      messageKind: Value(messageKind.wireName),
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
