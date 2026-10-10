import 'dart:convert';

/// Bundled merchant-keyword → category-id map (assets/seed/category_seed.json),
/// step 3 of the categorizer ladder (PLAN §7.4).
///
/// Matching is token-aware rather than raw-substring so a short brand cannot
/// misfile an unrelated word (`lic` must not match `public`, `ola` must not
/// match `coca cola`):
///
/// - Text and keys are lowercased and every run of non-alphanumeric
///   characters becomes one space (`jio-fiber`, `JIO FIBER` and `jio.fiber`
///   are equal).
/// - A key must start at a token boundary.
/// - Keys shorter than [_looseSuffixMinLength] characters must also end at a
///   token boundary; longer keys may be a token prefix (`bigbasket` matches
///   `bigbasketinnovative`).
/// - The longest matching key wins, so specific entries (`hdfc ergo`,
///   `urban company salon`) beat shorter overlapping ones.
///
/// There is no fuzzy or edit-distance matching.
class SeedCategoryMap {
  SeedCategoryMap(Map<String, String> entries)
      : _entries = {
          for (final entry in entries.entries)
            _normalize(entry.key): entry.value,
        }..remove('') {
    _keysByLength = _entries.keys.toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));
  }

  factory SeedCategoryMap.fromJson(String source) {
    final decoded = jsonDecode(source) as Map<String, Object?>;
    return SeedCategoryMap(decoded.cast<String, String>());
  }

  static const _looseSuffixMinLength = 6;

  final Map<String, String> _entries;
  late final List<String> _keysByLength;

  /// Every category id this map can return (for consistency checks).
  Iterable<String> get categoryIds => _entries.values;

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// Category id for the first (longest) seed key found in [text] at a token
  /// boundary, or null when nothing matches.
  String? categoryFor(String? text) {
    if (text == null || text.isEmpty) return null;
    final normalized = _normalize(text);
    if (normalized.isEmpty) return null;
    final haystack = ' $normalized ';
    for (final key in _keysByLength) {
      final needle = ' $key';
      final strictEnd = key.length < _looseSuffixMinLength;
      var from = 0;
      while (true) {
        final index = haystack.indexOf(needle, from);
        if (index < 0) break;
        final end = index + needle.length;
        if (!strictEnd || haystack[end] == ' ') return _entries[key];
        from = index + 1;
      }
    }
    return null;
  }
}
