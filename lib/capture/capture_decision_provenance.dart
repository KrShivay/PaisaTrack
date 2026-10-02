import 'dart:convert';

enum CaptureDecisionStatusMode {
  policy('policy'),
  fixedReview('fixed_review');

  const CaptureDecisionStatusMode(this.wireName);

  final String wireName;

  static CaptureDecisionStatusMode? fromWireName(String? value) {
    for (final mode in values) {
      if (mode.wireName == value) return mode;
    }
    return null;
  }
}

/// Version marker for the category and initial-status capture decision.
///
/// This metadata identifies a decision contract. It is not a correctness label
/// and carries no source message content.
class CaptureDecisionProvenance {
  const CaptureDecisionProvenance({
    required this.version,
    required this.statusMode,
    required this.categorySource,
  });

  static const currentVersion = 'capture-decision-v2';
  static const _blockKey = 'capture_decision';
  static const _versionKey = 'version';
  static const _statusModeKey = 'status_mode';
  static const _categorySourceKey = 'category_source';

  final String version;
  final CaptureDecisionStatusMode statusMode;
  final String? categorySource;

  /// Adds the current contract version to a transaction confidence payload.
  static void writeCurrent(
    Map<String, Object?> payload, {
    required CaptureDecisionStatusMode statusMode,
    String? categorySource,
  }) {
    payload[_blockKey] = {
      _versionKey: currentVersion,
      _statusModeKey: statusMode.wireName,
      if (categorySource != null) _categorySourceKey: categorySource,
    };
  }

  /// Reads a supported decision version, leaving legacy and unknown rows null.
  static CaptureDecisionProvenance? fromConfidenceJson(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, Object?>) return null;
      final block = decoded[_blockKey];
      if (block is! Map<String, Object?>) return null;
      final version = block[_versionKey];
      final statusMode = CaptureDecisionStatusMode.fromWireName(
        block[_statusModeKey] as String?,
      );
      if (version != currentVersion || statusMode == null) return null;
      return CaptureDecisionProvenance(
        version: currentVersion,
        statusMode: statusMode,
        categorySource: block[_categorySourceKey] as String?,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static String? versionFromConfidenceJson(String? source) =>
      fromConfidenceJson(source)?.version;
}
