import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/financial_calendar.dart';
import '../core/result.dart';
import '../data/db/database.dart';
import '../data/models/source_currency.dart';
import '../data/db/database_provider.dart';
import '../data/models/normalized_transaction_record.dart';
import '../data/models/raw_sms.dart';
import '../data/repositories/payee_evidence_repository.dart';
import '../data/repositories/expected_event_repository.dart';
import '../data/repositories/feature_flag_repository.dart';
import '../data/repositories/rule_repository.dart';
import '../enrichment/categorizer.dart';
import '../enrichment/decision_policy.dart';
import '../enrichment/merchant_resolver.dart';
import '../features/settings/app_settings.dart';
import '../intelligence/llm/llm_runtime.dart';
import 'capture_decision_provenance.dart';
import 'captured_sms_source.dart';
import 'duplicate_suppressor.dart';
import 'llm_field_locator.dart';
import 'message_kind_classifier.dart';
import 'parser_cascade.dart';
import 'parser_version.dart';
import 'permissions/sms_permission.dart';
import 'permissions/sms_permission_provider.dart';
import 'span_verifier.dart';
import 'template_engine/field_normalizer.dart';
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
      'assets/templates/pnb.json',
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
  final templateMatcher = await ref.watch(templateMatcherProvider.future);
  return ParserCascade(
    templateMatcher: templateMatcher,
    llmFieldLocator: LlmFieldLocator(ref.watch(llmRuntimeProvider)),
  );
});

