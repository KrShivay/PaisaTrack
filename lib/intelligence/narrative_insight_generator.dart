import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/constants.dart';
import '../data/db/database.dart';
import 'llm/llm_request.dart';
import 'llm/llm_runtime.dart';

/// Generates a qualitative monthly summary from aggregate insight JSON only.
class NarrativeInsightGenerator {
  const NarrativeInsightGenerator(
    this._database,
    this._runtime, {
    this.enabled = AppConstants.enableNarrativeInsights,
  });

  final AppDatabase _database;
  final LlmRuntime _runtime;
  final bool enabled;

  Future<bool> run({DateTime? today}) async {
    final now = (today ?? DateTime.now()).toUtc();
    final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final id = 'narrative:$period';
    if (!enabled) {
      await (_database.delete(_database.insights)
            ..where((row) => row.id.equals(id)))
          .go();
      return false;
    }

    final rows = await (_database.select(_database.insights)
          ..where(
            (row) =>
                row.period.equals(period) & row.kind.isNotValue('narrative'),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.id)]))
        .get();
    if (rows.isEmpty) return false;

    final aggregates = [
      for (final row in rows)
        {
          'kind': row.kind,
          'payload': _object(row.payloadJson),
        },
    ];
    final result = await _runtime.completeRequest(
      LlmRequest(
        systemInstruction:
            'Write one short, neutral observation about the supplied financial '
            'aggregates. Do not give advice. Do not include digits or currency '
            'amounts. Use only the supplied aggregate JSON.',
        userMessage: jsonEncode(aggregates),
        task: LlmTask.narrative,
      ),
    );
    if (result is! LlmSuccess<String>) return false;
    final body = result.value.trim();
    // Reject numbers so every displayed number continues to come from a
    // deterministic payload rather than model-authored prose.
    final containsDigit =
        RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9\u0966-\u096F]').hasMatch(body);
    final containsAdvice = RegExp(
      r'\b(should|recommend|consider|need to|try to)\b',
      caseSensitive: false,
    ).hasMatch(body);
    final containsThinking = body.toLowerCase().contains('<think>') ||
        body.toLowerCase().contains('</think>');
    if (body.isEmpty ||
        body.length > 280 ||
        containsDigit ||
        containsAdvice ||
        containsThinking) {
      return false;
    }
    final existing = await (_database.select(_database.insights)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    await _database.into(_database.insights).insertOnConflictUpdate(
          InsightsCompanion.insert(
            id: id,
            period: period,
            kind: 'narrative',
            payloadJson: jsonEncode({'body': body}),
            dismissed: Value(existing?.dismissed ?? false),
          ),
        );
    return true;
  }

  Map<String, Object?> _object(String source) {
    try {
      final decoded = jsonDecode(source);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}
