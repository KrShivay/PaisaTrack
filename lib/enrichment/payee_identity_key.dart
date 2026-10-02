/// Shared normalization for payee evidence and merchant aliases.
class PayeeIdentityKey {
  const PayeeIdentityKey._();

  /// Keeps the identity contract independent from punctuation and casing.
  static String normalize(String value) =>
      value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

  /// Matches two non-empty payee keys with the shared identity normalization.
  static bool matches(String left, String right) {
    final leftKey = normalize(left);
    return leftKey.isNotEmpty && leftKey == normalize(right);
  }
}

/// Normalized name and VPA keys used for deterministic payee resolution.
class PayeeKey {
  const PayeeKey({required this.vpaKey, required this.nameKey});

  /// Conservative token candidates for Ask's read-only VPA brand matching.
  /// Only the local part is considered; the PSP handle is never a brand.
  /// VPA local parts split on `.`, `_`, and `-`; raw merchant names also split
  /// on whitespace. Tokens must contain at least four letters and reject
  /// numeric, phone-like, and mixed letter/digit gateway IDs. If a VPA local
  /// part contains an opaque mixed token, its other tokens are omitted too
  /// (for example, `paytm.s22rtcb`). The only stripped prefix is `pay`,
  /// supported by the fixture VPA `payzomato@hdfcbank`; `payu` occurs as a
  /// separate gateway token in fixtures, so it is not stripped from words.
  static Set<String> brandTokens(String value) {
    final at = value.lastIndexOf('@');
    final local = at >= 0 ? value.substring(0, at) : value;
    final separators = at >= 0 ? RegExp(r'[._\-]+') : RegExp(r'[._\-\s]+');
    final tokens = local
        .toLowerCase()
        .split(separators)
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (tokens.any(_isOpaqueGatewayId)) return const {};

    final candidates = <String>{};
    for (final token in tokens) {
      _addBrandToken(candidates, token);
      if (token.startsWith('pay')) {
        _addBrandToken(candidates, token.substring('pay'.length));
      }
    }
    return candidates;
  }

  static void _addBrandToken(Set<String> candidates, String token) {
    if (token.length < 4 || !_hasLetters(token) || _isOpaqueGatewayId(token)) {
      return;
    }
    candidates.add(token);
  }

  static bool _hasLetters(String value) => RegExp(r'[a-z]').hasMatch(value);

  static bool _isOpaqueGatewayId(String token) =>
      _hasLetters(token) && RegExp(r'\d').hasMatch(token);

  /// Only the PSP's documented capture wrappers are removed: `UPI-`, `UPI/`,
  /// `VPS*`, and `POS ` at the start, plus the legal suffixes `LTD` and
  /// `LIMITED` at the end. Store numbers and city names are never guessed.
  factory PayeeKey.parse({String? name, String? vpa}) {
    final vpaKey = _normalizeVpa(vpa);
    var nameValue = (name ?? '').trim();
    nameValue = nameValue.toUpperCase().trim();
    for (final prefix in const ['UPI-', 'UPI/', 'VPS*', 'POS ']) {
      if (nameValue.startsWith(prefix)) {
        nameValue = nameValue.substring(prefix.length).trim();
        break;
      }
    }
    final suffix = RegExp(r'\s+(LTD|LIMITED)$');
    nameValue = nameValue.replaceFirst(suffix, '').trim();
    return PayeeKey(
      vpaKey: vpaKey,
      nameKey: PayeeIdentityKey.normalize(nameValue),
    );
  }

  final String vpaKey;
  final String nameKey;

  /// Returns the established storage key for either a VPA or a raw name.
  /// Name resolution may use [nameKey], which strips known capture wrappers;
  /// persisted aliases and evidence keep the pre-R2 normalization contract.
  static String keyFor(String value) => value.contains('@')
      ? PayeeKey.parse(vpa: value).vpaKey
      : PayeeIdentityKey.normalize(value);

  static String _normalizeVpa(String? value) {
    if (value == null || !value.contains('@')) return '';
    final separator = value.lastIndexOf('@');
    final local = value.substring(0, separator).trim();
    final psp = value.substring(separator + 1).trim();
    if (local.isEmpty || psp.isEmpty) return '';
    // Both components are retained, so ravi@ybl and ravi@okaxis stay apart.
    return PayeeIdentityKey.normalize('$local@$psp');
  }
}

/// Matches a complete payee word or phrase without accepting substrings.
/// Create once for a search phrase so its regular expression is reused for
/// every candidate row and evidence value.
class WholePhraseMatcher {
  WholePhraseMatcher(String phrase)
      : _phrase = phrase.trim(),
        _nameKey = PayeeKey.parse(name: phrase.trim()).nameKey,
        _pattern = RegExp(
          '(^|[^A-Z0-9])${RegExp.escape(phrase.trim().toUpperCase())}'
          '(\$|[^A-Z0-9])',
        );

  final String _phrase;
  final String _nameKey;
  final RegExp _pattern;

  bool matches(String value) {
    if (_phrase.isEmpty) return false;
    if (_nameKey.isNotEmpty &&
        {
          PayeeKey.keyFor(value),
          PayeeKey.parse(name: value).nameKey,
        }.contains(_nameKey)) {
      return true;
    }
    return _pattern.hasMatch(value.toUpperCase());
  }
}
