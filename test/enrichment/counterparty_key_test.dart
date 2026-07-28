import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/enrichment/counterparty_key.dart';

void main() {
  const parser = CounterpartyKeyParser();

  group('CounterpartyKeyParser', () {
    test('parses P2P VPA with phone number and hashes phone without storing raw phone', () {
      final identity = parser.parse(vpa: '9876543210@paytm');
      expect(identity.kind, CounterpartyKind.person);
      expect(identity.identityKey, startsWith('PERSON_PHONE_'));
      expect(identity.identityKey.contains('9876543210'), isFalse);
      expect(identity.pspFamily, 'paytm');
    });

    test('strips trailing digits only when remaining core is a known PSP token', () {
      // paytm-9876543210@ptys -> paytm is a known PSP token -> keeps core 'paytm'
      final identity1 = parser.parse(vpa: 'paytm9876543210@ptys');
      expect(identity1.identityKey, 'MERCHANT_PAYTM');

      // john9876543210@ybl -> john is not a PSP token -> keeps john (person)
      final identity2 = parser.parse(vpa: 'john9876543210@ybl');
      expect(identity2.kind, CounterpartyKind.person);
    });

    test('recognizes QR merchant prefixes', () {
      final identity = parser.parse(vpa: 'PAYTMQR12345@paytm');
      expect(identity.kind, CounterpartyKind.merchant);
      expect(identity.identityKey, startsWith('MERCHANT_QR_'));
    });

    test('parses card descriptors stripping trailing store numbers and geography', () {
      final identity1 = parser.parse(merchantRaw: 'SWIGGY INSTAMART BANGALORE');
      expect(identity1.identityKey, 'MERCHANT_SWIGGYINSTAMART');

      final identity2 = parser.parse(merchantRaw: 'RELIANCE SMART 4471');
      expect(identity2.identityKey, 'MERCHANT_RELIANCESMART');
    });
  });
}
