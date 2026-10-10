import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/supporting_sms_classifier.dart';

/// Synthetic fixtures only: names, accounts, references and VPAs are invented.
void main() {
  late SupportingSmsClassifier classifier;

  setUpAll(() {
    classifier = SupportingSmsClassifier.fromJson(
      File(SupportingSmsClassifier.assetPath).readAsStringSync(),
    );
  });

  void expectKind(String body, SupportingSmsKind kind, int paise) {
    final info = classifier.classify(body);
    expect(info, isNotNull, reason: 'expected $kind for fixture');
    expect(info!.kind, kind);
    expect(info.amountPaise, paise);
    expect(info.currency.code, 'INR');
  }

  group('dividend', () {
    test('SBI, HDFC and RTA phrasings', () {
      expectKind(
        'Dear Customer, Dividend of Rs.1,250.00 from ACME INDUSTRIES LTD '
        'credited to your A/c XX4321 on 12-Oct-26. Ref: DIV20260012345. -SBI',
        SupportingSmsKind.dividend,
        125000,
      );
      expectKind(
        'HDFC Bank: Rs 840.50 credited to a/c **7788 on 12-10-26 towards '
        'DIVIDEND-SAMPLE TECH LIMITED. UTR: HDFCN26285123456',
        SupportingSmsKind.dividend,
        84050,
      );
      expectKind(
        'Dividend of INR 3,000.00 for FY 2025-26 has been paid to your bank '
        'account ending 9012 by NORTHWIND FOODS LTD. -KFINTECH',
        SupportingSmsKind.dividend,
        300000,
      );
      expectKind(
        'ICICI Bank Acct XX5566 credited with Rs. 410.00 on 12-Oct-26; '
        'ACH C- OMEGA POWER LTD DIVIDEND',
        SupportingSmsKind.dividend,
        41000,
      );
    });

    test('extracts account suffix, reference and tokens', () {
      final info = classifier.classify(
        'Dividend of Rs.1,250.00 from ACME INDUSTRIES LTD credited to your '
        'A/c XX4321 on 12-Oct-26. Ref: DIV20260012345.',
      )!;
      expect(info.accountSuffixes, {'4321'});
      expect(info.reference, 'DIV20260012345');
      expect(info.bodyTokens, contains('acme'));
      expect(info.bodyTokens, isNot(contains('dividend')));
    });

    test('negative cases', () {
      for (final body in [
        'Get dividend-like returns of 12% on our new scheme. Invest Rs 5000 '
            'today. Apply now!',
        'ACME INDUSTRIES declared dividend of Rs 5 per share. Record date '
            '20-Oct-26. Dividend will be credited after AGM.',
        '123456 is your OTP for dividend claim of Rs 1,250. Do not share.',
        'Dividend of Rs 1,250 could not be credited to A/c XX4321. Payment '
            'failed; contact your RTA.',
        'Dividend yield on our mutual fund is 4.2%. Offer ends soon.',
        'Rs 1,250 credited to your A/c XX4321 by UPI from friend@ybl',
      ]) {
        expect(classifier.classify(body), isNull, reason: body);
      }
    });
  });

  group('rd_instalment', () {
    test('SBI, HDFC, ICICI and Axis phrasings', () {
      expectKind(
        'Dear Customer, Rs 5,000.00 debited from A/c XX1234 on 05-Oct-26 '
        'towards RD A/c 3300112233 instalment. -SBI',
        SupportingSmsKind.rdInstalment,
        500000,
      );
      expectKind(
        'HDFC Bank: Your RD installment of Rs 2,500.00 for RD A/c XX9988 has '
        'been auto-debited from A/c XX1234 on 05-Oct-26.',
        SupportingSmsKind.rdInstalment,
        250000,
      );
      expectKind(
        'ICICI Bank: Recurring Deposit instalment of INR 10,000.00 deducted '
        'from your account XX5566 on 06-Oct-26. Ref 618200112233',
        SupportingSmsKind.rdInstalment,
        1000000,
      );
      expectKind(
        'Axis Bank: RD installment Rs.1,000 debited from A/c no. XX7788 on '
        '07-10-2026 for RD A/c 9100000011.',
        SupportingSmsKind.rdInstalment,
        100000,
      );
    });

    test('collects every account mentioned', () {
      final info = classifier.classify(
        'Rs 5,000.00 debited from A/c XX1234 on 05-Oct-26 towards RD A/c '
        '3300112233 instalment.',
      )!;
      expect(info.accountSuffixes, containsAll(['1234', '2233']));
    });

    test('negative cases', () {
      for (final body in [
        'Open a Recurring Deposit today and earn 7.1% interest rate p.a. '
            'Start with Rs 500. Apply now',
        'Your RD instalment of Rs 5,000 is overdue. Penalty may apply.',
        'RD instalment of Rs 2,500 debit failed due to insufficient balance '
            'in A/c XX1234.',
        '554433 is your OTP for RD instalment payment of Rs 2,500.',
      ]) {
        expect(classifier.classify(body), isNull, reason: body);
      }
    });
  });

  group('emi_notice', () {
    test('pre-debit and debited notices', () {
      final preDebit = classifier.classify(
        'Dear Customer, your loan EMI of Rs 12,345 is due on 05-Nov-26. '
        'Please maintain sufficient balance in A/c XX1234. -HDFC Bank',
      )!;
      expect(preDebit.kind, SupportingSmsKind.emiNotice);
      expect(preDebit.amountPaise, 1234500);
      expect(preDebit.dueDate, DateTime.utc(2026, 11, 5));
      expect(preDebit.accountSuffixes, {'1234'});

      expectKind(
        'SBI: EMI of Rs.8,750.00 for your loan a/c 3300998877 will be '
        'auto-debited from A/c XX4321 on 10-Nov-2026.',
        SupportingSmsKind.emiNotice,
        875000,
      );
      expectKind(
        'ICICI Bank: Your loan instalment of INR 15,000.00 is scheduled to '
        'be debited from A/c XX5566 on 07/11/26.',
        SupportingSmsKind.emiNotice,
        1500000,
      );
      expectKind(
        'Axis Bank: Rs 6,420.00 debited from A/c XX7788 towards your loan '
        'EMI on 05-Nov-26. Ref 618900112233',
        SupportingSmsKind.emiNotice,
        642000,
      );
    });

    test('ignores balance and outstanding amounts when picking the amount', () {
      final info = classifier.classify(
        'Your EMI is due on 05-Nov-26. Available balance Rs 50,000. '
        'EMI amount Rs 4,200 will be debited from A/c XX1234.',
      )!;
      expect(info.amountPaise, 420000);
    });

    test('negative cases', () {
      for (final body in [
        'Convert your purchase to No Cost EMI starting at Rs 1,999/month. '
            'Apply now',
        'Your EMI of Rs 8,750 bounced due to insufficient balance. Pay now '
            'to avoid charges.',
        'Pre-approved loan of Rs 5,00,000 with easy EMI of Rs 9,999. Click '
            'here',
        '778899 is your OTP to authorise EMI of Rs 8,750.',
        'Your transaction of Rs 12,000 was converted to EMI of Rs 2,100 for '
            '6 months.',
      ]) {
        expect(classifier.classify(body), isNull, reason: body);
      }
    });
  });

  group('collect_request', () {
    test('GPay, PhonePe, Paytm, BHIM and bank phrasings', () {
      final named = classifier.classify(
        'Ravi Kumar has requested Rs 500.00 from you via UPI. Approve in '
        'your UPI app. Ref 612345678901',
      )!;
      expect(named.kind, SupportingSmsKind.collectRequest);
      expect(named.amountPaise, 50000);
      expect(named.counterpartyName, 'Ravi Kumar');
      expect(named.reference, '612345678901');

      final vpa = classifier.classify(
        'Payment request of INR 250.00 from abc.shop@ybl received on '
        'PhonePe. Pay before 12-Oct-26.',
      )!;
      expect(vpa.kind, SupportingSmsKind.collectRequest);
      expect(vpa.amountPaise, 25000);
      expect(vpa.counterpartyVpa, 'abc.shop@ybl');

      expectKind(
        'Paytm: SAMPLE MART has sent a collect request of Rs 1,199 on UPI. '
        'Open Paytm to approve.',
        SupportingSmsKind.collectRequest,
        119900,
      );
      expectKind(
        'BHIM UPI: Collect request for Rs 75 from tea.stall@okaxis. Accept '
        'on BHIM to pay.',
        SupportingSmsKind.collectRequest,
        7500,
      );
      expectKind(
        'HDFC Bank: UPI collect request of Rs 3,000.00 received from '
        'rent.owner@oksbi. Approve or decline in your UPI app.',
        SupportingSmsKind.collectRequest,
        300000,
      );
    });

    test('declined, expired and promotional requests are not recognised', () {
      for (final body in [
        'Collect request of Rs 500.00 from ravi@ybl was declined.',
        'Your payment request of Rs 250 from abc@ybl has expired.',
        'UPI collect request of Rs 100 failed. Please try again.',
        'Win cashback! Request Rs 100 from a friend and get a coupon.',
        '445566 is your OTP for payment request of Rs 500.',
      ]) {
        expect(classifier.classify(body), isNull, reason: body);
      }
    });
  });

  group('amounts', () {
    test('integer paise and currency bucket', () {
      expect(SupportingSmsClassifier.amountToPaise('1,23,456.78'), 12345678);
      expect(SupportingSmsClassifier.amountToPaise('0.10'), 10);
      expect(SupportingSmsClassifier.amountToPaise('0'), isNull);
      final usd = classifier.classify(
        'Dividend of USD 12.30 credited to your account ending 4321 by '
        'GLOBEX CORP.',
      )!;
      expect(usd.amountPaise, 1230);
      expect(usd.currency.code, 'USD');
    });

    test('messages without an amount are not supporting SMS', () {
      expect(
        classifier.classify(
          'Your loan EMI is due on 05-Nov-26. Please maintain balance.',
        ),
        isNull,
      );
    });
  });
}
