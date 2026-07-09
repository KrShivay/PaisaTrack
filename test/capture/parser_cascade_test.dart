import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
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

  for (final body in [
    'Your OTP is 123456. Do not share it.',
    'Get Rs. 500 cashback with this limited offer.',
    'Your card bill of Rs. 1200 is due on 20-07-26.',
    'Your account statement is ready. Balance Rs. 1200.',
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
