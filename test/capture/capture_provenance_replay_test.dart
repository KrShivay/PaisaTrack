import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/captured_sms_source.dart';
import 'package:paisatrack/capture/message_kind_classifier.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/sms_backfill.dart';
import 'package:paisatrack/capture/sms_import_state.dart';
import 'package:paisatrack/capture/sms_ingestion.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/data/repositories/rule_repository.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/enrichment/categorizer.dart';
import 'package:paisatrack/enrichment/merchant_resolver.dart';
import 'package:paisatrack/enrichment/seed_category_map.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

import '../support/capture_replay_report.dart';
import '../support/fake_sms_permission_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixture = _ReplayFixture.load();
  final matcher = TemplateMatcher(
    registries: [
      TemplateRegistry(
        senderPatterns: [RegExp(r'^XX-TESTBANK$')],
        templates: [
          SmsTemplate(
            id: 't177a_synthetic_debit_v1',
            regex: RegExp(
              r'INR (?<amount>\d+) debited to (?<merchant>[A-Z ]+) via UPI',
            ),
            direction: 'debit',
            channel: 'upi',
            dateFormat: null,
            provenance: TemplateProvenance.public,
          ),
        ],
      ),
    ],
  );

  for (final mode in _CaptureMode.values) {
    test(
      'production $mode provider wiring yields a labeled replay report',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        await database.seedDefaultCategories();
        final liveEvents = StreamController<Object?>();
        final reader = _FixtureInboxReader(fixture.messages.reversed.toList());
        final marker = _FixtureBackfillMarker(
          version: mode == _CaptureMode.resume ? smsHistoryImportVersion : 0,
        );
        final overrides = <Override>[
          appDatabaseProvider.overrideWith((ref) async => database),
          templateMatcherProvider.overrideWith((ref) async => matcher),
          parserCascadeProvider.overrideWith(
            (ref) async => ParserCascade(templateMatcher: matcher),
          ),
          categorizerProvider.overrideWith(
            (ref) async => Categorizer(
              rules: RuleRepository(database),
              seedMap: SeedCategoryMap({
                'alpha mart': 'groceries',
                'beta cafe': 'groceries',
                'gamma market': 'groceries',
              }),
            ),
          ),
          messageKindClassifierProvider.overrideWith((ref) async {
            return MessageKindClassifier.fromJson(
              File('assets/seed/message_cues_in.json').readAsStringSync(),
            );
          }),
          smsInboxReaderProvider.overrideWithValue(reader),
          backfillMarkerProvider.overrideWithValue(marker),
          merchantResolverProvider(
            database,
          ).overrideWithValue(MerchantResolver(database, const NoopEmbedder())),
        ];
        if (mode == _CaptureMode.live) {
          overrides.addAll([
            smsPermissionGateProvider.overrideWithValue(
              FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
            ),
            capturedSmsSourceProvider.overrideWithValue(
              PlatformCapturedSmsSource(
                channel: _FixtureCapturedSmsChannel(liveEvents.stream),
              ),
            ),
          ]);
        }
        final container = ProviderContainer(overrides: overrides);
        try {
          switch (mode) {
            case _CaptureMode.live:
              final subscription = container.listen<void>(
                smsCaptureBootstrapProvider,
                (_, __) {},
                fireImmediately: true,
              );
              await container.read(smsPermissionControllerProvider.future);
              await container.read(appDatabaseProvider.future);
              await container.read(parserCascadeProvider.future);
              await container.read(categorizerProvider.future);
              await container.read(messageKindClassifierProvider.future);
              await pumpEventQueue();
              for (final message in fixture.messages) {
                liveEvents.add(_toChannelPayload(message));
                await pumpEventQueue();
              }
              subscription.close();
            case _CaptureMode.history:
              final importer = await container.read(
                smsHistoryImportRunnerProvider.future,
              );
              await importer.run(force: true);
            case _CaptureMode.resume:
              final catchUp = await container.read(
                smsIncrementalCatchUpProvider.future,
              );
              await catchUp.run();
          }

          final transactions =
              await database.select(database.transactions).get();
          final bySmsId = {for (final row in transactions) row.smsId!: row};
          final observations = fixture.messages.map((message) {
            final transaction = bySmsId[message.id];
            return CaptureReplayObservation(
              smsId: message.id,
              receivedAt: message.receivedAt,
              predictedCategoryId: transaction?.categoryId,
              explicitCategoryId: message.explicitCategoryId,
              labelSource: message.labelSource,
              sourceEvidenceAvailable: transaction?.evidenceJson != null,
              // T-177a's production rows do not persist a decision-version key.
              decisionVersion: null,
            );
          });
          final report = CaptureReplayReport.fromObservations(
            observations.toList().reversed,
          );

          expect(report.chronologicalIds, fixture.messages.map((m) => m.id));
          expect(report.totalRows, 4);
          expect(report.explicitLabelRows, 2);
          expect(report.predictedRows, 3);
          expect(report.evaluatedRows, 2);
          expect(report.correctRows, 1);
          expect(report.incorrectRows, 1);
          expect(report.abstainedLabelRows, 0);
          expect(report.unreviewedRowsExcluded, 1);
          expect(report.unlabeledRows, 1);
          expect(report.measuredPrecision, 0.5);
          expect(report.explicitLabelCoverage, 1);
          expect(report.decisionCoverage, 0.75);
          expect(report.userDecisionsPer100Rows, 50);
          expect(report.precisionNumerator, 1);
          expect(report.precisionDenominator, 2);
          expect(report.coverageNumerator, 3);
          expect(report.coverageDenominator, 4);
          expect(report.explicitLabelCoverageNumerator, 2);
          expect(report.explicitLabelCoverageDenominator, 2);
          expect(report.evaluationScope, 'observed_explicit_feedback');
          expect(report.cohorts.single.monthUtc, '2026-01');
          expect(report.cohorts.single.rowCount, 4);
          expect(report.cohorts.single.explicitLabelCount, 2);
          expect(report.missingSourceEvidenceRows, 1);
          expect(report.missingDecisionVersionRows, 4);
          expect(report.evidenceComplete, isFalse);
          expect(report.isHoldoutValidated, isFalse);

          // Historical and resume providers deliberately force review status;
          // live capture uses the normal decision policy.
          if (mode != _CaptureMode.live) {
            expect(transactions, isNotEmpty);
            expect(
              transactions.every((row) => row.status == 'needs_review'),
              isTrue,
            );
          }
          final merchantSources = transactions.map((row) {
            final confidence =
                jsonDecode(row.confidenceJson) as Map<String, Object?>;
            return (confidence['merchant']! as Map<String, Object?>)['src'];
          }).toSet();
          expect(
            merchantSources,
            mode == _CaptureMode.live ? {'unembedded'} : {'template'},
            reason: 'live resolves merchant identity; history/resume currently '
                'retain parser merchant text without the resolver',
          );
          expect(
            transactions.every((row) {
              final confidence =
                  jsonDecode(row.confidenceJson) as Map<String, Object?>;
              return (confidence['parser']!
                      as Map<String, Object?>)['provenance'] ==
                  'public';
            }),
            isTrue,
            reason: 'synthetic templates must not be recorded as device-grade',
          );
          // The unrecognized synthetic source is retained but never promoted to
          // a transaction or counted as a prediction.
          expect(
            transactions.map((row) => row.smsId),
            isNot(contains('t177a_004')),
          );
        } finally {
          container.dispose();
          if (liveEvents.hasListener) await liveEvents.close();
          await database.close();
        }
      },
    );
  }

  test('no explicit labels means precision is unavailable, not zero', () {
    final report = CaptureReplayReport.fromObservations([
      CaptureReplayObservation(
        smsId: 'unreviewed_only',
        receivedAt: DateTime.utc(2026),
        predictedCategoryId: 'groceries',
        labelSource: CaptureLabelSource.unreviewed,
      ),
    ]);

    expect(report.explicitLabelRows, 0);
    expect(report.precisionNumerator, 0);
    expect(report.precisionDenominator, 0);
    expect(report.measuredPrecision, isNull);
    expect(report.explicitLabelCoverage, isNull);
    expect(report.userDecisionsPer100Rows, 0);
    expect(report.isHoldoutValidated, isFalse);
  });

  test('explicit labels without a prediction count as abstentions', () {
    final report = CaptureReplayReport.fromObservations([
      CaptureReplayObservation(
        smsId: 'explicit_label_after_abstention',
        receivedAt: DateTime.utc(2026),
        predictedCategoryId: null,
        explicitCategoryId: 'groceries',
        labelSource: CaptureLabelSource.confirmed,
        sourceEvidenceAvailable: false,
      ),
      CaptureReplayObservation(
        smsId: 'silent_guess',
        receivedAt: DateTime.utc(2026, 1, 2),
        predictedCategoryId: 'groceries',
        labelSource: CaptureLabelSource.unreviewed,
        decisionVersion: null,
      ),
    ]);

    expect(report.explicitLabelRows, 1);
    expect(report.abstainedLabelRows, 1);
    expect(report.evaluatedRows, 0);
    expect(report.explicitLabelCoverage, 0);
    expect(report.measuredPrecision, isNull);
    expect(report.missingSourceEvidenceRows, 1);
    expect(report.missingDecisionVersionRows, 2);
    expect(report.evidenceComplete, isFalse);
  });

  test('chronology ties are stable and repeated source IDs are rejected', () {
    final tied = CaptureReplayReport.fromObservations([
      _observation('b', DateTime.utc(2026)),
      _observation('a', DateTime.utc(2026)),
    ]);
    expect(tied.chronologicalIds, ['a', 'b']);
    expect(
      () => CaptureReplayReport.fromObservations([
        _observation('same', DateTime.utc(2026)),
        _observation('same', DateTime.utc(2026, 1, 2)),
      ]),
      throwsArgumentError,
    );
  });
}

