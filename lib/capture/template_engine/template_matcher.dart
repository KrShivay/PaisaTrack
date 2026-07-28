import '../../core/constants.dart';
import '../../data/models/normalized_transaction_record.dart';
import '../../data/models/raw_sms.dart';
import 'field_normalizer.dart';
import 'template_registry.dart';
import 'template_trust_ledger.dart';

/// Finds the first sender/template pair that recognizes an incoming SMS.
///
/// Registries are evaluated in caller-provided order, so more specific sender
/// patterns should appear before broad catch-all patterns.
class TemplateMatcher {
  const TemplateMatcher({
    required List<TemplateRegistry> registries,
    FieldNormalizer normalizer = const FieldNormalizer(),
    TemplateTrustLedger? trustLedger,
  })  : _registries = registries,
        _normalizer = normalizer,
        _trustLedger = trustLedger;

  final List<TemplateRegistry> _registries;
  final FieldNormalizer _normalizer;
  final TemplateTrustLedger? _trustLedger;

  /// Returns a normalized record when any configured template matches [sms].
  ///
  /// Returns `null` for expected misses so [ParserCascade] can try later
  /// strategies without treating the SMS as exceptional.
  Future<NormalizedTransactionRecord?> match(RawSms sms) async {
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
          if (template.provenance != TemplateProvenance.public) return record;
          final confidence = await _trustLedger?.confidenceForTemplate(
                template.id,
              ) ??
              AppConstants.defaultTemplateConfidence;
          return record.withParseConfidence(confidence);
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
