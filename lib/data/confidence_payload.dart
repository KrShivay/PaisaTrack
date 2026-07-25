import 'dart:convert';

/// Reads `parser.c` from a `confidence_json` payload, or null when absent/invalid.
///
/// Narrowly catches `FormatException` and `TypeError` to avoid swallowing `Error`s.
double? parseConfidenceFromJson(String? confidenceJson) {
  if (confidenceJson == null || confidenceJson.isEmpty) return null;
  try {
    final decoded = jsonDecode(confidenceJson);
    if (decoded is! Map<String, Object?>) return null;
    final parser = decoded['parser'];
    if (parser is! Map<String, Object?>) return null;
    final confidence = parser['c'];
    return (confidence as num?)?.toDouble();
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}
