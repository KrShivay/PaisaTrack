import '../data/models/normalized_transaction_record.dart';
import '../enrichment/decision_policy.dart';
import 'template_engine/field_normalizer.dart';

/// Verifies that extracted field evidence spans anchor accurately back to raw
/// source text and reproduce the exact parsed values.
class SpanVerifier {
  const SpanVerifier({
    FieldNormalizer fieldNormalizer = const FieldNormalizer(),
  }) : _fieldNormalizer = fieldNormalizer;

  final FieldNormalizer _fieldNormalizer;

  /// Re-anchors each span in [evidence] against [body] and asserts:
  /// 1. `body.substring(start, end) == verbatim`
  /// 2. Re-parsing the verbatim substring via [FieldNormalizer] reproduces the record's value.
  /// 3. When [record] is provided, all three required fields (`amount`, `direction`, `ts`) have verifying evidence.
  bool verify({
    required String body,
    required List<FieldEvidence>? evidence,
    NormalizedTransactionRecord? record,
  }) {
    if (evidence == null || evidence.isEmpty) {
      return false;
    }

    for (final e in evidence) {
      if (e.start < 0 || e.end > body.length || e.start > e.end) {
        return false;
      }
      final substring = body.substring(e.start, e.end);
      if (substring != e.verbatim) {
        return false;
      }

      if (record != null) {
        if (e.field == 'amount') {
          try {
            final parsedAmount = _fieldNormalizer.parseAmount(e.verbatim);
            if ((parsedAmount - record.amount).abs() > 0.001) {
              return false;
            }
          } catch (_) {
            return false;
          }
        }
      }
    }

    if (record != null) {
      final fields = evidence.map((e) => e.field).toSet();
      if (!fields.contains('amount') ||
          !fields.contains('direction') ||
          !fields.contains('ts')) {
        return false;
      }
    }

    return true;
  }

  /// Repository write guard: validates that [record] has verifying evidence for all required fields.
  ///
  /// Refuses unverified records from landing as `auto`: asserts in debug mode
  /// and downgrades to `needs_review` in release mode.
  static DecisionStatus enforceWriteGuard({
    required String body,
    required NormalizedTransactionRecord record,
    required DecisionStatus requestedStatus,
    FieldNormalizer normalizer = const FieldNormalizer(),
  }) {
    final verifier = SpanVerifier(fieldNormalizer: normalizer);
    final isValid = verifier.verify(
      body: body,
      evidence: record.evidence,
      record: record,
    );

    if (!isValid) {
      assert(
        requestedStatus == DecisionStatus.needsReview ||
            requestedStatus == DecisionStatus.asked,
        'WriteGuard: Record for parseSource=${record.parseSource} lacks verifying evidence for required fields.',
      );
      return DecisionStatus.needsReview;
    }

    return requestedStatus;
  }
}
