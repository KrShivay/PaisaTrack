import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';

import 'sms_fixture_runner.dart';

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
}
