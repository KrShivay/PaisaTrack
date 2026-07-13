import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
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
      final cascade = ParserCascade(
        templateMatcher: TemplateMatcher(registries: [registry]),
      );
      var matched = 0;
      final mismatches = <String>[];
      for (final fixture in positives) {
        final actual = await parseFixtureCase(cascade, fixture);
        if (jsonEncode(actual) == jsonEncode(fixture.expected)) {
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
