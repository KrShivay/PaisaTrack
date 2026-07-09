import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';

import 'sms_fixture_runner.dart';

/// Loads every registry committed under `assets/templates/`.
///
/// Fixture coverage tests read templates straight off disk (rather than via
/// `rootBundle`) so they exercise the exact JSON that ships in the app without
/// requiring widget test bindings.
List<TemplateRegistry> _loadRegistries() {
  final dir = Directory('assets/templates');
  return dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .map((file) => TemplateRegistry.fromJson(file.readAsStringSync()))
      .toList(growable: false);
}

void main() {
  final cascade = ParserCascade(
    templateMatcher: TemplateMatcher(registries: _loadRegistries()),
  );

  test('declined/failed/future-event SMS never produce a transaction',
      () async {
    final cases = await SmsFixtureRunner(
      root: Directory('test/fixtures/sms'),
    ).loadCases();
    final negativeCases =
        cases.where((fixture) => fixture.expected.containsKey('err'));

    expect(negativeCases, isNotEmpty);
    for (final fixture in negativeCases) {
      final actual = await parseFixtureCase(cascade, fixture);
      expect(
        actual,
        fixture.expected,
        reason: 'fixture ${fixture.id} must parse to err, not a transaction',
      );
    }
  });

  test(
      '>=90% of real per-bank transactional SMS parse into the correct '
      'NormalizedTransactionRecord', () async {
    final cases = await SmsFixtureRunner(
      root: Directory('test/fixtures/sms'),
    ).loadCases();
    final positiveCases =
        cases.where((fixture) => fixture.expected.containsKey('ok')).toList();

    expect(positiveCases, isNotEmpty);

    final byBank = <String, List<SmsFixtureCase>>{};
    for (final fixture in positiveCases) {
      final bank = fixture.id.split('/').first;
      byBank.putIfAbsent(bank, () => []).add(fixture);
    }

    for (final entry in byBank.entries) {
      var matched = 0;
      final mismatches = <String>[];
      for (final fixture in entry.value) {
        final actual = await parseFixtureCase(cascade, fixture);
        if (jsonEncode(actual) == jsonEncode(fixture.expected)) {
          matched++;
        } else {
          mismatches.add(fixture.id);
        }
      }

      final ratio = matched / entry.value.length;
      expect(
        ratio,
        greaterThanOrEqualTo(0.9),
        reason: '${entry.key}: only $matched/${entry.value.length} '
            'parsed correctly; mismatches: $mismatches',
      );
    }
  });

  test(
      'generic fallback parses >=80% of positive fixtures without '
      'contradicting amount, direction, or account hint', () async {
    const genericOnly = ParserCascade(
      templateMatcher: TemplateMatcher(registries: []),
    );
    final cases = await SmsFixtureRunner(
      root: Directory('test/fixtures/sms'),
    ).loadCases();
    final positives =
        cases.where((fixture) => fixture.expected.containsKey('ok'));
    var parsed = 0;
    final misses = <String>[];

    for (final fixture in positives) {
      final actual = await parseFixtureCase(genericOnly, fixture);
      final record = actual['ok'] as Map<String, Object?>?;
      if (record == null) {
        misses.add(fixture.id);
        continue;
      }
      parsed++;
      final expected = fixture.expected['ok']! as Map<String, Object?>;
      for (final key in ['amount', 'direction', 'account_hint']) {
        final expectedValue = expected[key];
        if (expectedValue != null && record[key] != null) {
          expect(record[key], expectedValue, reason: '${fixture.id}: $key');
        }
      }
      expect(record['parse_source'], 'generic');
      expect(record['parse_confidence'], lessThanOrEqualTo(0.6));
    }

    expect(
      parsed / positives.length,
      greaterThanOrEqualTo(0.8),
      reason:
          'generic fallback parsed only $parsed/${positives.length}; misses: $misses',
    );
  });
}
