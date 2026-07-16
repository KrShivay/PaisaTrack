import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/generic_transaction_parser.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

void main() {
  const parser = GenericTransactionParser();

  RawSms sms(String body) => RawSms(
        id: body,
        sender: 'XX-NEWBANK',
        body: body,
        receivedAt: DateTime.utc(2026, 7, 10),
      );

  group('rejectionReason maps each guard to its reason', () {
    test('hard-reject term short-circuits before other checks', () {
      // Has direction + amount + account, but the hard-reject term wins because
      // it is the first guard.
      expect(
        parser.rejectionReason(
          sms('Rs. 500 will be debited from A/c XX1234 tomorrow'),
        ),
        GenericParseRejection.hardRejectTerm,
      );
    });

    test('no direction keyword', () {
      expect(
        parser.rejectionReason(sms('Rs. 250 A/c XX1234 via UPI at SHOP')),
        GenericParseRejection.noDirection,
      );
    });

    test('no usable amount (only a balance figure)', () {
      expect(
        parser
            .rejectionReason(sms('Amount debited. Avl Bal Rs. 1200 A/c XX12')),
        GenericParseRejection.noAmount,
      );
    });

    test('direction and amount present but no context signal', () {
      // Debited + Rs. amount, but no account tail / channel / VPA to anchor it.
      expect(
        parser.rejectionReason(sms('Rs. 250 debited towards groceries')),
        GenericParseRejection.noContextSignal,
      );
    });

    test('returns null (accepted) when the guard would parse', () {
      const body =
          'Rs. 250.00 debited from A/c XX1234 via UPI to SANITIZED SHOP.';
      expect(parser.rejectionReason(sms(body)), isNull);
      // And parse() agrees — the two share one evaluation.
      expect(parser.parse(sms(body)), isNotNull);
    });
  });

  test('parse and rejectionReason never both yield a value', () {
    for (final body in const [
      'Your OTP is 123456. Do not share it.',
      'Rs. 250 A/c XX1234 via UPI at SHOP',
      'Rs. 250 debited towards groceries',
      'Rs. 250.00 debited from A/c XX1234 via UPI to SHOP.',
    ]) {
      final record = parser.parse(sms(body));
      final reason = parser.rejectionReason(sms(body));
      expect(
        (record == null) != (reason == null),
        isTrue,
        reason: 'exactly one of record/reason must be non-null for: $body',
      );
    }
  });

  test('extracts a UPI handle without treating an email address as a VPA', () {
    final upi = parser.parse(
      sms('Rs. 250 debited via UPI to friend@okaxis'),
    );
    final email = parser.parse(
      sms('Rs. 250 debited via UPI to support@example.com'),
    );

    expect(upi?.counterpartyVpa, 'friend@okaxis');
    expect(email?.counterpartyVpa, isNull);
  });
}
