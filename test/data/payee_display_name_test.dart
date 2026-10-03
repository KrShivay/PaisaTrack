import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/payee_display_name.dart';

void main() {
  group('payeeDisplayName', () {
    test('owner examples derive a readable brand from VPA-only rows', () {
      expect(payeeDisplayName(counterpartyVpa: 'payzomato@hdfcbank'), 'Zomato');
      expect(
        payeeDisplayName(
          merchantRaw: 'zomato.eternaltsp.payu@hdfcbank',
          counterpartyVpa: 'zomato.eternaltsp.payu@hdfcbank',
        ),
        'Zomato',
      );
      // A merchant created from a VPA keeps the VPA as its canonical name.
      expect(
        payeeDisplayName(merchantName: 'payzomato@hdfcbank'),
        'Zomato',
      );
    });

    test('opaque gateway ids and phone VPAs stay as stored', () {
      expect(
        payeeDisplayName(counterpartyVpa: 'paytm.s22rtcb@pty'),
        'paytm.s22rtcb@pty',
      );
      expect(
        payeeDisplayName(counterpartyVpa: '9876543210@ybl'),
        '9876543210@ybl',
      );
    });

    test('pay prefix is stripped only when a real brand remains', () {
      expect(payeeDisplayName(counterpartyVpa: 'payment.gw@ybl'), 'Payment');
      expect(payeeDisplayName(counterpartyVpa: 'payback@icici'), 'Payback');
      expect(payeeDisplayName(counterpartyVpa: 'payswiggy@axl'), 'Swiggy');
    });

    test('labels, merchant names and SMS payee text keep precedence', () {
      expect(
        payeeDisplayName(
          userLabel: 'Lunch place',
          merchantName: 'ZOMATO LTD',
          counterpartyVpa: 'payzomato@hdfcbank',
        ),
        'Lunch place',
      );
      expect(
        payeeDisplayName(
          merchantName: 'ZOMATO LTD',
          counterpartyVpa: 'payzomato@hdfcbank',
        ),
        'ZOMATO LTD',
      );
      expect(
        payeeDisplayName(
          merchantRaw: 'SWIGGY',
          counterpartyVpa: 'swiggy.stores@icici',
        ),
        'SWIGGY',
      );
    });

    test('falls back to the description, then the caller fallback', () {
      expect(payeeDisplayName(description: 'Rent cash'), 'Rent cash');
      expect(payeeDisplayName(), 'Unknown');
      expect(payeeDisplayName(fallback: 'Transaction'), 'Transaction');
      expect(payeeDisplayName(merchantRaw: '   '), 'Unknown');
    });
  });
}
