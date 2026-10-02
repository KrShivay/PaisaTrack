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
