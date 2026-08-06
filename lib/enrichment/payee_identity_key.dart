/// Shared normalization for payee evidence and merchant aliases.
class PayeeIdentityKey {
  const PayeeIdentityKey._();

  /// Keeps the identity contract independent from punctuation and casing.
  static String normalize(String value) =>
      value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
}
