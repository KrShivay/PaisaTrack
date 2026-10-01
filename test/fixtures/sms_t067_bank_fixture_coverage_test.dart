import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';

import 'sms_fixture_runner.dart';

void main() {
  for (final bank in ['kotak', 'centbk']) {
    test('$bank has sourced public fixtures with >=90% exact coverage',
        () async {
      final directory = Directory('test/fixtures/sms/$bank');
      final fixtures = await SmsFixtureRunner(
        root: Directory('test/fixtures/sms'),
      ).loadCases();
      final bankFixtures = fixtures
          .where((fixture) => fixture.id.startsWith('$bank/'))
          .toList(growable: false);
      final positives = bankFixtures
          .where((fixture) => fixture.expected.containsKey('ok'))
          .toList(growable: false);

      expect(positives.length, greaterThanOrEqualTo(10));
      expect(
        bankFixtures.every((fixture) => fixture.provenance.name == 'public'),
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
        File('assets/templates/$bank.json').readAsStringSync(),
      );
      final cascade = fixtureParserCascade(registries: [registry]);
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
        reason: '$bank matched $matched/${positives.length}: $mismatches',
      );
    });
  }
}

bool _matchesExpected(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
) {
  // Older sourced fixtures don't include currency fields; focused tests check
  // the new fields while this coverage check retains its historical contract.
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