CaptureReplayObservation _observation(String id, DateTime receivedAt) {
  return CaptureReplayObservation(
    smsId: id,
    receivedAt: receivedAt,
    predictedCategoryId: null,
    labelSource: CaptureLabelSource.absent,
  );
}

Map<Object?, Object?> _toChannelPayload(RawSms message) => {
      'id': message.id,
      'sender': message.sender,
      'body': message.body,
      'receivedAtEpochMillis': message.receivedAt.millisecondsSinceEpoch,
    };

enum _CaptureMode { live, history, resume }

class _ReplayFixture {
  const _ReplayFixture(this.messages);

  final List<_FixtureMessage> messages;

  factory _ReplayFixture.load() {
    final document = jsonDecode(
      File(
        'test/fixtures/sms/t177a_capture_replay.json',
      ).readAsStringSync(),
    ) as Map<String, Object?>;
    if (document['privacy'] != 'synthetic_public') {
      throw const FormatException('T-177a fixture must remain synthetic');
    }
    final records =
        (document['messages']! as List<Object?>).cast<Map<String, Object?>>();
    return _ReplayFixture([
      for (final record in records)
        _FixtureMessage(
          id: record['id']! as String,
          sender: record['sender']! as String,
          body: record['body']! as String,
          receivedAt: DateTime.parse(record['received_at']! as String).toUtc(),
          labelSource: CaptureLabelSource.values.byName(
            record['label_source']! as String,
          ),
          explicitCategoryId: record['explicit_category_id'] as String?,
        ),
    ]);
  }
}

