import 'dart:convert';

/// Evidence emitted by one parser/enricher for a persisted transaction field.
class ConfidenceTrailEntry {
  const ConfidenceTrailEntry({
    required this.value,
    required this.confidence,
    required this.source,
    this.ruleId,
    this.templateId,
    this.provenance,
  });

  final Object? value;
  final double? confidence;
  final String? source;
  final String? ruleId;
  final String? templateId;
  final String? provenance;

  factory ConfidenceTrailEntry.fromJson(Map<String, Object?> json) {
    return ConfidenceTrailEntry(
      value: json['v'],
      confidence: (json['c'] as num?)?.toDouble(),
      source: json['src'] as String?,
      ruleId: json['rule_id'] as String?,
      templateId: json['template_id'] as String?,
      provenance: json['provenance'] as String?,
    );
  }
}

/// Backward-compatible reader for the versionless `confidence_json` trail.
///
/// Unknown blocks are retained when they match the `{c,src,...}` shape, while
/// malformed JSON degrades to an empty trail. Legacy rows containing only a
/// parser block therefore remain readable with absent merchant/category data.
class TransactionConfidenceTrail {
  TransactionConfidenceTrail._(Map<String, ConfidenceTrailEntry> entries)
      : entries = Map.unmodifiable(entries);

  factory TransactionConfidenceTrail.fromJson(String source) {
    try {
      final decoded = jsonDecode(source) as Map<String, Object?>;
      final entries = <String, ConfidenceTrailEntry>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map) {
          entries[entry.key] = ConfidenceTrailEntry.fromJson(
            Map<String, Object?>.from(value),
          );
        }
      }
      return TransactionConfidenceTrail._(entries);
    } on FormatException {
      return TransactionConfidenceTrail._({});
    } on TypeError {
      return TransactionConfidenceTrail._({});
    }
  }

  final Map<String, ConfidenceTrailEntry> entries;

  ConfidenceTrailEntry? get parser => entries['parser'];
  ConfidenceTrailEntry? get merchant => entries['merchant'];
  ConfidenceTrailEntry? get category => entries['category'];
}
