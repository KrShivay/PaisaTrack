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
