import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/enrichment/source_currency_repair_service.dart';

void main() {
  late AppDatabase database;
  late SourceCurrencyRepairService service;
  final now = DateTime.utc(2026, 9, 30, 10);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    service = SourceCurrencyRepairService(database, clock: () => now);
  });

  tearDown(() async => database.close());

  Future<void> insertCandidate({
    required String id,
    required String body,
    required double amount,
    String parseSource = 'template',
    String extractor = 'template',
    String? evidenceVerbatim,
    int? evidenceStart,
    String? smsId,
    DateTime? purgeAfter,
    String? currencyCode,
    String? currencySymbol,
    bool isDeleted = false,
    bool isNotTransaction = false,
    String? duplicateOfTxnId,
    bool includeEvidence = true,
  }) async {
    final sourceId = smsId ?? 'sms_$id';
    if (await (database.select(database.rawSms)
              ..where((row) => row.id.equals(sourceId)))
            .getSingleOrNull() ==
        null) {
      await database.into(database.rawSms).insert(
            RawSmsCompanion.insert(
              id: sourceId,
              sender: 'XX-BANK',
              body: body,
              receivedAt: now.subtract(const Duration(days: 1)),
              purgeAfter: purgeAfter ?? now.add(const Duration(days: 10)),
            ),
          );
    }

    final amountSpan = evidenceVerbatim ?? '500';
    final start = evidenceStart ?? body.indexOf(amountSpan);
    final evidenceJson = includeEvidence
        ? jsonEncode([
            {
              'field': 'amount',
              'start': start,
              'end': start + amountSpan.length,
              'verbatim': amountSpan,
              'extractor': extractor,
            },
          ])
        : null;
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: id,
            ts: now.millisecondsSinceEpoch,
            amount: amount,
            currencyCode: Value(currencyCode),
            currencySymbol: Value(currencySymbol),
            direction: 'debit',
            channel: 'upi',
            description: const Value('keep this note'),
            parseSource: parseSource,
            smsId: Value(sourceId),
            confidenceJson: '{}',
            evidenceJson: Value(evidenceJson),
            status: 'confirmed',
            isDeleted: Value(isDeleted),
            isNotTransaction: Value(isNotTransaction),
            duplicateOfTxnId: Value(duplicateOfTxnId),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  test('previews exact adjacent INR tokens without mutating source rows',
      () async {
    for (final token in ['Rs', 'Rs.', 'INR', '₹']) {
      final id = 'txn_${token.codeUnits.join('_')}';
      final body = 'Paid $token 500 to Cafe';
      await insertCandidate(
        id: id,
        body: body,
        amount: 500,
        evidenceVerbatim: '500',
        evidenceStart: body.indexOf('500'),
      );

      final preview = await service.preview(id);
      expect(preview, isNotNull, reason: token);
      expect(preview!.currencyToken, token, reason: token);
      expect(preview.amountPaise, 50000, reason: token);
      final txn = await (database.select(database.transactions)
            ..where((row) => row.id.equals(id)))
          .getSingle();
      expect(txn.currencyCode, isNull);
      expect(txn.currencySymbol, isNull);
      expect(txn.description, 'keep this note');
    }
  });

  test('accepts generic amount spans that include Rs. and validates paise',
      () async {
    const body = 'Paid Rs. 1,234.50 to Cafe';
    await insertCandidate(
      id: 'txn_generic',
      body: body,
      amount: 1234.5,
      parseSource: 'generic',
      extractor: 'generic_regex',
      evidenceVerbatim: 'Rs. 1,234.50',
      evidenceStart: body.indexOf('Rs.'),
    );

    final preview = await service.preview('txn_generic');
    expect(preview, isNotNull);
    expect(preview!.currencyToken, 'Rs.');
    expect(preview.amountPaise, 123450);
  });

  test('accepts local LLM evidence only when its bounded amount span verifies',
      () async {
    const body = 'Paid 500 INR to Cafe';
    await insertCandidate(
      id: 'txn_llm',
      body: body,
      amount: 500,
      parseSource: 'local_llm',
      extractor: 'local_llm',
      evidenceVerbatim: '500',
      evidenceStart: body.indexOf('500'),
    );

    expect(await service.preview('txn_llm'), isNotNull);
  });

  test('accepts one exact INR token immediately after amount evidence',
      () async {
    const body = 'Paid 500 Rs. to Cafe';
    await insertCandidate(
      id: 'txn_suffix',
      body: body,
      amount: 500,
      evidenceVerbatim: '500',
      evidenceStart: body.indexOf('500'),
    );

    expect((await service.preview('txn_suffix'))?.currencyToken, 'Rs.');
  });

  test('apply is idempotent and undo changes only currency fields', () async {
    const body = 'Paid Rs. 500 to Cafe';
    await insertCandidate(
      id: 'txn_apply',
      body: body,
      amount: 500,
      evidenceVerbatim: '500',
      evidenceStart: body.indexOf('500'),
    );
    final preview = (await service.preview('txn_apply'))!;

    expect(await service.apply(preview), isTrue);
    expect(await service.apply(preview), isFalse);
    var txn = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_apply')))
        .getSingle();
    expect(txn.currencyCode, 'INR');
    expect(txn.currencySymbol, '₹');
    expect(txn.amount, 500);
    expect(txn.description, 'keep this note');
    expect(txn.updatedAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);

    expect(await service.undo(preview), isTrue);
    txn = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_apply')))
        .getSingle();
    expect(txn.currencyCode, isNull);
    expect(txn.currencySymbol, isNull);
    expect(txn.description, 'keep this note');
  });

  test('apply rechecks amount and undo preserves later currency changes',
      () async {
    const body = 'Paid Rs 500 to Cafe';
    await insertCandidate(
      id: 'txn_stale_apply',
      body: body,
      amount: 500,
      evidenceVerbatim: '500',
      evidenceStart: body.indexOf('500'),
    );
    final stale = (await service.preview('txn_stale_apply'))!;
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('txn_stale_apply')))
        .write(const TransactionsCompanion(amount: Value(501)));
    expect(await service.apply(stale), isFalse);
    expect(
      (await (database.select(database.transactions)
                ..where((row) => row.id.equals('txn_stale_apply')))
              .getSingle())
          .currencyCode,
      isNull,
    );

    await (database.update(database.transactions)
          ..where((row) => row.id.equals('txn_stale_apply')))
        .write(const TransactionsCompanion(amount: Value(500)));
    final preview = (await service.preview('txn_stale_apply'))!;
    expect(await service.apply(preview), isTrue);
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('txn_stale_apply')))
        .write(
      const TransactionsCompanion(
        currencyCode: Value('USD'),
        currencySymbol: Value('\$'),
      ),
    );
    expect(await service.undo(preview), isFalse);
    final txn = await (database.select(database.transactions)
          ..where((row) => row.id.equals('txn_stale_apply')))
        .getSingle();
    expect(txn.currencyCode, 'USD');
    expect(txn.currencySymbol, '\$');
  });

  test('rejects unsafe provenance, missing/expired source, and pre-set fields',
      () async {
    const body = 'Paid INR 500 to Cafe';
    final candidates = [
      ('manual', 'manual', null, null, null, null),
      ('imported', 'unknown', null, null, null, null),
      ('missing_sms', 'template', null, null, null, null),
      (
        'expired',
        'template',
        null,
        null,
        null,
        now.subtract(const Duration(seconds: 1)),
      ),
      ('known_code', 'template', 'INR', null, null, null),
      ('known_symbol', 'template', null, '₹', null, null),
      ('deleted', 'template', null, null, true, null),
    ];
    for (final candidate in candidates) {
      final (id, parseSource, code, symbol, deleted, expiry) = candidate;
      await insertCandidate(
        id: id,
        body: body,
        amount: 500,
        parseSource: parseSource,
        currencyCode: code,
        currencySymbol: symbol,
        isDeleted: deleted ?? false,
        purgeAfter: expiry,
        smsId: id == 'missing_sms' ? null : null,
        evidenceVerbatim: '500',
        evidenceStart: body.indexOf('500'),
      );
      if (id == 'missing_sms') {
        await (database.update(database.transactions)
              ..where((row) => row.id.equals(id)))
            .write(const TransactionsCompanion(smsId: Value(null)));
      }
      expect(await service.preview(id), isNull, reason: id);
    }
  });

  test('rejects duplicate SMS links, suppressed rows, and not-transactions',
      () async {
    const body = 'Paid ₹500 to Cafe';
    await insertCandidate(
      id: 'txn_duplicate_source',
      body: body,
      amount: 500,
      smsId: 'sms_shared',
      evidenceVerbatim: '500',
      evidenceStart: body.indexOf('500'),
    );
    await insertCandidate(
      id: 'txn_duplicate_echo',
      body: body,
      amount: 500,
      smsId: 'sms_shared',
      evidenceVerbatim: '500',
      evidenceStart: body.indexOf('500'),
      duplicateOfTxnId: 'txn_duplicate_source',
    );
    await insertCandidate(
      id: 'txn_not_transaction',
      body: body,
      amount: 500,
      isNotTransaction: true,
      evidenceVerbatim: '500',
      evidenceStart: body.indexOf('500'),
    );

    expect(await service.preview('txn_duplicate_source'), isNull);
    expect(await service.preview('txn_duplicate_echo'), isNull);
    expect(await service.preview('txn_not_transaction'), isNull);
  });

  test('rejects stale spans, changed amounts, distant and ambiguous markers',
      () async {
    const body = 'Paid 500 to Shop. Available balance Rs. 500';
    await insertCandidate(
      id: 'txn_distant_marker',
      body: body,
      amount: 500,
      evidenceVerbatim: '500',
      evidenceStart: body.indexOf('500'),
    );
    await insertCandidate(
      id: 'txn_stale_span',
      body: 'Paid Rs 500 to Shop',
      amount: 500,
      evidenceVerbatim: '500',
      evidenceStart: 0,
    );
    await insertCandidate(
      id: 'txn_mismatch',
      body: 'Paid INR 500 to Shop',
      amount: 501,
      evidenceVerbatim: '500',
      evidenceStart: 9,
    );
    await insertCandidate(
      id: 'txn_ambiguous',
      body: 'Paid Rs 500 INR to Shop',
      amount: 500,
      evidenceVerbatim: '500',
      evidenceStart: 8,
    );
    await insertCandidate(
      id: 'txn_malformed_amount',
      body: 'Paid Rs. , to Shop',
      amount: 500,
      evidenceVerbatim: ',',
      evidenceStart: 9,
    );

    for (final id in [
      'txn_distant_marker',
      'txn_stale_span',
      'txn_mismatch',
      'txn_ambiguous',
      'txn_malformed_amount',
    ]) {
      expect(await service.preview(id), isNull, reason: id);
    }
  });

  test('ignores USD and ambiguous dollar markers', () async {
    for (final (id, marker) in [
      ('txn_usd', 'USD'),
      ('txn_us_dollar', 'US\$'),
      ('txn_dollar', '\$'),
    ]) {
      final body = 'Paid $marker 500 to Cafe';
      await insertCandidate(
        id: id,
        body: body,
        amount: 500,
        evidenceVerbatim: '500',
        evidenceStart: body.indexOf('500'),
      );
      expect(await service.preview(id), isNull, reason: marker);
    }
  });
}
