import 'dart:convert';

/// Parsed collection of SMS templates scoped by sender patterns.
///
/// A registry usually maps to one template JSON asset for a bank, wallet, or
/// payment provider.
class TemplateRegistry {
  const TemplateRegistry({
    required this.senderPatterns,
    required this.templates,
  });

  final List<RegExp> senderPatterns;
  final List<SmsTemplate> templates;

  /// Parses a registry JSON document from `assets/templates`.
  static TemplateRegistry fromJson(String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    final senderPatterns = (json['sender_patterns'] as List<Object?>? ?? [])
        .cast<String>()
        .map(RegExp.new)
        .toList(growable: false);
    final templates = (json['templates'] as List<Object?>? ?? [])
        .cast<Map<String, Object?>>()
        .map(SmsTemplate.fromJson)
        .toList(growable: false);

    return TemplateRegistry(
      senderPatterns: senderPatterns,
      templates: templates,
    );
  }

  /// Whether this registry should be considered for an SMS sender ID.
  bool matchesSender(String sender) {
    return senderPatterns.any((pattern) => pattern.hasMatch(sender));
  }
}

/// One regex-backed SMS transaction pattern.
///
/// Regexes should expose named capture groups such as `amount`, `merchant`,
/// `account`, `balance`, `ref`, `vpa`, and `date` when those values are present.
class SmsTemplate {
  const SmsTemplate({
    required this.id,
    required this.regex,
    required this.direction,
    required this.channel,
    required this.dateFormat,
  });

  final String id;
  final RegExp regex;
  final String direction;
  final String channel;
  final String? dateFormat;

  /// Parses one template entry from registry JSON.
  static SmsTemplate fromJson(Map<String, Object?> json) {
    return SmsTemplate(
      id: json['id']! as String,
      regex: RegExp(json['regex']! as String, caseSensitive: false),
      direction: json['direction']! as String,
      channel: json['channel']! as String,
      dateFormat: json['date_format'] as String?,
    );
  }
}
