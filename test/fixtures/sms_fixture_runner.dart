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

  /// Loads ordered multi-message event-graph fixtures from [sequences.json].
  Future<List<SmsSequenceFixture>> loadSequences() async {
    final file = File('${root.path}/sequences.json');
    if (!await file.exists()) return const [];
    final document = jsonDecode(await file.readAsString());
    if (document is! Map || document['cases'] is! List) {
      throw const FormatException(
        'Sequence fixture catalogue must contain cases',
      );
    }
    return [
      for (final item in document['cases'] as List)
        SmsSequenceFixture.fromJson((item as Map).cast<String, Object?>()),
    ];
  }

  /// Loads extraction-bait fixtures from [adversarial.json].
  Future<List<SmsAdversarialFixture>> loadAdversarial() async {
    final file = File('${root.path}/adversarial.json');
    if (!await file.exists()) return const [];
    final document = jsonDecode(await file.readAsString());
    if (document is! Map || document['cases'] is! List) {
      throw const FormatException(
        'Adversarial fixture catalogue must contain cases',
      );
    }
    return [
      for (final item in document['cases'] as List)
        SmsAdversarialFixture.fromJson((item as Map).cast<String, Object?>()),
    ];
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

/// An ordered message sequence with the event graph expected from correlation.
class SmsSequenceFixture {
  const SmsSequenceFixture({
    required this.id,
    required this.provenance,
    required this.messages,
    required this.expectedGraph,
  });

  factory SmsSequenceFixture.fromJson(Map<String, Object?> json) {
    final graph = json['expected_graph'];
    if (graph is! Map) {
      throw const FormatException('Sequence fixture is missing expected_graph');
    }
    return SmsSequenceFixture(
      id: json['id']! as String,
      provenance: FixtureProvenance.fromJson(json['provenance'] as String?),
      messages: [
        for (final item in json['messages']! as List)
          SmsFixtureMessage.fromJson(item as Map<String, Object?>),
      ],
      expectedGraph: SmsEventGraph.fromJson(graph.cast<String, Object?>()),
    );
  }

  final String id;
  final FixtureProvenance provenance;
  final List<SmsFixtureMessage> messages;
  final SmsEventGraph expectedGraph;
}

/// An SMS where a plausible number is present but must not become an amount.
class SmsAdversarialFixture {
  const SmsAdversarialFixture({
    required this.id,
    required this.provenance,
    required this.message,
    required this.bait,
    required this.expected,
  });

  factory SmsAdversarialFixture.fromJson(Map<String, Object?> json) {
    return SmsAdversarialFixture(
      id: json['id']! as String,
      provenance: FixtureProvenance.fromJson(json['provenance'] as String?),
      message: SmsFixtureMessage.fromJson(
        (json['message']! as Map).cast<String, Object?>(),
      ),
      bait: json['bait']! as String,
      expected: (json['expected']! as Map).cast<String, Object?>(),
    );
  }

  final String id;
  final FixtureProvenance provenance;
  final SmsFixtureMessage message;
  final String bait;
  final Map<String, Object?> expected;
}

class SmsFixtureMessage {
  const SmsFixtureMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  factory SmsFixtureMessage.fromJson(Map<String, Object?> json) {
    return SmsFixtureMessage(
      id: json['id']! as String,
      sender: json['sender']! as String,
      body: json['body']! as String,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        json['received_at']! as int,
        isUtc: true,
      ),
    );
  }

  final String id;
  final String sender;
  final String body;
  final DateTime receivedAt;
}

class SmsEventGraph {
  const SmsEventGraph({required this.nodes, required this.edges});

  factory SmsEventGraph.fromJson(Map<String, Object?> json) {
    return SmsEventGraph(
      nodes: [
        for (final item in json['nodes']! as List)
          SmsEventNode.fromJson((item as Map).cast<String, Object?>()),
      ],
      edges: [
        for (final item in json['edges']! as List)
          SmsEventEdge.fromJson((item as Map).cast<String, Object?>()),
      ],
    );
  }

  final List<SmsEventNode> nodes;
  final List<SmsEventEdge> edges;
}

class SmsEventNode {
  const SmsEventNode({required this.id, required this.kind});

  factory SmsEventNode.fromJson(Map<String, Object?> json) {
    return SmsEventNode(
      id: json['id']! as String,
      kind: json['kind']! as String,
    );
  }

  final String id;
  final String kind;
}

class SmsEventEdge {
  const SmsEventEdge({
    required this.from,
    required this.to,
    required this.relation,
  });

  factory SmsEventEdge.fromJson(Map<String, Object?> json) {
    return SmsEventEdge(
      from: json['from']! as String,
      to: json['to']! as String,
      relation: json['relation']! as String,
    );
  }

  final String from;
  final String to;
  final String relation;
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
