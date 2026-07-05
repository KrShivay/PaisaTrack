import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/core/result.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

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
