import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';

import '../support/fixture_loader.dart';

void main() {
  test('reports no cases for an empty fixture root', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'paisatrack_empty_fixtures_',
    );
    addTearDown(() async {
      await tempDir.delete(recursive: true);
    });

    final cases = await SmsFixtureRunner(root: tempDir).loadCases();

    expect(cases, isEmpty);
  });

  test('compares sample unparsed parser fixture', () async {
    final runner = SmsFixtureRunner(root: Directory('test/fixtures/sms'));
    final cases = await runner.loadCases();

    expect(cases.map((fixture) => fixture.id), contains('sample/unparsed'));

    final fixture = cases.singleWhere(
      (fixture) => fixture.id == 'sample/unparsed',
    );
    expect(fixture.provenance, FixtureProvenance.device);
    const cascade = ParserCascade(
      templateMatcher: TemplateMatcher(registries: []),
    );

    final actual = await parseFixtureCase(cascade, fixture);

    expect(actual, fixture.expected);
  });

  test('loads public provenance from optional fixture metadata', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'paisatrack_public_fixture_',
    );
    addTearDown(() async => tempDir.delete(recursive: true));
    final bankDir = await Directory('${tempDir.path}/public_bank').create();
    await File('${bankDir.path}/case.txt').writeAsString('Rs. 100 debited');
    await File('${bankDir.path}/case.expected.json').writeAsString('''
      {"sender":"XX-PUBLIC","received_at":0,"provenance":"public",
       "expected":{"err":"unparsed"}}
    ''');

    final cases = await SmsFixtureRunner(root: tempDir).loadCases();

    expect(cases.single.provenance, FixtureProvenance.public);
  });

  test('loads ordered sequence fixtures with expected event graphs', () async {
    final runner = SmsFixtureRunner(root: Directory('test/fixtures/sms'));
    final sequences = await runner.loadSequences();

    expect(sequences, hasLength(5));
    expect(
      sequences.map((sequence) => sequence.expectedGraph.edges.single.relation),
      containsAll(<String>[
        'auth_settles',
        'reverses',
        'refunds',
        'fulfils',
        'echoes',
      ]),
    );
    for (final sequence in sequences) {
      expect(sequence.provenance, FixtureProvenance.device);
      expect(sequence.messages, hasLength(2));
      expect(
        sequence.messages.first.receivedAt.isBefore(
          sequence.messages.last.receivedAt,
        ),
        isTrue,
      );
      expect(
        sequence.expectedGraph.nodes.map((node) => node.id),
        containsAll(sequence.messages.map((message) => message.id)),
      );
    }
  });

  test('loads adversarial fixtures without promoting bait to an amount',
      () async {
    final runner = SmsFixtureRunner(root: Directory('test/fixtures/sms'));
    final adversarial = await runner.loadAdversarial();

    expect(adversarial, hasLength(3));
    for (final fixture in adversarial) {
      expect(fixture.provenance, FixtureProvenance.device);
      expect(fixture.message.body, contains(fixture.bait));
      expect(fixture.expected['amount'], isNull);
      expect(fixture.expected['direction'], isNull);
    }
  });
}
