import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/message_kind_classifier.dart';

void main() {
  late MessageKindClassifier classifier;

  setUpAll(() {
    final file = File('assets/seed/message_cues_in.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'assets/seed/message_cues_in.json must exist',
    );
    classifier = MessageKindClassifier.fromJson(file.readAsStringSync());
  });

  group('MessageKindClassifier', () {
    test('classifies promoted negative fixtures correctly', () {
      final billDueBody =
          File('test/fixtures/sms/axisbk/axisbk_bill_due_reminder.txt')
              .readAsStringSync();
      expect(classifier.classify(billDueBody), MessageKind.reminder);

      final declinedSecBody =
          File('test/fixtures/sms/axisbk/axisbk_txn_declined_security.txt')
              .readAsStringSync();
      expect(classifier.classify(declinedSecBody), MessageKind.failed);

      final declinedIntlBody = File(
        'test/fixtures/sms/axisbk/axisbk_txn_declined_international_disabled.txt',
      ).readAsStringSync();
      expect(classifier.classify(declinedIntlBody), MessageKind.failed);

      final declinedLimitBody =
          File('test/fixtures/sms/axisbk/axisbk_txn_declined_usage_limit.txt')
              .readAsStringSync();
      expect(classifier.classify(declinedLimitBody), MessageKind.failed);

      final statementBody =
          File('test/fixtures/sms/axisbk/axisbk_statement_generated.txt')
              .readAsStringSync();
      expect(classifier.classify(statementBody), MessageKind.statement);
    });

    test('classifies OTP, promo, balance, mandate, reversal, and settled kinds',
        () {
      expect(
        classifier.classify(
          'Your OTP for Axis Bank transaction is 482910. Do not share.',
        ),
        MessageKind.otp,
      );

      expect(
        classifier.classify(
          'Get flat 10% cashback offer on your credit card. Apply now!',
        ),
        MessageKind.promo,
      );

      expect(
        classifier.classify('Available balance in A/C XX1234 is INR 15,200.00'),
        MessageKind.balance,
      );

      expect(
        classifier.classify(
          'E-mandate of INR 500 created for Netflix on card XX5678.',
        ),
        MessageKind.mandate,
      );

      expect(
        classifier
            .classify('Reversal of INR 450.00 credited back to your account.'),
        MessageKind.reversal,
      );

      expect(
        classifier.classify('INR 449.00 debited from A/C XX1234 at Amazon.'),
        MessageKind.settledDebit,
      );

      expect(
        classifier.classify(
          'INR 449 debited from A/c XX1234 via UPI at SHOP. '
          'Available balance INR 1,200.',
        ),
        MessageKind.settledDebit,
      );

      expect(
        classifier.classify(
          'INR 1,250 credited to A/c XX1234 from SALARY. '
          'Available balance INR 15,200.',
        ),
        MessageKind.settledCredit,
      );

      expect(
        classifier.classify(
          'Available balance INR 1,200. Monthly snapshot shows Rs 500 spent.',
        ),
        MessageKind.balance,
      );
      expect(
        classifier.classify(
          'Available balance INR 1,200. Monthly view: Rs 500 spent via UPI.',
        ),
        MessageKind.balance,
      );
      expect(
        classifier.classify(
          'Spent Rs 500 at SYNTHETIC SHOP. Available balance Rs 2,000.',
        ),
        MessageKind.settledDebit,
      );
      expect(
        classifier.classify(
          'Paid Rs 500 to SYNTHETIC SHOP. Available balance Rs 2,000.',
        ),
        MessageKind.settledDebit,
      );
      expect(
        classifier.classify(
          'Purchase of groceries for Rs 500. Available balance Rs 2,000.',
        ),
        MessageKind.settledDebit,
      );

      expect(
        classifier.classify(
          'Still spending without rewards? Earn 3 pts on every Rs 100 spent. '
          'Apply: https://example.test',
        ),
        MessageKind.promo,
      );
      expect(
        classifier.classify(
          'INR 700 debited from A/c XX1234 via UPI at SYNTHETIC SHOP. '
          'Earn 3 points on every Rs 100 spent. Apply: example.test',
        ),
        MessageKind.settledDebit,
      );
      expect(
        classifier.classify(
          'INR 700 debited from A/c XX1234 via UPI at SYNTHETIC SHOP. '
          'Congratulations, enjoy our exclusive offer. Apply now!',
        ),
        MessageKind.settledDebit,
      );
      expect(
        classifier.classify(
          'INR 1,250.00 credited to A/c XX1234 from SYNTHETIC PAYROLL. '
          'Congratulations, enjoy our exclusive offer. Apply now!',
        ),
        MessageKind.settledCredit,
      );
      expect(
        classifier.classify(
          'Credited to A/c XX1234 INR 1,250.00 from SYNTHETIC PAYROLL. '
          'Congratulations, enjoy our exclusive offer. Apply now!',
        ),
        MessageKind.settledCredit,
      );
      expect(
        classifier.classify(
          'Rs 1,500 sent from A/c XX1234 via UPI to SYNTHETIC MERCHANT. '
          'Congratulations, enjoy our exclusive offer. Apply now!',
        ),
        MessageKind.settledDebit,
      );
      expect(
        classifier.classify(
          'Congratulations! Earn 3 points on every Rs 100 spent via UPI. '
          'Enjoy this exclusive offer. Apply now!',
        ),
        MessageKind.promo,
      );
      expect(
        classifier.classify(
          'Spent Rs 500 at SYNTHETIC SHOP. Congratulations, apply now!',
        ),
        MessageKind.promo,
      );
      expect(
        classifier.classify(
          'Paid Rs 500 to SYNTHETIC SHOP. Exclusive offer, apply now!',
        ),
        MessageKind.promo,
      );
      expect(
        classifier.classify(
          'Purchase of groceries for Rs 500. Congratulations, apply now!',
        ),
        MessageKind.promo,
      );
      expect(
        classifier.classify(
          'Earn 3 points on every purchase of products for Rs 100. Apply now!',
        ),
        MessageKind.promo,
      );
      expect(
        classifier.classify(
          'Earn 3 points on every Rs 100 payment via UPI. '
          'Points are credited to your account monthly. Apply now!',
        ),
        MessageKind.promo,
      );
      expect(
        classifier.classify(
          'Earn 3 points on every Rs 100.00. '
          'Credited to your account monthly. Apply now!',
        ),
        MessageKind.promo,
      );
      expect(
        classifier.classify(
          'Earn 3 points on every Rs 100 payment via UPI. '
          'Debited from A/c monthly. Apply now!',
        ),
        MessageKind.promo,
      );
      expect(
        classifier.classify(
          'Earn rewards: Rs 100 spent via UPI. Apply now!',
        ),
        MessageKind.promo,
      );

      expect(
        classifier.classify(
          'INR 500 expected to be debited from A/c XX1234 tomorrow.',
        ),
        MessageKind.pendingAuth,
      );

      expect(
        classifier.classify('Your account summary is ready for INR 500.'),
        MessageKind.unknown,
      );
      expect(MessageKind.fromWireName('unrecognized'), MessageKind.unknown);

      expect(
        classifier.classify('INR 1,250.00 credited to A/C XX1234 from Salary.'),
        MessageKind.settledCredit,
      );
    });
  });
}
