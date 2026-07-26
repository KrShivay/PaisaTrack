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
    this.provenance = TemplateProvenance.device,
  });

  final String id;
  final RegExp regex;
  final String direction;
  final String channel;
  final String? dateFormat;

  /// Evidence tier for this template's fixture source (ADR 0005).
  final TemplateProvenance provenance;

  static const _supportedDateFormats = {
    'ddMMMyy',
    'dd-MM-yy',
    'dd/MM/yy',
    'dd-MM-yyyy',
    'dd/MM/yyyy',
    'dd-MMM-yy',
    'dd/MMM/yy',
  };

  /// Parses one template entry from registry JSON.
  static SmsTemplate fromJson(Map<String, Object?> json) {
    final dateFormat = json['date_format'] as String?;
    if (dateFormat != null && !_supportedDateFormats.contains(dateFormat)) {
      throw FormatException('Unsupported date_format: $dateFormat');
    }
    return SmsTemplate(
      id: json['id']! as String,
      regex: RegExp(json['regex']! as String, caseSensitive: false),
      direction: json['direction']! as String,
      channel: json['channel']! as String,
      dateFormat: dateFormat,
      provenance: TemplateProvenance.fromJson(json['provenance'] as String?),
    );
  }
}

/// Evidence source for a template's fixture-backed parser contract.
enum TemplateProvenance {
  /// A sanitized, statement-reconcilable device fixture (gold tier).
  device,

  /// A publicly posted fixture that must remain in the review band (silver).
  public;

  /// Stable JSON value used by templates and fixture metadata.
  String get wireName => name;

  /// Missing provenance predates ADR 0005 and is intentionally device-grade.
  static TemplateProvenance fromJson(String? value) {
    return switch (value) {
      null || 'device' => TemplateProvenance.device,
      'public' => TemplateProvenance.public,
      _ => throw FormatException('Unsupported template provenance: $value'),
    };
  }
}
