import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/span_verifier.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/core/result.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';
import 'package:paisatrack/enrichment/decision_policy.dart';

void main() {
  test('returns unparsed when no template registries exist', () async {
    const cascade = ParserCascade(
      templateMatcher: TemplateMatcher(registries: []),
    );

    final result = await cascade.parse(
      RawSms(
        id: 'sms-1',
        sender: 'XX-HDFCBK',
        body: 'sanitized transactional sms',
        receivedAt: DateTime.utc(2026, 7, 5),
      ),
    );

    expect(result, isA<Err>());
    expect((result as Err).error, ParseFailure.unparsed);
  });

  test('uses a generic parse after a template miss', () async {
    const cascade = ParserCascade(
      templateMatcher: TemplateMatcher(registries: []),
    );
    final result = await cascade.parse(
      RawSms(
        id: 'generic-1',
        sender: 'XX-NEWBANK',
        body: 'Rs. 250.00 debited from A/c XX1234 via UPI to SANITIZED SHOP. '
            'Avl Bal: Rs. 1,000.00 Ref: ABCDEF123',
        receivedAt: DateTime.utc(2026, 7, 10),
      ),
    );

    final record = (result as Ok).value;
    expect(record.amount, 250);
    expect(record.direction, TransactionDirection.debit);
    expect(record.accountHint, 'xx1234');
    expect(record.channel, TransactionChannel.upi);
    expect(record.balanceAfter, 1000);
    expect(record.refId, 'ABCDEF123');
    expect(record.parseSource, ParseSource.generic);
    expect(record.parseConfidence, lessThanOrEqualTo(0.6));
  });

  test('parses INR, Rs, and rupee payment wording after template miss',
      () async {
    const cascade = ParserCascade(
      templateMatcher: TemplateMatcher(registries: []),
    );
    const examples = <({String body, double amount})>[
      (
        body: 'Your UPI payment of INR 1,250.50 was debited from A/C XX1234 '
            'to SANITIZED SHOP',
        amount: 1250.5,
      ),
      (
        body: 'Rs. 245.00 was paid from A/C XX2345 via card at SANITIZED STORE',
        amount: 245,
      ),
      (
        body: '₹350.00 withdrawn from A/C XX3456 by ATM',
        amount: 350,
      ),
    ];

    for (final example in examples) {
      final result = await cascade.parse(
        RawSms(
          id: 'synthetic-${example.amount}',
          sender: 'VK-HDFCBK',
          body: example.body,
          receivedAt: DateTime.utc(2026, 7, 10),
        ),
      );
      final record = (result as Ok).value;

      expect(record.amount, example.amount);
      expect(record.direction, TransactionDirection.debit);
      expect(record.parseSource, ParseSource.generic);
      expect(record.parseConfidence, lessThanOrEqualTo(0.6));
      expect(
        const SpanVerifier().verify(
          body: example.body,
          evidence: record.evidence,
          record: record,
        ),
        isTrue,
      );
    }
  });

  test('template parse takes precedence over the generic fallback', () async {
    final cascade = ParserCascade(
      templateMatcher: TemplateMatcher(
        registries: [
          TemplateRegistry(
            senderPatterns: [RegExp(r'^XX-BANK$')],
            templates: [
              SmsTemplate(
                id: 'template_wins',
                regex: RegExp(r'Rs\. (?<amount>\d+) debited'),
                direction: 'debit',
                channel: 'upi',
                dateFormat: null,
              ),
            ],
          ),
        ],
      ),
    );

    final result = await cascade.parse(
      RawSms(
        id: 'precedence-1',
        sender: 'XX-BANK',
        body: 'Rs. 250 debited from A/c XX1234 via UPI',
        receivedAt: DateTime.utc(2026, 7, 10),
      ),
    );

    expect((result as Ok).value.parseSource, ParseSource.template);
  });

  test('generic confidence never produces an automatic decision', () {
    const policy = DecisionPolicy();
    for (final confidence in [0.5, 0.6]) {
      expect(
        policy.decide(
          DecisionPolicyInput(
            merchantConfidence: confidence,
            categoryConfidence: confidence,
            amount: 100,
            merchantTxnCount: 0,
            askBudgetLeft: 2,
          ),
        ),
        isNot(DecisionStatus.auto),
      );
    }
  });

  test('public template confidence is capped below silent auto-labeling',
      () async {
    final cascade = ParserCascade(
      templateMatcher: TemplateMatcher(
        registries: [
          TemplateRegistry(
            senderPatterns: [RegExp(r'^XX-PUBLIC$')],
            templates: [
              SmsTemplate(
                id: 'public_debit_v1',
                regex: RegExp(r'Rs\. (?<amount>\d+) debited'),
                direction: 'debit',
                channel: 'upi',
                dateFormat: null,
                provenance: TemplateProvenance.public,
              ),
            ],
          ),
        ],
      ),
    );

    final result = await cascade.parse(
      RawSms(
        id: 'public-1',
        sender: 'XX-PUBLIC',
        body: 'Rs. 250 debited from A/c XX1234 via UPI',
        receivedAt: DateTime.utc(2026, 7, 10),
      ),
    );
    final record = (result as Ok).value;

    expect(record.parseConfidence, 0.85);
    expect(record.templateId, 'public_debit_v1');
    expect(record.templateProvenance, 'public');
    expect(
      const DecisionPolicy().decide(
        DecisionPolicyInput(
          merchantConfidence: record.parseConfidence,
          categoryConfidence: 1,
          amount: 1000,
          merchantTxnCount: 10,
          askBudgetLeft: 2,
        ),
      ),
      isNot(DecisionStatus.auto),
    );
  });

  for (final body in [
    'Your OTP is 123456. Do not share it.',
    'Get Rs. 500 cashback with this limited offer.',
    'Your card bill of Rs. 1200 is due on 20-07-26.',
    'Your account statement is ready. Balance Rs. 1200.',
    'Available balance is INR 1,000.00 for A/c XX1234',
    'Transaction of INR 500 on card XX1234 has been declined',
    'A/c XX1234 failed for Rs. 500.00 via UPI',
    'Reversal of INR 300.00 credited back to A/c XX1234',
  ]) {
    test('generic fallback rejects non-transaction SMS: $body', () async {
      const cascade = ParserCascade(
        templateMatcher: TemplateMatcher(registries: []),
      );

      final result = await cascade.parse(
        RawSms(
          id: body,
          sender: 'XX-NEWBANK',
          body: body,
          receivedAt: DateTime.utc(2026, 7, 10),
        ),
      );

      expect(result, isA<Err>());
    });
  }

  for (final malformedCase in const <_MalformedTemplateCase>[
    _MalformedTemplateCase(
      description: 'non-positive amount',
      body: 'txn amount 0 on 05-07-26',
    ),
    _MalformedTemplateCase(
      description: 'garbage amount',
      body: 'txn amount bananas on 05-07-26',
    ),
    _MalformedTemplateCase(
      description: 'non-numeric date',
      body: 'txn amount 45 on aa-07-26',
    ),
    _MalformedTemplateCase(
      description: 'invalid direction',
      body: 'txn amount 45 on 05-07-26',
      direction: 'outflow',
    ),
  ]) {
    test(
      'returns unparsed for matched template with ${malformedCase.description}',
      () async {
        final cascade = ParserCascade(
          templateMatcher: TemplateMatcher(
            registries: [
              TemplateRegistry(
                senderPatterns: [RegExp(r'^XX-BANK$')],
                templates: [
                  SmsTemplate(
                    id: 'malformed_${malformedCase.description}',
                    regex: RegExp(
                      r'txn amount (?<amount>\S+) on (?<date>\S+)',
                      caseSensitive: false,
                    ),
                    direction: malformedCase.direction,
                    channel: 'upi',
                    dateFormat: 'dd-MM-yy',
                  ),
                ],
              ),
            ],
          ),
        );

        final result = await cascade.parse(
          RawSms(
            id: 'sms-malformed',
            sender: 'XX-BANK',
            body: malformedCase.body,
            receivedAt: DateTime.utc(2026, 7, 5),
          ),
        );

        expect(result, isA<Err>());
        expect((result as Err).error, ParseFailure.unparsed);
      },
    );
  }
}

class _MalformedTemplateCase {
  const _MalformedTemplateCase({
    required this.description,
    required this.body,
    this.direction = 'debit',
  });

  final String description;
  final String body;
  final String direction;
}