/// Loads the deterministic lifecycle cues once for every ingestion path.
final messageKindClassifierProvider =
    FutureProvider<MessageKindClassifier>((ref) async {
  final cueJson =
      await rootBundle.loadString('assets/seed/message_cues_in.json');
  return MessageKindClassifier.fromJson(cueJson);
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
  final messageKindClassifier =
      ref.watch(messageKindClassifierProvider).valueOrNull;
  if (parser == null || categorizer == null || messageKindClassifier == null) {
    return;
  }
  final ingestor = SmsIngestor(
    database: database,
    parser: parser,
    categorizer: categorizer,
    messageKindClassifier: messageKindClassifier,
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
    isCapturePausedResolver: () =>
        ref.read(appSettingsControllerProvider).valueOrNull?.isCapturePaused ??
        false,
    isSenderPausedResolver: (sender) {
      final paused =
          ref.read(appSettingsControllerProvider).valueOrNull?.pausedSenders ??
              [];
      return paused.contains(sender.trim().toUpperCase());
    },
    financialCalendar: ref.watch(financialCalendarProvider),
  );
  final subscription = source.messages().listen(
    (sms) => unawaited(_ingestSafely(ingestor, sms)),
    onError: (Object error, StackTrace stackTrace) {
      // Keep capture alive even if one native payload is malformed.
    },
  );
  unawaited(_reconcileExpectedEventsSafely(ingestor));
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

Future<void> _reconcileExpectedEventsSafely(SmsIngestor ingestor) async {
  try {
    await ingestor.reconcileExpectedEvents();
  } catch (_) {
    // Keep capture alive; a later ingest or app start retries reconciliation.
  }
}

class SmsBatchIngestResult {
  const SmsBatchIngestResult({
    required this.succeededIds,
    required this.failed,
    this.createdTxnIds = const {},
    this.alreadyKnownIds = const {},
    this.parsedIds = const {},
    this.unparsedIds = const {},
    this.failedIds = const {},
  });

  final Set<String> succeededIds;
  final Set<String> createdTxnIds;
  final Set<String> alreadyKnownIds;
  final Set<String> parsedIds;
  final Set<String> unparsedIds;
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
    bool Function()? isCapturePausedResolver,
    bool Function(String sender)? isSenderPausedResolver,
    DecisionStatus? fixedStatus,
    CaptureDecisionStatusMode captureDecisionStatusMode =
        CaptureDecisionStatusMode.policy,
    Set<String>? knownTransactionIds,
    DecisionPolicy decisionPolicy = const DecisionPolicy(),
    DuplicateSuppressor duplicateSuppressor = const DuplicateSuppressor(),
    DateTime Function()? now,
    MessageKindClassifier? messageKindClassifier,
    ExpectedEventRepository? expectedEventRepository,
    FinancialCalendar? financialCalendar,
    int parserVersion = smsParserVersion,
  })  : _database = database,
        _captureDecisionStatusMode = captureDecisionStatusMode,
        _parser = parser,
        _categorizer = categorizer,
        _merchantResolver = merchantResolver,
        _askDailyBudget = askDailyBudgetResolver ?? (() => askDailyBudget),
        _isCapturePaused = isCapturePausedResolver,
        _isSenderPaused = isSenderPausedResolver,
        _fixedStatus = fixedStatus,
        _knownTransactionIds = knownTransactionIds,
        _decisionPolicy = decisionPolicy,
        _duplicateSuppressor = duplicateSuppressor,
        _messageKindClassifier = messageKindClassifier,
        _expectedEventRepository =
            expectedEventRepository ?? ExpectedEventRepository(database),
        _financialCalendar = financialCalendar ?? FinancialCalendar(),
        _parserVersion = parserVersion,
        _now = now ?? DateTime.now {
    if ((captureDecisionStatusMode == CaptureDecisionStatusMode.policy &&
            fixedStatus != null) ||
        (captureDecisionStatusMode == CaptureDecisionStatusMode.fixedReview &&
            fixedStatus != DecisionStatus.needsReview)) {
      throw ArgumentError(
        'Capture decision status mode does not match override',
      );
    }
  }

  final AppDatabase _database;
  final ParserCascade _parser;
  final Categorizer? _categorizer;
  final MerchantResolver? _merchantResolver;
  final int Function() _askDailyBudget;
  final bool Function()? _isCapturePaused;
  final bool Function(String sender)? _isSenderPaused;
  final DecisionStatus? _fixedStatus;
  final CaptureDecisionStatusMode _captureDecisionStatusMode;
  final Set<String>? _knownTransactionIds;
  final DecisionPolicy _decisionPolicy;
  final DuplicateSuppressor _duplicateSuppressor;
  final MessageKindClassifier? _messageKindClassifier;
  final ExpectedEventRepository _expectedEventRepository;
  final FinancialCalendar _financialCalendar;
  final int _parserVersion;
  final DateTime Function() _now;

  int get parserVersion => _parserVersion;

  /// Reconciles stored expectations on startup and after each persisted SMS.
  Future<void> reconcileExpectedEvents() {
    final localToday = _financialCalendar.localDate(_now());
    return _expectedEventRepository.reconcileExpectedEvents(
      today: DateTime.utc(localToday.year, localToday.month, localToday.day),
    );
  }

  /// Inserts the raw SMS, attempts parsing, and stores a transaction on success.
  Future<void> ingest(
    RawSms sms, {
    MerchantResolutionRun? merchantResolutionRun,
  }) async {
    if (_isCapturePaused?.call() == true) return;
    if (_isSenderPaused?.call(sms.sender) == true) return;
    final flagsRepo = FeatureFlagRepository(_database);
    final flagsState = await flagsRepo.getFlags();
    final stagedMerchantRun = merchantResolutionRun?.stage();
    var persistedSms = sms;

    try {
      await _database.transaction(() async {
        final claims = await _resolveIdentityClaims(sms);
        if (claims.alreadyKnown) return;
        final knownIds = sms.identityIds
            .where((id) => _knownTransactionIds?.contains('txn_$id') ?? false)
            .toSet();
        if (knownIds.length > 1) throw const _SmsIdentityConflict();
        if (knownIds.isNotEmpty) return;
        persistedSms = RawSms(
          id: claims.raw?.id ?? sms.id,
          sender: sms.sender,
          body: sms.body,
          receivedAt: claims.raw?.receivedAt ?? sms.receivedAt,
          legacyId: sms.legacyId,
        );
        final transactionId = 'txn_${persistedSms.id}';
        await _database.into(_database.rawSms).insertOnConflictUpdate(
              RawSmsCompanion.insert(
                id: persistedSms.id,
                sender: persistedSms.sender,
                body: persistedSms.body,
                receivedAt: persistedSms.receivedAt,
                parserVersion: Value(_parserVersion),
                failureReason: const Value<String?>(null),
                purgeAfter: persistedSms.receivedAt.add(
                  const Duration(days: AppConstants.rawSmsRetentionDays),
                ),
              ),
            );

        final kind = _messageKindClassifier?.classify(persistedSms.body) ??
            MessageKind.unknown;

        if (kind == MessageKind.reminder || kind == MessageKind.mandate) {
          final parseResult = await _parser.parse(
            persistedSms,
            calendar: _financialCalendar,
          );
          int amountPaise = 0;
          int? amountLowPaise;
          int? amountHighPaise;
          SourceCurrency? eventCurrency;
          String label = persistedSms.sender;
          String? counterpartyId;

          if (parseResult is Ok<NormalizedTransactionRecord, ParseFailure>) {
            amountPaise = (parseResult.value.amount * 100).round();
            label = parseResult.value.merchantRaw ?? persistedSms.sender;
            counterpartyId = parseResult.value.counterpartyVpa;
            eventCurrency = SourceCurrency(
              code: parseResult.value.currencyCode,
              symbol: parseResult.value.currencySymbol,
            );
          } else {
            const amountNumber =
                r'(?:\d{1,2}(?:,\d{2})*,\d{3}|\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?';
            final amtMatch = RegExp(
              r'(Rs\.?|INR|₹|USD|US\$|\$)\s*(' + amountNumber + r')(?![\d,])',
              caseSensitive: false,
            ).firstMatch(persistedSms.body);
            if (amtMatch != null) {
              eventCurrency = SourceCurrency.fromToken(amtMatch.group(1));
              amountPaise = _fallbackAmountPaise(amtMatch.group(2)!) ?? 0;
            }
            final rangeMatch = RegExp(
              '(?:^|[^\\d,.])($amountNumber)\\s*to\\s*($amountNumber)(?![\\d,])',
              caseSensitive: false,
            ).firstMatch(persistedSms.body);
            if (rangeMatch != null) {
              amountLowPaise = _fallbackAmountPaise(rangeMatch.group(1)!);
              amountHighPaise = _fallbackAmountPaise(rangeMatch.group(2)!);
            }
          }

          await _expectedEventRepository.recordExpectedEvent(
            source: 'sms_${kind.name}',
            originSmsId: persistedSms.id,
            counterpartyId: counterpartyId,
            label: label,
            expectedAmountPaise: amountPaise,
            currencyCode: eventCurrency?.code,
            currencySymbol: eventCurrency?.symbol,
            amountLowPaise: amountLowPaise,
            amountHighPaise: amountHighPaise,
            expectedDate: _reminderExpectedDate(
              persistedSms.body,
              persistedSms.receivedAt,
            ),
            confidence: 0.95,
          );

          await _markRawSmsOutcome(
            persistedSms.id,
            processed: true,
            failureReason: null,
          );
          await reconcileExpectedEvents();
          return;
        }

        if (kind == MessageKind.otp ||
            kind == MessageKind.promo ||
            kind == MessageKind.balance ||
            kind == MessageKind.statement ||
            kind == MessageKind.unknown) {
          await _markRawSmsOutcome(
            persistedSms.id,
            processed: kind != MessageKind.unknown,
            failureReason:
                kind == MessageKind.unknown ? SmsFailureReason.unparsed : null,
          );
          return;
        }

        final (lifecycleState, lifecycleReason) = switch (kind) {
          MessageKind.settledDebit || MessageKind.settledCredit => (
              'settled',
              null
            ),
          MessageKind.pendingAuth => ('pending', 'authorized'),
          MessageKind.failed => ('failed', 'declined'),
          MessageKind.reversal => ('reversed', 'refund_or_reversal'),
          MessageKind.reminder ||
          MessageKind.mandate ||
          MessageKind.balance ||
          MessageKind.statement ||
          MessageKind.promo ||
          MessageKind.otp ||
          MessageKind.unknown =>
            throw StateError(
              'Non-transactional kind reached transaction route',
            ),
        };

        final parseResult = await _parser.parse(
          persistedSms,
          calendar: _financialCalendar,
        );
        switch (parseResult) {
          case Ok<NormalizedTransactionRecord, ParseFailure>(:final value):
            final directionCue =
                _messageKindClassifier?.settledDirectionCue(persistedSms.body);
            final requiredDirection = switch (directionCue) {
              MessageKind.settledDebit => TransactionDirection.debit,
              MessageKind.settledCredit => TransactionDirection.credit,
              _ => null,
            };
            if (requiredDirection != null &&
                value.direction != requiredDirection) {
              await _markRawSmsOutcome(
                persistedSms.id,
                processed: false,
                failureReason: SmsFailureReason.unparsed,
              );
              return;
            }

            final duplicateOfTxnId = await _findDuplicateOfExisting(
              value,
              lifecycleState: lifecycleState,
            );
            final merchant = await _merchantResolver?.resolve(
              value,
              run: stagedMerchantRun,
              allowSuggestions: duplicateOfTxnId == null &&
                  _captureDecisionStatusMode ==
                      CaptureDecisionStatusMode.policy,
            );
            final categorization = await _categorizer?.categorize(
              value,
              merchantId: merchant?.merchantId,
              merchantEmbedding: merchant?.embedding,
            );
            final decidedStatus = lifecycleState != 'settled'
                ? DecisionStatus.needsReview
                : duplicateOfTxnId != null
                    ? DecisionStatus.auto
                    : merchant?.needsReview == true
                        ? DecisionStatus.needsReview
                        : categorization?.ruleId != null
                            ? await _decideStatus(
                                value,
                                categorization: categorization,
                              )
                            : _fixedStatus ??
                                await _decideStatus(
                                  value,
                                  categorization: categorization,
                                );
            final initialStatus = _captureDecisionStatusMode ==
                        CaptureDecisionStatusMode.fixedReview &&
                    decidedStatus == DecisionStatus.asked
                ? DecisionStatus.needsReview
                : decidedStatus;
            final status = SpanVerifier.enforceWriteGuard(
              body: persistedSms.body,
              record: value,
              requestedStatus: initialStatus,
            );
            await _database.into(_database.transactions).insertOnConflictUpdate(
                  _transactionCompanionFor(
                    smsId: persistedSms.id,
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
            await PayeeEvidenceRepository(_database).replaceForTransaction(
              transactionId: transactionId,
              merchantRaw: value.merchantRaw,
              counterpartyVpa: value.counterpartyVpa,
            );
            if (duplicateOfTxnId != null) {
              await _database
                  .into(_database.transactionLinks)
                  .insertOnConflictUpdate(
                    TransactionLinksCompanion.insert(
                      id: 'link_${persistedSms.id}_$duplicateOfTxnId',
                      fromTxnId: 'txn_${persistedSms.id}',
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
            await _markRawSmsOutcome(
              persistedSms.id,
              processed: true,
              failureReason: null,
            );
          case Err<NormalizedTransactionRecord, ParseFailure>():
            await _markRawSmsOutcome(
              persistedSms.id,
              processed: false,
              failureReason: SmsFailureReason.unparsed,
            );
        }
        await reconcileExpectedEvents();
      });
      if (stagedMerchantRun != null) {
        merchantResolutionRun!.commit(stagedMerchantRun);
      }
    } catch (error) {
      if (error is _SmsIdentityConflict) rethrow;
      await _recordProcessingFailure(persistedSms, flagsState);
      rethrow;
    }
  }

  Future<SmsIdentityClaims> _resolveIdentityClaims(RawSms sms) async {
    final ids = sms.identityIds.toList(growable: false);
    final transactionIds = ids.map((id) => 'txn_$id').toList(growable: false);
    final rawRows = await (_database.select(_database.rawSms)
          ..where((row) => row.id.isIn(ids)))
        .get();
    final transactionRows = await (_database.select(_database.transactions)
          ..where(
            (row) => row.smsId.isIn(ids) | row.id.isIn(transactionIds),
          ))
        .get();
    final dispositions = await (_database.select(_database.smsDispositions)
          ..where((row) => row.smsId.isIn(ids)))
        .get();
    final claims = validateSmsIdentityClaims(
      sms,
      rawRows: rawRows,
      transactionRows: transactionRows,
      dispositions: dispositions,
      parserVersion: _parserVersion,
    );
    if (claims.conflict) throw const _SmsIdentityConflict();
    return claims;
  }

  /// Imports one inbox page under a single outer transaction so Drift emits
  /// one coherent change notification instead of rebuilding consumers once
  /// per SMS. Nested per-message transactions preserve failure isolation.
  Future<SmsBatchIngestResult> ingestBatch(
    List<RawSms> messages, {
    MerchantResolutionRun? merchantResolutionRun,
    Set<String> additionalIdentityConflictIds = const {},
    Set<String>? failedIdsAlreadyAttemptedThisRun,
  }) async {
    final result = await _database.transaction(() async {
      final succeededIds = <String>{};
      final createdTxnIds = <String>{};
      final alreadyKnownIds = <String>{};
      final parsedIds = <String>{};
      final unparsedIds = <String>{};
      final failedIds = <String>{};
      final attemptedSmsIds = <String>{};
      final identityCollisionIds = {
        ...smsIdentityCollisionIds(messages),
        ...additionalIdentityConflictIds,
      };
      final identityIds = messages
          .expand((sms) => sms.identityIds)
          .toSet()
          .toList(growable: false);
      final messageIdsByIdentity = <String, Set<String>>{};
      for (final sms in messages) {
        for (final id in sms.identityIds) {
          messageIdsByIdentity.putIfAbsent(id, () => <String>{}).add(sms.id);
        }
      }
      final transactionIds = identityIds.map((id) => 'txn_$id').toList();
      final priorTransactionIds = <String>{};
      final rawRowsById = <String, RawSm>{};
      final transactionRowsByIdentity = <String, Set<Transaction>>{};
      final dispositionsByIdentity = <String, List<SmsDisposition>>{};
      for (var offset = 0; offset < identityIds.length; offset += 400) {
        final ids = identityIds.skip(offset).take(400).toList();
        final txnIds = transactionIds.skip(offset).take(400).toList();
        final transactions = await (_database.select(_database.transactions)
              ..where((row) => row.smsId.isIn(ids) | row.id.isIn(txnIds)))
            .get();
        for (final transaction in transactions) {
          priorTransactionIds.add(transaction.id);
          for (final id in ids) {
            if (transaction.smsId == id || transaction.id == 'txn_$id') {
              transactionRowsByIdentity
                  .putIfAbsent(id, () => <Transaction>{})
                  .add(transaction);
            }
          }
        }
        final dispositions = await (_database.select(_database.smsDispositions)
              ..where((row) => row.smsId.isIn(ids)))
            .get();
        for (final disposition in dispositions) {
          dispositionsByIdentity
              .putIfAbsent(disposition.smsId, () => <SmsDisposition>[])
              .add(disposition);
        }
        final rawRows = await (_database.select(_database.rawSms)
              ..where((row) => row.id.isIn(ids)))
            .get();
        for (final row in rawRows) {
          rawRowsById[row.id] = row;
        }
      }
      var failed = 0;
      for (final sms in messages) {
        try {
          if (identityCollisionIds.contains(sms.id)) {
            throw const _SmsIdentityConflict();
          }
          final ids = sms.identityIds;
          final claims = validateSmsIdentityClaims(
            sms,
            rawRows:
                ids.map((id) => rawRowsById[id]).whereType<RawSm>().toList(),
            transactionRows: ids
                .expand(
                  (id) =>
                      transactionRowsByIdentity[id] ?? const <Transaction>{},
                )
                .toList(),
            dispositions: ids
                .expand(
                  (id) =>
                      dispositionsByIdentity[id] ?? const <SmsDisposition>[],
                )
                .toList(),
            parserVersion: _parserVersion,
          );
          if (claims.conflict) throw const _SmsIdentityConflict();
          if (claims.alreadyKnown) {
            succeededIds.add(sms.id);
            alreadyKnownIds.add(sms.id);
            continue;
          }
          if (failedIdsAlreadyAttemptedThisRun?.contains(sms.id) == true) {
            failedIds.add(sms.id);
            continue;
          }
          if (!attemptedSmsIds.add(sms.id)) {
            if (failedIds.contains(sms.id)) continue;
            succeededIds.add(sms.id);
            alreadyKnownIds.add(sms.id);
            continue;
          }
          await ingest(sms, merchantResolutionRun: merchantResolutionRun);
          succeededIds.add(sms.id);
        } catch (_) {
          final newBatchFailure = failedIds.add(sms.id);
          final newRunFailure =
              failedIdsAlreadyAttemptedThisRun?.add(sms.id) ?? true;
          if (newBatchFailure && newRunFailure) failed++;
        }
      }
      for (var offset = 0; offset < identityIds.length; offset += 400) {
        final ids = identityIds.skip(offset).take(400).toList();
        final txnIds = transactionIds.skip(offset).take(400).toList();
        final transactionId = _database.transactions.id;
        final smsId = _database.transactions.smsId;
        final rows = await (_database.selectOnly(_database.transactions)
              ..addColumns([transactionId, smsId])
              ..where(smsId.isIn(ids) | transactionId.isIn(txnIds)))
            .get();
        for (final row in rows) {
          final txnId = row.read(transactionId)!;
          if (!priorTransactionIds.contains(txnId)) {
            createdTxnIds.add(txnId);
          }
        }

        final rawId = _database.rawSms.id;
        final processed = _database.rawSms.processed;
        final failureReason = _database.rawSms.failureReason;
        final attemptedIds = attemptedSmsIds
            .expand((id) {
              final sms = messages.where((message) => message.id == id).first;
              return sms.identityIds;
            })
            .where(ids.contains)
            .toSet()
            .toList(growable: false);
        final rawRows = attemptedIds.isEmpty
            ? const <TypedResult>[]
            : await (_database.selectOnly(_database.rawSms)
                  ..addColumns([rawId, processed, failureReason])
                  ..where(rawId.isIn(attemptedIds)))
                .get();
        for (final row in rawRows) {
          final rawSmsId = row.read(rawId)!;
          final ownerIds = messageIdsByIdentity[rawSmsId] ?? const <String>{};
          for (final smsId in ownerIds) {
            if (!attemptedSmsIds.contains(smsId) || failedIds.contains(smsId)) {
              continue;
            }
            if (row.read(processed) == true) {
              parsedIds.add(smsId);
            } else if (row.read(failureReason) == SmsFailureReason.unparsed) {
              unparsedIds.add(smsId);
            }
          }
        }
      }
      return SmsBatchIngestResult(
        succeededIds: succeededIds,
        failed: failed,
        createdTxnIds: createdTxnIds,
        alreadyKnownIds: alreadyKnownIds,
        parsedIds: parsedIds,
        unparsedIds: unparsedIds,
        failedIds: failedIds,
      );
    });
    return result;
  }

  Future<MerchantResolutionRun?> beginMerchantResolutionRun() async {
    return await _merchantResolver?.beginImportRun();
  }

  /// Id of an already-stored transaction describing the same real-world
  /// payment as [record] (e.g. a bank SMS and its wallet/UPI echo, T-025),
  /// or null if none is found. Suppressed/deleted rows are never candidates.
  Future<String?> _findDuplicateOfExisting(
    NormalizedTransactionRecord record, {
    required String lifecycleState,
  }) async {
    final window = _duplicateSuppressor.window;
    final windowStart = record.ts.toUtc().subtract(window);
    final windowEnd = record.ts.toUtc().add(window);
    final candidates = await (_database.select(_database.transactions)
          ..where(
            (row) =>
                row.direction.equals(record.direction.wireName) &
                row.isDeleted.equals(false) &
                row.isNotTransaction.equals(false) &
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
      if (_duplicateSuppressor.isDuplicate(
        record,
        existing,
        lifecycleState: lifecycleState,
      )) {
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
    final calendar = _financialCalendar;
    final start = calendar.dayContaining(_now()).start;
    final askedCount = _database.transactions.id.count();
    final askedQuery = _database.selectOnly(_database.transactions)
      ..addColumns([askedCount])
      ..where(
        _database.transactions.status.equals(DecisionStatus.asked.wireName) &
            _database.transactions.isDeleted.equals(false) &
            _database.transactions.isNotTransaction.equals(false) &
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
            _database.transactions.isNotTransaction.equals(false) &
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
            _database.transactions.isNotTransaction.equals(false) &
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
                row.isNotTransaction.equals(false) &
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
    final confidence = <String, Object?>{
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
        if (merchant?.suggestedMerchantId != null)
          'suggested_merchant_id': merchant!.suggestedMerchantId,
      },
      if (categorization != null)
        'category': {
          'c': categorization.confidence,
          'src': categorization.source,
          if (categorization.ruleId != null) 'rule_id': categorization.ruleId,
        },
    };
    CaptureDecisionProvenance.writeCurrent(
      confidence,
      statusMode: _captureDecisionStatusMode,
      categorySource: categorization?.source,
    );
    return TransactionsCompanion.insert(
      id: 'txn_$smsId',
      ts: record.ts.toUtc().millisecondsSinceEpoch,
      amount: record.amount,
      currencyCode: Value(record.currencyCode),
      currencySymbol: Value(record.currencySymbol),
      direction: record.direction.wireName,
      channel: record.channel.wireName,
      accountHint: Value(record.accountHint),
      merchantRaw: Value(record.merchantRaw),
      merchantId: Value(merchant?.merchantId),
      description: Value(categorization?.description),
      counterpartyVpa: Value(record.counterpartyVpa),
      balanceAfter: Value(record.balanceAfter),
      refId: Value(record.refId),
      categoryId: Value(categorization?.categoryId),
      parseSource: record.parseSource.wireName,
      smsId: Value(smsId),
      confidenceJson: jsonEncode(confidence),
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

  Future<void> _markRawSmsOutcome(
    String smsId, {
    required bool processed,
    required String? failureReason,
  }) {
    return (_database.update(_database.rawSms)
          ..where((row) => row.id.equals(smsId)))
        .write(
      RawSmsCompanion(
        processed: Value(processed),
        parserVersion: Value(_parserVersion),
        failureReason: Value(failureReason),
      ),
    );
  }

  int? _fallbackAmountPaise(String amountText) {
    final double? amount;
    try {
      amount = const FieldNormalizer().parseOptionalAmount(amountText);
    } on FormatException {
      return null;
    }
    if (amount == null || !amount.isFinite || amount <= 0) return null;

    // Expected amounts are stored as integer paise; keep conversion within the
    // safe integer range of the double-based normalizer.
    const maxSafePaise = 9007199254740991;
    final paiseValue = amount * 100;
    if (!paiseValue.isFinite || paiseValue > maxSafePaise) return null;
    final paise = paiseValue.round();
    return paise > 0 ? paise : null;
  }

  DateTime _reminderExpectedDate(String body, DateTime fallback) {
    DateTime fallbackDate() {
      final localDate = _financialCalendar.localDate(fallback);
      return DateTime.utc(localDate.year, localDate.month, localDate.day);
    }

    final match = RegExp(
      r'\bdue\s+on\s+(\d{1,2})-([A-Za-z]{3})-(\d{4})\b',
      caseSensitive: false,
    ).firstMatch(body);
    if (match == null) return fallbackDate();

    const months = <String, int>{
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final day = int.parse(match.group(1)!);
    final month = months[match.group(2)!.toLowerCase()];
    final year = int.parse(match.group(3)!);
    if (month == null) return fallbackDate();

    final parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return fallbackDate();
    }
    return parsed;
  }

  Future<void> _recordProcessingFailure(
    RawSms sms,
    FeatureFlagsState flagsState,
  ) async {
    await _database.into(_database.rawSms).insertOnConflictUpdate(
          RawSmsCompanion.insert(
            id: sms.id,
            sender: sms.sender,
            body: sms.body,
            receivedAt: sms.receivedAt,
            parserVersion: Value(_parserVersion),
            failureReason: const Value(SmsFailureReason.processingError),
            purgeAfter: sms.receivedAt.add(
              const Duration(days: AppConstants.rawSmsRetentionDays),
            ),
          ),
        );
  }
}

/// Shared exact-evidence validation for live ingestion, batch import, and
/// incremental catch-up. Conflicts remain content-free for callers to report.
SmsIdentityClaims validateSmsIdentityClaims(
  RawSms sms, {
  required List<RawSm> rawRows,
  required List<Transaction> transactionRows,
  required List<SmsDisposition> dispositions,
  required int parserVersion,
}) {
  const conflict = SmsIdentityClaims(conflict: true);
  for (final raw in rawRows) {
    if (raw.sender != sms.sender || raw.body != sms.body) {
      return conflict;
    }
  }

  final transactionById = {for (final row in transactionRows) row.id: row};
  if (transactionById.length > 1) {
    return conflict;
  }
  final transaction =
      transactionById.isEmpty ? null : transactionById.values.first;
  if (transaction != null) {
    final deterministicClaim = sms.identityIds.any(
      (id) => transaction.id == 'txn_$id',
    );
    if (transaction.smsId != null &&
        (!sms.identityIds.contains(transaction.smsId) ||
            (deterministicClaim &&
                transaction.smsId != transaction.id.substring(4)))) {
      return conflict;
    }
  }

  final dispositionIds = dispositions.map((row) => row.transactionId).toSet();
  if (dispositionIds.length > 1 ||
      (transaction != null &&
          dispositionIds.any((id) => id != transaction.id))) {
    return conflict;
  }
  if (transaction != null || dispositions.isNotEmpty) {
    return const SmsIdentityClaims(alreadyKnown: true);
  }

  RawSm? selectedRaw;
  for (final id in sms.identityIds) {
    for (final raw in rawRows) {
      if (raw.id == id && (selectedRaw == null || raw.id == sms.id)) {
        selectedRaw = raw;
      }
    }
  }
  final terminalRaw = rawRows.any(
    (raw) => isRawSmsAttemptTerminal(
      processed: raw.processed,
      parserVersion: raw.parserVersion,
      failureReason: raw.failureReason,
      currentParserVersion: parserVersion,
    ),
  );
  return SmsIdentityClaims(
    raw: selectedRaw,
    alreadyKnown: terminalRaw,
  );
}

/// Returns page entries whose bounded alias is claimed by different canonical
/// payloads. Identical repeated inputs with the same id/body remain idempotent.
Set<String> smsIdentityCollisionIds(List<RawSms> messages) {
  final claimantsByIdentity = <String, Map<String, RawSms>>{};
  final collisions = <String>{};
  for (final sms in messages) {
    for (final identity in sms.identityIds) {
      final claimants = claimantsByIdentity.putIfAbsent(
        identity,
        () => <String, RawSms>{},
      );
      final prior = claimants[sms.id];
      claimants[sms.id] = sms;
      if (claimants.length > 1 ||
          (prior != null &&
              (prior.sender != sms.sender || prior.body != sms.body))) {
        collisions.addAll(claimants.keys);
      }
    }
  }
  return collisions;
}

/// Keeps exact alias evidence for only the last receipt-time cohort in an
/// inbox run, which can continue across adjacent DATE-sorted pages.
class SmsIdentityCohortGuard {
  SmsIdentityCohortGuard({this.maximumClaims = 4096})
      : assert(maximumClaims > 0);

  final int maximumClaims;
  int? _receivedAtEpochMillis;
  final Map<String, _SmsIdentityCohortClaim?> _claims = {};
  bool _overflowed = false;

  Set<String> consume(List<RawSms> messages) {
    final conflicts = smsIdentityCollisionIds(messages);
    for (final sms in messages) {
      final receivedAt = sms.receivedAt.millisecondsSinceEpoch;
      if (_receivedAtEpochMillis != receivedAt) {
        _receivedAtEpochMillis = receivedAt;
        _claims.clear();
        _overflowed = false;
      }
      if (_overflowed) {
        conflicts.add(sms.id);
        continue;
      }

      final claimant = _SmsIdentityCohortClaim(
        canonicalId: sms.id,
        sender: sms.sender,
        body: sms.body,
      );
      var conflict = false;
      for (final identity in sms.identityIds) {
        if (!_claims.containsKey(identity)) continue;
        final prior = _claims[identity];
        if (prior == null ||
            prior.canonicalId != claimant.canonicalId ||
            prior.sender != claimant.sender ||
            prior.body != claimant.body) {
          conflicts.add(sms.id);
          _claims[identity] = null;
          conflict = true;
        }
      }
      if (conflict) {
        for (final identity in sms.identityIds) {
          if (_claims.containsKey(identity)) {
            _claims[identity] = null;
          } else if (_claims.length < maximumClaims) {
            _claims[identity] = null;
          } else {
            _overflowed = true;
          }
        }
        continue;
      }

      final newClaims = sms.identityIds
          .where((identity) => !_claims.containsKey(identity))
          .length;
      if (_claims.length + newClaims > maximumClaims) {
        // Once evidence cannot be retained safely, abstain on this timestamp
        // cohort until DATE advances instead of accepting unseen collisions.
        _overflowed = true;
        conflicts.add(sms.id);
        conflicts.addAll(
          messages
              .where(
                (candidate) =>
                    candidate.receivedAt.millisecondsSinceEpoch == receivedAt,
              )
              .map((candidate) => candidate.id),
        );
        continue;
      }
      for (final identity in sms.identityIds) {
        if (!_claims.containsKey(identity)) _claims[identity] = claimant;
      }
    }
    return conflicts;
  }
}

class _SmsIdentityCohortClaim {
  const _SmsIdentityCohortClaim({
    required this.canonicalId,
    required this.sender,
    required this.body,
  });

  final String canonicalId;
  final String sender;
  final String body;
}

class SmsIdentityClaims {
  const SmsIdentityClaims({
    this.raw,
    this.alreadyKnown = false,
    this.conflict = false,
  });

  final RawSm? raw;
  final bool alreadyKnown;
  final bool conflict;
}

class _SmsIdentityConflict implements Exception {
  const _SmsIdentityConflict();
}
