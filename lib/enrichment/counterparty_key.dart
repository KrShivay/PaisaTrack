/// Counterparty identity classification (T-136a).
enum CounterpartyKind {
  person('person'),
  merchant('merchant'),
  institution('institution'),
  self('self'),
  unknown('unknown');

  const CounterpartyKind(this.wireName);
  final String wireName;
}

/// Parsed counterparty identity key and metadata.
class CounterpartyIdentity {
  const CounterpartyIdentity({
    required this.identityKey,
    required this.kind,
    this.displayName,
    this.inferredName,
    this.pspFamily,
  });

  final String identityKey;
  final CounterpartyKind kind;
  final String? displayName;
  final String? inferredName;
  final String? pspFamily;
}

/// Structured identity parser for VPAs, QR prefixes, phone numbers, and card descriptors.
class CounterpartyKeyParser {
  const CounterpartyKeyParser();

  static const _knownPspTokens = {
    'paytm',
    'ybl',
    'upi',
    'okaxis',
    'ibl',
    'axl',
    'okicici',
    'oksbi',
    'barodampay',
    'idfcbank',
    'postbank',
  };

  static const _qrPrefixes = [
    'PAYTMQR',
    'BHARATPE',
    'Q',
    'MERCHANT',
    'MAB',
  ];

  /// Hashes phone numbers to prevent raw phone storage in keys.
  static String hashPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    var hash = 0x811c9dc5;
    for (var i = 0; i < cleaned.length; i++) {
      hash ^= cleaned.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Parses raw VPA or merchant text into a structured identity.
  CounterpartyIdentity parse({
    String? vpa,
    String? merchantRaw,
  }) {
    if (vpa != null && vpa.contains('@')) {
      final parts = vpa.split('@');
      final localPart = parts[0].trim();
      final psp = parts[1].toLowerCase().trim();

      // 1. Check trailing digits: strip digit run >= 6 ONLY if remaining core is a known PSP token
      var core = localPart.toLowerCase();
      final trailingDigitMatch = RegExp(r'^(.*?)(\d{6,})$').firstMatch(core);
      if (trailingDigitMatch != null) {
        final prefix = trailingDigitMatch.group(1)!;
        if (_knownPspTokens.contains(prefix)) {
          core = prefix; // Known PSP token -> keep core (e.g., paytm-9876543210 -> paytm)
        }
      }

      // 2. Check aggregator QR prefix
      final upperCore = core.toUpperCase();
      final isQrMerchant = _qrPrefixes.any((prefix) => upperCore.startsWith(prefix));
      if (isQrMerchant) {
        return CounterpartyIdentity(
          identityKey: 'MERCHANT_QR_${upperCore.replaceAll(RegExp(r'[^A-Z0-9]'), '')}',
          kind: CounterpartyKind.merchant,
          pspFamily: psp,
        );
      }

      // 3. Check if core is a known PSP token
      if (_knownPspTokens.contains(core)) {
        return CounterpartyIdentity(
          identityKey: 'MERCHANT_${upperCore.replaceAll(RegExp(r'[^A-Z0-9]'), '')}',
          kind: CounterpartyKind.merchant,
          pspFamily: psp,
        );
      }

      // 4. Check if local part contains a phone number (>= 10 digits)
      final phoneMatch = RegExp(r'\d{10,}').firstMatch(localPart);
      if (phoneMatch != null || RegExp(r'^\d{10,}$').hasMatch(localPart)) {
        final phoneHash = hashPhone(localPart);
        return CounterpartyIdentity(
          identityKey: 'PERSON_PHONE_$phoneHash',
          kind: CounterpartyKind.person,
          pspFamily: psp,
        );
      }

      final isKnownMerchantToken = _knownPspTokens.contains(core);
      final kind = isKnownMerchantToken ? CounterpartyKind.merchant : CounterpartyKind.unknown;
      return CounterpartyIdentity(
        identityKey: '${isKnownMerchantToken ? 'MERCHANT' : 'VPA'}_${upperCore.replaceAll(RegExp(r'[^A-Z0-9]'), '')}',
        kind: kind,
        inferredName: localPart,
        pspFamily: psp,
      );
    }

    if (merchantRaw != null && merchantRaw.isNotEmpty) {
      // Card descriptor: strip trailing store numbers & city names
      var normalized = merchantRaw.toUpperCase().trim();
      normalized = normalized.replaceAll(RegExp(r'\s+\d{3,}\b'), ''); // Strip trailing store numbers (e.g. 4471)
      normalized = normalized.replaceAll(RegExp(r'\s+(BANGALORE|MUMBAI|DELHI|GURGAON|HYDERABAD|CHENNAI|KOLKATA|PUNE)\b'), ''); // Strip trailing city
      final cleanKey = normalized.replaceAll(RegExp(r'[^A-Z0-9]'), '');

      return CounterpartyIdentity(
        identityKey: 'MERCHANT_$cleanKey',
        kind: CounterpartyKind.merchant,
        displayName: merchantRaw.trim(),
      );
    }

    return const CounterpartyIdentity(
      identityKey: 'UNKNOWN',
      kind: CounterpartyKind.unknown,
    );
  }
}
