import 'dart:convert';

/// Bundled merchant-keyword → category-id map (assets/seed/category_seed.json),
/// step 3 of the categorizer ladder (PLAN §7.4).
///
/// Keys are matched case-insensitively as substrings of the merchant text
/// (or VPA), longest key first so more specific entries (e.g. `hdfc ergo`)
/// win over shorter overlapping ones.
class SeedCategoryMap {
  SeedCategoryMap(Map<String, String> entries)
      : _entries = {
          for (final entry in entries.entries)
            entry.key.toLowerCase().trim(): entry.value,
        } {
    _keysByLength = _entries.keys.toList(growable: false)
      ..sort((a, b) => b.length.compareTo(a.length));
  }

  factory SeedCategoryMap.fromJson(String source) {
    final decoded = jsonDecode(source) as Map<String, Object?>;
    return SeedCategoryMap(decoded.cast<String, String>());
  }

  final Map<String, String> _entries;
  late final List<String> _keysByLength;

  /// Category id for the first (longest) seed key contained in [text],
  /// or null when nothing matches.
  String? categoryFor(String? text) {
    if (text == null || text.isEmpty) return null;
    final haystack = text.toLowerCase();
    for (final key in _keysByLength) {
      if (haystack.contains(key)) return _entries[key];
    }
    return null;
  }
}
