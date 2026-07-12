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

  // T-080 — untitled and payee/counterparty name masking.
  test('masks an untitled leading name before a transaction verb', () {
    final sanitized = donation.sanitize('Rahul Kumar paid Rs 500 to Amazon.');

    expect(sanitized, isNot(contains('Rahul Kumar')));
    expect(sanitized, contains('<NAME>'));
    expect(sanitized, contains('Rs 500'));
    // Single-token merchant after a preposition is left intact.
    expect(sanitized, contains('Amazon'));
  });

  test('masks a payee name after "to" and keeps the amount and ref', () {
    final sanitized = donation.sanitize('Sent Rs 500 to John Doe. Ref 123456.');

    expect(sanitized, isNot(contains('John Doe')));
    expect(sanitized, isNot(contains('123456')));
    expect(sanitized, contains('<NAME>'));
    expect(sanitized, contains('Rs 500'));
  });

  test('masks a trailing greeting name at end-of-string', () {
    final sanitized = donation.sanitize('Txn successful. Dear Rahul');

    expect(sanitized, isNot(contains('Rahul')));
    expect(sanitized, contains('<NAME>'));
  });

  test('masks both a titled leading name and a payee name in one message', () {
    final sanitized =
        donation.sanitize('Dear Rahul Kumar paid Rs 500 to Priya Sharma');

    expect(sanitized, isNot(contains('Rahul Kumar')));
    expect(sanitized, isNot(contains('Priya Sharma')));
    expect(sanitized, contains('<NAME>'));
    expect(sanitized, contains('Rs 500'));
  });

  // T-081 — UPI VPA / email-like handle masking.
  test('masks the local-part of UPI VPAs and email handles', () {
    final sanitized = donation.sanitize(
      'Paid via swiggy@okhdfc; contact rahul.kumar@gmail.com or rahul.kumar@paytm.',
    );

    expect(sanitized, isNot(contains('swiggy@okhdfc')));
    expect(sanitized, isNot(contains('rahul.kumar')));
    expect(sanitized, contains('<VPA>@okhdfc'));
    expect(sanitized, contains('<VPA>@gmail.com'));
    expect(sanitized, contains('<VPA>@paytm'));
  });

  // T-082 — do not over-mask large comma-less transaction amounts.
  test('keeps a currency-adjacent comma-less amount but masks account digits',
      () {
    final sanitized = donation.sanitize(
      'Rs 250000 debited from A/c 501002345678. Ref 987654321000.',
    );

    // The amount survives...
    expect(sanitized, contains('Rs 250000'));
    // ...while the account and reference runs are still masked.
    expect(sanitized, isNot(contains('501002345678')));
    expect(sanitized, isNot(contains('987654321000')));
    expect(sanitized, contains('<ACCOUNT>'));
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
