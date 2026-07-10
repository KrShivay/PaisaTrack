import '../../data/models/normalized_transaction_record.dart';
import '../../data/models/raw_sms.dart';
import 'field_normalizer.dart';
import 'template_registry.dart';

/// Finds the first sender/template pair that recognizes an incoming SMS.
///
/// Registries are evaluated in caller-provided order, so more specific sender
/// patterns should appear before broad catch-all patterns.
class TemplateMatcher {
  const TemplateMatcher({
    required List<TemplateRegistry> registries,
    FieldNormalizer normalizer = const FieldNormalizer(),
  })  : _registries = registries,
        _normalizer = normalizer;

  final List<TemplateRegistry> _registries;
  final FieldNormalizer _normalizer;

  /// Returns a normalized record when any configured template matches [sms].
  ///
  /// Returns `null` for expected misses so [ParserCascade] can try later
  /// strategies without treating the SMS as exceptional.
  NormalizedTransactionRecord? match(RawSms sms) {
    for (final registry in _registries) {
      if (!registry.matchesSender(sms.sender)) {
        continue;
      }

      for (final template in registry.templates) {
        final match = template.regex.firstMatch(sms.body);
        if (match == null) {
          continue;
        }

        try {
          final record = _normalizer.normalizeTemplateMatch(
            match: match,
            template: template,
            fallbackTimestamp: sms.receivedAt,
          );
          // Public fixtures are useful coverage, but without device/statement
          // evidence they must never enter the silent auto-label band (ADR 0005).
          return template.provenance == TemplateProvenance.public
              ? record.withParseConfidence(0.85)
              : record;
        } on FormatException {
          continue;
        } on ArgumentError {
          continue;
        }
      }
    }

    return null;
  }
}
