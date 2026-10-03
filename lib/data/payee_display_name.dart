import '../enrichment/payee_identity_key.dart';

/// Readable title for a transaction's payee (T-198). Display only: it never
/// merges identities or writes anything.
///
/// Order: the user's label, the merchant name, the SMS payee text, then a
/// brand derived from a VPA with the R4 [PayeeKey.brandTokens] rules, then
/// the VPA itself as stored (phone numbers and opaque gateway ids stay
/// as-is), the note, and [fallback]. A merchant name or payee text that is
/// itself a VPA counts as VPA-only.
String payeeDisplayName({
  String? userLabel,
  String? merchantName,
  String? merchantRaw,
  String? counterpartyVpa,
  String? description,
  String fallback = 'Unknown',
}) {
  String? present(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  final label = present(userLabel);
  if (label != null) return label;

  final vpas = <String>[];
  for (final name in [present(merchantName), present(merchantRaw)]) {
    if (name == null) continue;
    if (!name.contains('@')) return name;
    vpas.add(name);
  }
  final vpa = present(counterpartyVpa);
  if (vpa != null) vpas.insert(0, vpa);
  for (final candidate in vpas) {
    final brand = PayeeKey.displayBrand(candidate);
    if (brand != null) return brand;
  }
  if (vpas.isNotEmpty) return vpas.first;
  return present(description) ?? fallback;
}
