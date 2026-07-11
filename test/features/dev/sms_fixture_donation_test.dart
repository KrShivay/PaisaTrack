import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/raw_sms_repository.dart';
import 'package:paisatrack/features/dev/sms_fixture_donation.dart';

void main() {
  const donation = SmsFixtureDonation();

  test('masks names accounts references and balances but keeps amount', () {
    final sanitized = donation.sanitize(
      'Dear Rahul Kumar, INR 2,499.00 was debited from account 1234 5678. '
      'Available balance is Rs 10,001.25. UTR 987654321012.',
    );

    expect(sanitized, isNot(contains('Rahul Kumar')));
    expect(sanitized, isNot(contains('1234 5678')));
    expect(sanitized, isNot(contains('10,001.25')));
    expect(sanitized, isNot(contains('987654321012')));
    expect(sanitized, contains('<NAME>'));
    expect(sanitized, contains('<ACCOUNT>'));
    expect(sanitized, contains('<BALANCE>'));
    expect(sanitized, contains('INR 2,499.00'));
  });

  test('fixture is valid device-provenance JSON with sanitized body', () {
    final fixture = donation.fixture(
      UnparsedSms(
        id: 'sms_1',
        sender: 'AX-BANK',
        body: 'Ms. Anjali, A/c XX998877 was credited Rs. 500.',
        receivedAt: DateTime.utc(2026, 7, 11),
      ),
    );
    final json = jsonDecode(fixture) as Map<String, Object?>;

    expect(json['sender'], 'AX-BANK');
    expect(json['provenance'], 'device');
    expect(json['body'], contains('<NAME>'));
    expect(json['body'], contains('<ACCOUNT>'));
    expect(json['body'], contains('Rs. 500'));
  });
}