class _FixtureMessage extends RawSms {
  _FixtureMessage({
    required super.id,
    required super.sender,
    required super.body,
    required super.receivedAt,
    required this.labelSource,
    required this.explicitCategoryId,
  });

  final CaptureLabelSource labelSource;
  final String? explicitCategoryId;
}

class _FixtureInboxReader implements SmsInboxReader {
  _FixtureInboxReader(this.messages);

  final List<RawSms> messages;

  @override
  Future<SmsInboxPage> readPage({
    SmsInboxCursor? before,
    required int limit,
  }) async {
    if (before != null) return const SmsInboxPage(messages: []);
    return SmsInboxPage(
      messages: messages,
      scanned: messages.length,
      accepted: messages.length,
    );
  }
}

class _FixtureBackfillMarker implements BackfillMarker {
  _FixtureBackfillMarker({required this.version});

  final int version;

  @override
  Future<int> completedVersion() async => version;

  @override
  Future<SmsImportCheckpoint?> checkpoint() async => null;

  @override
  Future<void> saveCheckpoint(SmsImportCheckpoint checkpoint) async {}

  @override
  Future<void> markCompleted(int version) async {}

  @override
  Future<void> reset() async {}
}

class _FixtureCapturedSmsChannel implements CapturedSmsChannel {
  const _FixtureCapturedSmsChannel(this.events);

  final Stream<Object?> events;

  @override
  Stream<Object?> receiveBroadcastStream() => events;
}
