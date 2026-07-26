import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/generic_transaction_parser.dart';
import 'package:paisatrack/capture/span_verifier.dart';
import 'package:paisatrack/capture/template_engine/field_normalizer.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

void main() {
  const verifier = SpanVerifier();
  const normalizer = FieldNormalizer();
  const genericParser = GenericTransactionParser();

  test('verifies accurate evidence spans against body text', () {
    const body = 'Rs 450.00 debited from A/C xx1234 on 10-10-23';
    final evidence = [
      const FieldEvidence(
        field: 'amount',
        start: 3,
        end: 9,
        verbatim: '450.00',
        extractor: 'template',
      ),
      const FieldEvidence(
        field: 'direction',
        start: 10,
        end: 17,
        verbatim: 'debited',
        extractor: 'template',
      ),
      const FieldEvidence(
        field: 'ts',
        start: 37,
        end: 45,
        verbatim: '10-10-23',
        extractor: 'template',
      ),
    ];
    final record = NormalizedTransactionRecord(
      amount: 450.0,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: null,
      counterpartyVpa: null,
      accountHint: 'xx1234',
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2023, 10, 10),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
      evidence: evidence,
    );

    expect(verifier.verify(body: body, evidence: evidence, record: record), isTrue);
  });

  test('refuses tampered evidence spans where verbatim does not match body substring', () {
    const body = 'Rs 450.00 debited from A/C xx1234 on 10-10-23';
    final tamperedEvidence = [
      const FieldEvidence(
        field: 'amount',
        start: 3,
        end: 9,
        verbatim: '999.00', // tampered verbatim
        extractor: 'template',
      ),
      const FieldEvidence(
        field: 'direction',
        start: 10,
        end: 17,
        verbatim: 'debited',
        extractor: 'template',
      ),
      const FieldEvidence(
        field: 'ts',
        start: 37,
        end: 45,
        verbatim: '10-10-23',
        extractor: 'template',
      ),
    ];
    final record = NormalizedTransactionRecord(
      amount: 450.0,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: null,
      counterpartyVpa: null,
      accountHint: 'xx1234',
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2023, 10, 10),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
      evidence: tamperedEvidence,
    );

    expect(verifier.verify(body: body, evidence: tamperedEvidence, record: record), isFalse);
  });

  test('refuses evidence missing required fields', () {
    const body = 'Rs 450.00 debited from A/C xx1234';
    final incompleteEvidence = [
      const FieldEvidence(
        field: 'amount',
        start: 3,
        end: 9,
        verbatim: '450.00',
        extractor: 'template',
      ),
      // Missing direction and ts
    ];
    final record = NormalizedTransactionRecord(
      amount: 450.0,
      direction: TransactionDirection.debit,
      channel: TransactionChannel.upi,
      merchantRaw: null,
      counterpartyVpa: null,
      accountHint: 'xx1234',
      balanceAfter: null,
      refId: null,
      ts: DateTime.utc(2023, 10, 10),
      parseSource: ParseSource.template,
      parseConfidence: 0.97,
      evidence: incompleteEvidence,
    );

    expect(verifier.verify(body: body, evidence: incompleteEvidence, record: record), isFalse);
  });

  test('generic transaction parser emits verifying evidence', () {
    final sms = RawSms(
      id: 'sms_gen_1',
      sender: 'HDFCBK',
      body: 'Rs 1250.00 spent on HDFC Bank Card xx4321 at ZOMATO',
      receivedAt: DateTime.utc(2023, 10, 10),
    );

    final record = genericParser.parse(sms);
    expect(record, isNotNull);
    expect(record!.evidence, isNotNull);
    expect(record.evidence!, isNotEmpty);

    expect(
      verifier.verify(
        body: sms.body,
        evidence: record.evidence,
        record: record,
      ),
      isTrue,
    );
  });

  test('template parser via normalizer emits verifying evidence', () {
    final template = SmsTemplate(
      id: 'hdfc_debit_test',
      direction: 'debit',
      channel: 'card',
      dateFormat: null,
      provenance: TemplateProvenance.device,
      regex: RegExp(r'Rs\s*(?<amount>[\d,]+(?:\.\d{1,2})?)\s+spent\s+at\s+(?<merchant>.+)', caseSensitive: false),
    );
    const body = 'Rs 750.00 spent at Swiggy';
    final match = template.regex.firstMatch(body)!;

    final record = normalizer.normalizeTemplateMatch(
      match: match,
      template: template,
      fallbackTimestamp: DateTime.utc(2023, 10, 10),
    );

    expect(record.evidence, isNotNull);
    expect(record.evidence!, isNotEmpty);
    expect(
      verifier.verify(
        body: body,
        evidence: record.evidence,
        record: record,
      ),
      isTrue,
    );
  });
}
