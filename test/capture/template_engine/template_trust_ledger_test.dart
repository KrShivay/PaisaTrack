import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/capture/template_engine/template_trust_ledger.dart';
import 'package:paisatrack/core/result.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

void main() {
  late AppDatabase database;
  late TemplateTrustLedger ledger;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    ledger = TemplateTrustLedger(database);
  });

  tearDown(() => database.close());

  test('promotes a public template after twenty clean confirmations', () async {
    await _insertPublicTemplateTransaction(database, 'txn-promote', 'kotak_v1');
    for (var index = 0; index < 20; index++) {
      await _insertVerdict(database, 'ok_$index', 'txn-promote', 'ok');
    }

    final snapshot = await ledger.refresh();
    final entry = snapshot.entries['kotak_v1']!;

    expect(entry.confirmedParses, 20);
    expect(entry.amountDirectionCorrections, 0);
    expect(entry.isPromoted, isTrue);
    expect(entry.isFlagged, isFalse);
    expect(await ledger.confidenceForTemplate('kotak_v1'), 0.97);

    final parser = ParserCascade(
      templateMatcher: TemplateMatcher(
        registries: [
          TemplateRegistry(
            senderPatterns: [RegExp(r'^XX-KOTAK$')],
            templates: [
              SmsTemplate(
                id: 'kotak_v1',
                regex: RegExp(r'Rs\. (?<amount>\d+) debited'),
                direction: 'debit',
                channel: 'upi',
                dateFormat: null,
                provenance: TemplateProvenance.public,
              ),
            ],
          ),
        ],
        trustLedger: ledger,
      ),
    );
    final parsed = await parser.parse(
      RawSms(
        id: 'promoted-sms',
        sender: 'XX-KOTAK',
        body: 'Rs. 10 debited',
        receivedAt: DateTime.utc(2026, 7, 10),
      ),
    );
    expect(
      (parsed as Ok<NormalizedTransactionRecord, ParseFailure>)
          .value
          .parseConfidence,
      0.97,
    );

    final cached = await (database.select(database.modelMeta)
          ..where((row) => row.key.equals(templateTrustLedgerMetaKey)))
        .getSingle();
    expect(jsonDecode(cached.value), containsPair('version', 1));
  });

  test('amount or direction correction demotes and flags a public template',
      () async {
    await _insertPublicTemplateTransaction(database, 'txn-demote', 'centbk_v1');
    for (var index = 0; index < 20; index++) {
      await _insertVerdict(database, 'ok_$index', 'txn-demote', 'ok');
    }
    await _insertVerdict(
      database,
      'amount_correction',
      'txn-demote',
      'amount_corrected',
    );
    await _insertVerdict(
      database,
      'direction_correction',
      'txn-demote',
      'direction_corrected',
    );
    // Merchant-only fixes are useful feedback but do not demote parser trust.
    await _insertVerdict(
      database,
      'merchant_correction',
      'txn-demote',
      'merchant_corrected',
    );

    final snapshot = await ledger.refresh();
    final entry = snapshot.entries['centbk_v1']!;

    expect(entry.confirmedParses, 20);
    expect(entry.amountCorrections, 1);
    expect(entry.directionCorrections, 1);
    expect(entry.isPromoted, isFalse);
    expect(entry.isFlagged, isTrue);
    expect(snapshot.flaggedEntries.single.templateId, 'centbk_v1');
    expect(await ledger.confidenceForTemplate('centbk_v1'), 0.85);
  });

  test('ignores parse verdicts without public template attribution', () async {
    final now = DateTime.utc(2026, 7, 10);
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: 'generic',
            ts: now.millisecondsSinceEpoch,
            amount: 10,
            direction: 'debit',
            channel: 'upi',
            parseSource: 'generic',
            confidenceJson: '{"parser":{"c":0.6,"src":"generic"}}',
            status: 'needs_review',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _insertVerdict(database, 'generic_ok', 'generic', 'ok');

    expect((await ledger.refresh()).entries, isEmpty);
  });

  test(
      'ignores legacy and non-template confirmations while retaining purged evidence',
      () async {
    await _insertPublicTemplateTransaction(database, 'txn-purged', 'valid_v1');
    await _insertVerdict(
      database,
      'legacy_ok',
      'txn-purged',
      'ok',
      versioned: false,
    );

    for (final entry in [
      ('manual', 'manual', true),
      ('imported', 'unknown', true),
      ('no_evidence', 'template', false),
    ]) {
      final now = DateTime.utc(2026, 7, 10);
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: entry.$1,
              ts: now.millisecondsSinceEpoch,
              amount: 10,
              direction: 'debit',
              channel: 'upi',
              parseSource: entry.$2,
              confidenceJson: jsonEncode({
                'parser': {
                  'c': 0.85,
                  'src': 'template',
                  'template_id': 'invalid_v1',
                  'provenance': 'public',
                },
              }),
              evidenceJson: entry.$3
                  ? const Value(
                      '[{"field":"amount","start":0,"end":2,"verbatim":"10","extractor":"regex"}]',
                    )
                  : const Value.absent(),
              status: 'needs_review',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _insertVerdict(database, 'ok_${entry.$1}', entry.$1, 'ok');
    }
    await _insertPublicTemplateTransaction(
      database,
      'deleted_public',
      'invalid_v1',
      isDeleted: true,
    );
    await _insertVerdict(database, 'ok_deleted_public', 'deleted_public', 'ok');
    await _insertPublicTemplateTransaction(
      database,
      'duplicate_parent',
      'invalid_v1',
    );
    await _insertPublicTemplateTransaction(
      database,
      'duplicate_public',
      'invalid_v1',
      duplicateOfTxnId: 'duplicate_parent',
    );
    await _insertVerdict(
      database,
      'ok_duplicate_public',
      'duplicate_public',
      'ok',
    );

    final snapshot = await ledger.refresh();
    expect(snapshot.entries['valid_v1']?.confirmedParses ?? 0, 0);
    expect(snapshot.entries['invalid_v1'], null);
  });

  test('rebuilds v2 trust cache rather than trusting restored v1 counters',
      () async {
    await database.into(database.modelMeta).insert(
          ModelMetaCompanion.insert(
            key: 'template_trust_ledger_v1',
            value: jsonEncode({
              'version': 1,
              'templates': {
                'stale_v1': {
                  'confirmed_parses': 20,
                  'amount_corrections': 0,
                  'direction_corrections': 0,
                },
              },
            }),
          ),
        );
    await _insertPublicTemplateTransaction(database, 'txn-cache', 'valid_v1');
    await _insertVerdict(database, 'valid_cache_ok', 'txn-cache', 'ok');

    final rebuilt = await ledger.load();

    expect(rebuilt.entries['stale_v1'], null);
    expect(rebuilt.entries['valid_v1']?.confirmedParses, 1);
    expect(rebuilt.entries['valid_v1']?.isPromoted, isFalse);
    final persisted = await (database.select(database.modelMeta)
          ..where((row) => row.key.equals(templateTrustLedgerMetaKey)))
        .getSingleOrNull();
    expect(persisted != null, isTrue);
  });

  test('watch emits a developer alert after a demotion refresh', () async {
    final snapshots = ledger.watch().take(2).toList();
    await _insertPublicTemplateTransaction(database, 'txn-watch', 'watch_v1');
    await _insertVerdict(
      database,
      'watch_amount_correction',
      'txn-watch',
      'amount_corrected',
    );

    await ledger.refresh();

    final values = await snapshots;
    expect(values.first.flaggedEntries, isEmpty);
    expect(values.last.flaggedEntries.single.templateId, 'watch_v1');
  });
}

