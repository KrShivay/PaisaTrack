import 'dart:convert';
import 'dart:io';

import 'package:paisatrack/capture/parser_cascade.dart';
import 'package:paisatrack/core/result.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

/// Discovers sanitized SMS parser fixtures and compares parser output.
class SmsFixtureRunner {
  const SmsFixtureRunner({
    required this.root,
  });

  /// Directory containing bank folders such as `test/fixtures/sms/hdfc`.
  final Directory root;

  /// Loads every `<case>.txt` fixture that has a matching expected JSON file.
  ///
  /// A missing root reports no cases so empty fixture sets are clean in Phase 0.
  Future<List<SmsFixtureCase>> loadCases() async {
    if (!await root.exists()) {
      return const [];
    }

    final cases = <SmsFixtureCase>[];
    await for (final bankEntity in root.list()) {
      if (bankEntity is! Directory) {
        continue;
      }

      await for (final caseEntity in bankEntity.list()) {
        if (caseEntity is! File || !caseEntity.path.endsWith('.txt')) {
          continue;
        }

        cases.add(await _loadCase(bankEntity, caseEntity));
      }
    }

    cases.sort((a, b) => a.id.compareTo(b.id));
    return cases;
  }

  Future<SmsFixtureCase> _loadCase(
    Directory bankDirectory,
    File bodyFile,
  ) async {
    final expectedFile = File(
      bodyFile.path.replaceFirst(RegExp(r'\.txt$'), '.expected.json'),
    );
    if (!await expectedFile.exists()) {
      throw StateError('Missing expected fixture ${expectedFile.path}');
    }

    final metadata =
        jsonDecode(await expectedFile.readAsString()) as Map<String, Object?>;
    final bank = bankDirectory.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    final caseName = bodyFile.uri.pathSegments.last.replaceFirst(
      RegExp(r'\.txt$'),
      '',
    );

    return SmsFixtureCase(
      id: '$bank/$caseName',
      sender: metadata['sender']! as String,
      body: await bodyFile.readAsString(),
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        metadata['received_at']! as int,
        isUtc: true,
      ),
      provenance: FixtureProvenance.fromJson(metadata['provenance'] as String?),
      expected: (metadata['expected']! as Map<String, Object?>).cast(),
    );
  }
}

/// One sanitized SMS parser fixture and its expected parse result.
class SmsFixtureCase {
  const SmsFixtureCase({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.provenance,
    required this.expected,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final FixtureProvenance provenance;
  final Map<String, Object?> expected;

  RawSms toRawSms() {
    return RawSms(
      id: id,
      sender: sender,
      body: body,
      receivedAt: receivedAt,
    );
  }
}

/// Fixture evidence tier; missing legacy metadata remains device-grade.
enum FixtureProvenance {
  device,
  public;

  static FixtureProvenance fromJson(String? value) {
    return switch (value) {
      null || 'device' => FixtureProvenance.device,
      'public' => FixtureProvenance.public,
      _ => throw FormatException('Unsupported fixture provenance: $value'),
    };
  }
}

/// Runs one fixture through [cascade] and serializes the outcome for comparison.
Future<Map<String, Object?>> parseFixtureCase(
  ParserCascade cascade,
  SmsFixtureCase fixture,
) async {
  final result = await cascade.parse(fixture.toRawSms());
  return switch (result) {
    Ok<NormalizedTransactionRecord, ParseFailure>(:final value) => {
        'ok': value.toJson(),
      },
    Err<NormalizedTransactionRecord, ParseFailure>(:final error) => {
        'err': error.name,
      },
  };
}
