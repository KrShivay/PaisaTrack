import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/generic_transaction_parser.dart';
import 'package:paisatrack/capture/span_verifier.dart';
import 'package:paisatrack/core/constants.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

void main() {
  const parser = GenericTransactionParser();

  RawSms sms(String body, {String sender = 'VK-HDFCBK'}) => RawSms(
        id: body,
        sender: sender,
        body: body,
        receivedAt: DateTime.utc(2026, 7, 10),
      );

  group('rejectionReason maps each guard to its reason', () {
    test('hard-reject term short-circuits before other checks', () {
      // Has direction + amount + account, but the hard-reject OTP term wins
      // because it is the first guard.
      expect(
        parser.rejectionReason(
          sms('Your OTP is 482910 for Rs. 500 debited from A/c XX1234'),
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

  test('marks an account credit described as salary for income categorization',
      () {
    final record = parser.parse(
      sms('INR 50,000 salary credited to A/c XX1234 via NEFT.'),
    );

    expect(record?.direction, TransactionDirection.credit);
    expect(record?.merchantRaw, 'Salary');
  });

  test('preserves explicit USD and keeps bare dollar as unknown ISO bucket',
      () {
    final usd = parser.parse(
      sms('Your card XX1234 was charged USD 25.00 at SANITIZED STORE'),
    );
    final ambiguous = parser.parse(
      sms(r'Your card XX1234 was charged $25.00 at SANITIZED STORE'),
    );

    expect(usd?.amount, 25);
    expect(usd?.currencyCode, 'USD');
    expect(usd?.currencySymbol, r'$');
    expect(ambiguous?.amount, 25);
    expect(ambiguous?.currencyCode, isNull);
    expect(ambiguous?.currencySymbol, r'$');
  });

  test('keeps a debit when available balance trails the transaction', () {
    const body = 'Your account XX1234 was debited INR 250.00 via UPI at '
        'SANITIZED SHOP. Available balance is INR 1,000.00';
    final record = parser.parse(sms(body));

    expect(record, isNotNull);
    expect(record!.amount, 250);
    expect(record.balanceAfter, 1000);
    expect(record.direction, TransactionDirection.debit);
    expect(record.parseConfidence, lessThanOrEqualTo(0.6));
    expect(
      const SpanVerifier().verify(
        body: body,
        evidence: record.evidence,
        record: record,
      ),
      isTrue,
    );
  });

  test('balance-only, failed, and reversal text abstain in generic parsing',
      () {
    for (final body in const [
      'Available balance is INR 1,000.00 for A/c XX1234',
      'Transaction of INR 500 on card XX1234 has been declined',
      'A/c XX1234 failed for Rs. 500.00 via UPI',
      'Reversal of INR 300.00 credited back to A/c XX1234',
      'Refunded INR 300.00 to A/c XX1234',
    ]) {
      expect(
        parser.parse(sms(body)),
        isNull,
        reason: 'generic fallback must abstain: $body',
      );
    }
  });

  test('accepts unambiguous completed charge, transfer, and credit wording',
      () {
    const examples = <({
      String body,
      double amount,
      TransactionDirection dir,
      String? merchant,
      double confidence,
    })>[
      (
        body: 'Your card XX1234 was charged Rs. 725.00 at SANITIZED STORE',
        amount: 725,
        dir: TransactionDirection.debit,
        merchant: 'SANITIZED STORE',
        confidence: AppConstants.genericHighParseConfidence,
      ),
      (
        body:
            'INR 2,500.00 transferred from A/c XX2345 via IMPS to SANITIZED PERSON',
        amount: 2500,
        dir: TransactionDirection.debit,
        merchant: 'SANITIZED PERSON',
        confidence: AppConstants.genericHighParseConfidence,
      ),
      (
        body: '₹4,200.00 added to A/c XX3456 via NEFT',
        amount: 4200,
        dir: TransactionDirection.credit,
        merchant: null,
        confidence: AppConstants.genericLowParseConfidence,
      ),
    ];

    for (final example in examples) {
      final record = parser.parse(sms(example.body));

      expect(record, isNotNull, reason: example.body);
      expect(record!.amount, example.amount, reason: example.body);
      expect(record.direction, example.dir, reason: example.body);
      expect(record.merchantRaw, example.merchant, reason: example.body);
      expect(record.parseConfidence, example.confidence, reason: example.body);
      expect(
        const SpanVerifier().verify(
          body: example.body,
          evidence: record.evidence,
          record: record,
        ),
        isTrue,
        reason: example.body,
      );
    }
  });

  test('parses the verified SLICE sent-from alert and ignores its footer', () {
    const body = 'Rs. 1,531.20 sent from a/c xx1234 on 14-Sep-26 to '
        'SAMPLE SERVICE STATION (UPI Ref: 111111111111). '
        'Not you? Call your bank immediately. - slice';
    final receivedAt = DateTime.utc(2026, 9, 15);
    final source = RawSms(
      id: 'synthetic-slice-sent-from',
      sender: 'SLICE',
      body: body,
      receivedAt: receivedAt,
    );

    final record = parser.parse(source);

    expect(record, isNotNull);
    expect(record!.amount, 1531.2);
    expect(record.direction, TransactionDirection.debit);
    expect(record.channel, TransactionChannel.upi);
    expect(record.accountHint, 'xx1234');
    expect(record.merchantRaw, 'SAMPLE SERVICE STATION');
    expect(record.refId, '111111111111');
    expect(record.ts, DateTime.utc(2026, 9, 14));
    expect(record.ts, isNot(receivedAt));
    expect(
      record.evidence!
          .singleWhere((evidence) => evidence.field == 'ts')
          .verbatim,
      '14-Sep-26',
    );
    expect(
      const SpanVerifier().verify(
        body: body,
        evidence: record.evidence,
        record: record,
      ),
      isTrue,
    );

    expect(
      parser
          .parse(sms('Not you? Call your bank immediately.', sender: 'SLICE')),
      isNull,
    );
  });

  test('uses the received date for unrelated or invalid body dates', () {
    final receivedAt = DateTime.utc(2026, 9, 15);
    const bodies = [
      'Rs. 1,531.20 sent from a/c xx1234 to SAMPLE STORE. '
          'Not you? Call your bank immediately on 14-Sep-26.',
      'Rs. 1,531.20 sent from a/c xx1234 on 32-Sep-26 to SAMPLE STORE.',
    ];

    for (final body in bodies) {
      final record = parser.parse(
        RawSms(
          id: 'synthetic-slice-invalid-date',
          sender: 'SLICE',
          body: body,
          receivedAt: receivedAt,
        ),
      );

      expect(record, isNotNull, reason: body);
      expect(record!.ts, receivedAt, reason: body);
      expect(
        record.evidence!
            .singleWhere((evidence) => evidence.field == 'ts')
            .verbatim,
        body,
        reason: body,
      );
    }
  });

  test('parses the transaction date when its leading word is capitalized', () {
    final record = parser.parse(
      sms('Rs. 250.00 sent from a/c xx1234 On 14-Sep-26 via UPI'),
    );

    expect(record, isNotNull);
    expect(record!.ts, DateTime.utc(2026, 9, 14));
  });

  test('abstains on future, pending, and scheduled payment wording', () {
    for (final body in const [
      'Rs. 500 will be debited from A/c XX1234 tomorrow via UPI',
      'Your card XX1234 will be charged INR 500 tomorrow',
      'INR 500 will be transferred from A/c XX1234 tomorrow via IMPS',
      'INR 500 will be credited to A/c XX1234 tomorrow via NEFT',
      'INR 500 will be added to A/c XX1234 tomorrow via NEFT',
      'Rs. 500 to be debited from A/c XX1234 via UPI tomorrow',
      'Rs. 500 expected to be debited from A/c XX1234 tomorrow via UPI',
      'INR 500 to be credited to A/c XX1234 via NEFT tomorrow',
      'INR 500 expected to be credited to A/c XX1234 via NEFT tomorrow',
      'A/c XX1234 is scheduled to be debited INR 500 tomorrow via UPI',
      'A/c XX1234 is due to be debited INR 500 tomorrow via UPI',
      'UPI payment of Rs. 500 is scheduled from A/c XX1234',
      'UPI payment of Rs. 500 is pending from A/c XX1234',
    ]) {
      expect(
        parser.parse(sms(body)),
        isNull,
        reason: 'generic fallback must abstain: $body',
      );
    }
  });

  test('does not treat an unrelated processing fee as an unsettled payment',
      () {
    const body = 'Your card XX1234 was charged INR 725.00 at SANITIZED STORE; '
        'processing fee INR 10.00';
    final record = parser.parse(sms(body));

    expect(record, isNotNull);
    expect(record!.amount, 725);
    expect(record.direction, TransactionDirection.debit);
    expect(record.parseConfidence, lessThanOrEqualTo(0.6));
  });
}
