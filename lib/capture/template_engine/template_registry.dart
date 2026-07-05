import 'dart:convert';

class TemplateRegistry {
  const TemplateRegistry({
    required this.senderPatterns,
    required this.templates,
  });

  final List<RegExp> senderPatterns;
  final List<SmsTemplate> templates;

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

  bool matchesSender(String sender) {
    return senderPatterns.any((pattern) => pattern.hasMatch(sender));
  }
}

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
