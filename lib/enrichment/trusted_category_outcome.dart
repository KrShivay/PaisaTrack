import 'dart:convert';

/// Shared provenance contract for category outcomes that may inform policy.
/// Keep this predicate strict: a category score alone is not provenance.
bool hasCategoryPredictionEvidence(String confidenceJson) {
  try {
    final payload = jsonDecode(confidenceJson) as Map<String, Object?>;
    final category = payload['category'] as Map<String, Object?>?;
    return category?['c'] is num && category?['src'] is String;
  } on FormatException {
    return false;
  } on TypeError {
    return false;
  }
}
