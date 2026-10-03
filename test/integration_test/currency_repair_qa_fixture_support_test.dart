import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/enrichment/source_currency_repair_service.dart';

import '../../integration_test/currency_repair_qa_fixture_support.dart';

void main() {
  test('synthetic fixture amount evidence points to its exact source span', () {
    final evidence = (jsonDecode(currencyRepairQaEvidenceJson()) as List).single
        as Map<String, dynamic>;
    final start = evidence['start'] as int;
    final end = evidence['end'] as int;

    expect(evidence['field'], 'amount');
    expect(evidence['extractor'], 'generic_regex');
    expect(
      currencyRepairQaBody.substring(start, end),
      currencyRepairQaAmountText,
    );
    expect(currencyRepairQaBody, contains('XX4242'));
    expect(currencyRepairQaAmount, 1234.5);
  });

  test('production repair service previews the exact fixture row in memory',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    const smsId = 't193_currency_repair_qa_sms';
    final now = DateTime.utc(2026, 10, 1, 10);
    await database.into(database.paymentSources).insert(
          PaymentSourcesCompanion.insert(
            id: currencyRepairQaSourceId,
            kind: 'card',
            maskedIdentifier: 'xx4242',
            nickname: const Value('Synthetic Currency QA'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.into(database.rawSms).insert(
          RawSmsCompanion.insert(
            id: smsId,
            sender: 'XX-BANK',
            body: currencyRepairQaBody,
            receivedAt: now.subtract(const Duration(days: 1)),
            purgeAfter: now.add(const Duration(days: 30)),
          ),
        );
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: currencyRepairQaTransactionId,
            ts: now.millisecondsSinceEpoch,
            amount: currencyRepairQaAmount,
            direction: 'debit',
            channel: 'card',
            paymentSourceId: const Value(currencyRepairQaSourceId),
            merchantRaw: const Value('Synthetic Currency QA'),
            description: const Value('Synthetic Currency QA purchase'),
            parseSource: 'generic',
            smsId: const Value(smsId),
            confidenceJson: '{}',
            evidenceJson: Value(currencyRepairQaEvidenceJson()),
            status: 'confirmed',
            createdAt: now,
            updatedAt: now,
          ),
        );

    final preview = await SourceCurrencyRepairService(database)
        .preview(currencyRepairQaTransactionId);

    expect(preview, isNotNull);
    expect(preview!.currencyToken, 'Rs.');
    expect(preview.amountPaise, 123450);
    await database.close();
  });
}
