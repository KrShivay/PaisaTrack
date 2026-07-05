import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
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
}
