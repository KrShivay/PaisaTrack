import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/message_kind_classifier.dart';

void main() {
  late MessageKindClassifier classifier;

  setUpAll(() {
    final file = File('assets/seed/message_cues_in.json');
    expect(file.existsSync(), isTrue, reason: 'assets/seed/message_cues_in.json must exist');
    classifier = MessageKindClassifier.fromJson(file.readAsStringSync());
  });

  group('MessageKindClassifier', () {
    test('classifies promoted negative fixtures correctly', () {
      final billDueBody = File('test/fixtures/sms/axisbk/axisbk_bill_due_reminder.txt').readAsStringSync();
      expect(classifier.classify(billDueBody), MessageKind.reminder);

      final declinedSecBody = File('test/fixtures/sms/axisbk/axisbk_txn_declined_security.txt').readAsStringSync();
      expect(classifier.classify(declinedSecBody), MessageKind.failed);

      final declinedIntlBody = File('test/fixtures/sms/axisbk/axisbk_txn_declined_international_disabled.txt').readAsStringSync();
      expect(classifier.classify(declinedIntlBody), MessageKind.failed);

      final declinedLimitBody = File('test/fixtures/sms/axisbk/axisbk_txn_declined_usage_limit.txt').readAsStringSync();
      expect(classifier.classify(declinedLimitBody), MessageKind.failed);

      final statementBody = File('test/fixtures/sms/axisbk/axisbk_statement_generated.txt').readAsStringSync();
      expect(classifier.classify(statementBody), MessageKind.statement);
    });

    test('classifies OTP, promo, balance, mandate, reversal, and settled kinds', () {
      expect(
        classifier.classify('Your OTP for Axis Bank transaction is 482910. Do not share.'),
        MessageKind.otp,
      );

      expect(
        classifier.classify('Get flat 10% cashback offer on your credit card. Apply now!'),
        MessageKind.promo,
      );

      expect(
        classifier.classify('Available balance in A/C XX1234 is INR 15,200.00'),
        MessageKind.balance,
      );

      expect(
        classifier.classify('E-mandate of INR 500 created for Netflix on card XX5678.'),
        MessageKind.mandate,
      );

      expect(
        classifier.classify('Reversal of INR 450.00 credited back to your account.'),
        MessageKind.reversal,
      );

      expect(
        classifier.classify('INR 449.00 debited from A/C XX1234 at Amazon.'),
        MessageKind.settledDebit,
      );

      expect(
        classifier.classify('INR 1,250.00 credited to A/C XX1234 from Salary.'),
        MessageKind.settledCredit,
      );
    });
  });
}
