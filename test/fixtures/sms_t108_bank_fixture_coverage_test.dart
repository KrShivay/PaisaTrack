import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';

import 'sms_fixture_runner.dart';

void main() {
  test('PNB has sourced public fixtures with >=90% exact coverage', () async {
    final directory = Directory('test/fixtures/sms/pnb');
    final fixtures = await SmsFixtureRunner(
      root: Directory('test/fixtures/sms'),
    ).loadCases();
    final positives = fixtures
        .where(
          (fixture) =>
              fixture.id.startsWith('pnb/') &&
              fixture.expected.containsKey('ok'),
        )
        .toList(growable: false);

    expect(positives.length, greaterThanOrEqualTo(7));
    expect(
      positives
          .every((fixture) => fixture.provenance == FixtureProvenance.public),
      isTrue,
    );

    for (final expectedFile in directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.expected.json'))) {
      final metadata =
          jsonDecode(expectedFile.readAsStringSync()) as Map<String, Object?>;
      expect(metadata['source_url'], isNotEmpty, reason: expectedFile.path);
    }

    final registry = TemplateRegistry.fromJson(
      File('assets/templates/pnb.json').readAsStringSync(),
    );
    final cascade = ParserCascade(
      templateMatcher: TemplateMatcher(registries: [registry]),
    );
    var matched = 0;
    final mismatches = <String>[];
    for (final fixture in positives) {
      final actual = await parseFixtureCase(cascade, fixture);
      if (_matchesExpected(actual, fixture.expected)) {
        matched++;
      } else {
        mismatches.add(
          '${fixture.id}: expected ${fixture.expected}, actual $actual',
        );
      }
    }

    expect(
      matched / positives.length,
      greaterThanOrEqualTo(0.9),
      reason: 'pnb matched $matched/${positives.length}: $mismatches',
    );
  });
}

bool _matchesExpected(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
) {
  // These public fixtures were authored before source-currency fields existed.
  return expected.entries.every((entry) {
    final actualValue = actual[entry.key];
    final expectedValue = entry.value;
    if (actualValue is Map && expectedValue is Map) {
      return expectedValue.entries.every(
        (field) => actualValue[field.key] == field.value,
      );
    }
    return actualValue == expectedValue;
  });
}
