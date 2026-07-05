import '../../data/models/normalized_transaction_record.dart';
import '../../data/models/raw_sms.dart';
import 'field_normalizer.dart';
import 'template_registry.dart';

class TemplateMatcher {
  const TemplateMatcher({
    required List<TemplateRegistry> registries,
    FieldNormalizer normalizer = const FieldNormalizer(),
  })  : _registries = registries,
        _normalizer = normalizer;

  final List<TemplateRegistry> _registries;
  final FieldNormalizer _normalizer;

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

        return _normalizer.normalizeTemplateMatch(
          match: match,
          template: template,
          fallbackTimestamp: sms.receivedAt,
        );
      }
    }

    return null;
  }
}