Future<void> _insertPublicTemplateTransaction(
  AppDatabase database,
  String id,
  String templateId, {
  bool isDeleted = false,
  String? duplicateOfTxnId,
}) async {
  final now = DateTime.utc(2026, 7, 10);
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: now.millisecondsSinceEpoch,
          amount: 10,
          direction: 'debit',
          channel: 'upi',
          parseSource: 'template',
          isDeleted: Value(isDeleted),
          duplicateOfTxnId: Value(duplicateOfTxnId),
          confidenceJson: jsonEncode({
            'parser': {
              'c': 0.85,
              'src': 'template',
              'template_id': templateId,
              'provenance': 'public',
            },
          }),
          evidenceJson: const Value(
            '[{"field":"amount","start":0,"end":2,"verbatim":"10","extractor":"regex"}]',
          ),
          status: 'needs_review',
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<void> _insertVerdict(
  AppDatabase database,
  String id,
  String txnId,
  String verdict, {
  bool versioned = true,
}) {
  return database.into(database.feedback).insert(
        FeedbackCompanion.insert(
          id: id,
          txnId: txnId,
          field: 'parse_verdict',
          oldValue: versioned && verdict == 'ok'
              ? const Value(templateTrustExplicitConfirmationMarker)
              : const Value.absent(),
          newValue: Value(verdict),
          context: 'parse_confirm',
          createdAt: DateTime.utc(2026, 7, 10),
        ),
      );
}
