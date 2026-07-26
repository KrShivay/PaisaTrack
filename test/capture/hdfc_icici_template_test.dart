import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/template_engine/template_matcher.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';
import 'package:paisatrack/data/models/raw_sms.dart';

void main() {
  final fallbackDate = DateTime.utc(2026, 1, 1);

  group('HDFC Bank Template Registry', () {
    late TemplateRegistry registry;
    late TemplateMatcher matcher;

    setUp(() {
      final jsonString =
          File('assets/templates/hdfcbk.json').readAsStringSync();
      registry = TemplateRegistry.fromJson(jsonString);
      matcher = TemplateMatcher(registries: [registry]);
    });

    test('matches HDFC sender patterns', () {
      expect(registry.matchesSender('VK-HDFCBK-A'), isTrue);
      expect(registry.matchesSender('AD-HDFCBN'), isTrue);
      expect(registry.matchesSender('VK-SBIUPI'), isFalse);
    });

    test('parses HDFC UPI debit template via TemplateMatcher', () async {
      final sms = RawSms(
        id: 't1',
        sender: 'VK-HDFCBK',
        body:
            'Money Transfer: Rs 1,450.50 debited from A/C x5678 to Coffee Shop on 15-Jul-26 via UPI Ref 619283746510',
        receivedAt: fallbackDate,
      );

      final record = await matcher.match(sms);
      expect(record, isNotNull);
      expect(record!.amount, 1450.50);
      expect(record.accountHint, 'xx5678');
      expect(record.merchantRaw, 'Coffee Shop');
      expect(record.refId, '619283746510');
      expect(record.ts, DateTime.utc(2026, 7, 15));
      expect(record.parseConfidence, 0.85);
    });

    test('parses HDFC card spent template via TemplateMatcher', () async {
      final sms = RawSms(
        id: 't2',
        sender: 'VK-HDFCBK',
        body:
            'Rs 890 spent on HDFC Bank Card ending 1234 at Supermarket on 20-Jul-26',
        receivedAt: fallbackDate,
      );

      final record = await matcher.match(sms);
      expect(record, isNotNull);
      expect(record!.amount, 890.0);
      expect(record.accountHint, 'xx1234');
      expect(record.merchantRaw, 'Supermarket');
      expect(record.ts, DateTime.utc(2026, 7, 20));
      expect(record.parseConfidence, 0.85);
    });

    test('parses HDFC account debit with balance via TemplateMatcher',
        () async {
      final sms = RawSms(
        id: 't3',
        sender: 'VK-HDFCBK',
        body:
            'Rs.500.00 debited from HDFC Bank A/C x1234 on 15-Jul-26 to SWIGGY. Avl Bal: Rs.5,000.00',
        receivedAt: fallbackDate,
      );

      final record = await matcher.match(sms);
      expect(record, isNotNull);
      expect(record!.amount, 500.00);
      expect(record.accountHint, 'xx1234');
      expect(record.merchantRaw, 'SWIGGY');
      expect(record.balanceAfter, 5000.00);
      expect(record.ts, DateTime.utc(2026, 7, 15));
      expect(record.parseConfidence, 0.85);
    });

    test('parses HDFC account debit without balance via TemplateMatcher',
        () async {
      final sms = RawSms(
        id: 't4',
        sender: 'VK-HDFCBK',
        body:
            'Rs.500.00 debited from HDFC Bank A/C x1234 on 15-Jul-26 to AMAZON.IN.',
        receivedAt: fallbackDate,
      );

      final record = await matcher.match(sms);
      expect(record, isNotNull);
      expect(record!.amount, 500.00);
      expect(record.accountHint, 'xx1234');
      expect(record.merchantRaw, 'AMAZON.IN');
      expect(record.ts, DateTime.utc(2026, 7, 15));
      expect(record.parseConfidence, 0.85);
    });

    test('parses HDFC account credit via TemplateMatcher', () async {
      final sms = RawSms(
        id: 't5',
        sender: 'VK-HDFCBK',
        body:
            'Rs.2,500.00 credited to HDFC Bank A/C x1234 on 18-Jul-26 by ACME CORP.',
        receivedAt: fallbackDate,
      );

      final record = await matcher.match(sms);
      expect(record, isNotNull);
      expect(record!.amount, 2500.00);
      expect(record.accountHint, 'xx1234');
      expect(record.merchantRaw, 'ACME CORP');
      expect(record.ts, DateTime.utc(2026, 7, 18));
      expect(record.parseConfidence, 0.85);
    });
  });

  group('ICICI Bank Template Registry', () {
    late TemplateRegistry registry;
    late TemplateMatcher matcher;

    setUp(() {
      final jsonString =
          File('assets/templates/icicib.json').readAsStringSync();
      registry = TemplateRegistry.fromJson(jsonString);
      matcher = TemplateMatcher(registries: [registry]);
    });

    test('matches ICICI sender patterns', () {
      expect(registry.matchesSender('DM-ICICIB'), isTrue);
      expect(registry.matchesSender('AX-ICICIP-S'), isTrue);
      expect(registry.matchesSender('VK-AXISBK'), isFalse);
    });

    test('parses ICICI UPI debit template via TemplateMatcher', () async {
      final sms = RawSms(
        id: 't6',
        sender: 'DM-ICICIB',
        body:
            'Dear Customer, A/C X4321 debited by Rs 250.00 on 18-Jul-26 transfer to Bookstore UPI Ref 987654321012',
        receivedAt: fallbackDate,
      );

      final record = await matcher.match(sms);
      expect(record, isNotNull);
      expect(record!.amount, 250.00);
      expect(record.accountHint, 'xx4321');
      expect(record.merchantRaw, 'Bookstore');
      expect(record.refId, '987654321012');
      expect(record.ts, DateTime.utc(2026, 7, 18));
      expect(record.parseConfidence, 0.85);
    });

    test('parses ICICI credit card spent template via TemplateMatcher',
        () async {
      final sms = RawSms(
        id: 't7',
        sender: 'DM-ICICIB',
        body:
            'INR 3,200.00 spent on ICICI Bank Credit Card xx9876 on 22-Jul-26 at Electronics Store.',
        receivedAt: fallbackDate,
      );

      final record = await matcher.match(sms);
      expect(record, isNotNull);
      expect(record!.amount, 3200.00);
      expect(record.accountHint, 'xx9876');
      expect(record.merchantRaw, 'Electronics Store');
      expect(record.ts, DateTime.utc(2026, 7, 22));
      expect(record.parseConfidence, 0.85);
    });

    test('parses ICICI account debit template via TemplateMatcher', () async {
      final sms = RawSms(
        id: 't8',
        sender: 'DM-ICICIB',
        body:
            'A/C X4321 Debited with INR 1,500.00 on 20-Jul-26 info AMAZON.IN.',
        receivedAt: fallbackDate,
      );

      final record = await matcher.match(sms);
      expect(record, isNotNull);
      expect(record!.amount, 1500.00);
      expect(record.accountHint, 'xx4321');
      expect(record.merchantRaw, 'AMAZON.IN');
      expect(record.ts, DateTime.utc(2026, 7, 20));
      expect(record.parseConfidence, 0.85);
    });

    test('parses ICICI account credit template via TemplateMatcher', () async {
      final sms = RawSms(
        id: 't9',
        sender: 'DM-ICICIB',
        body:
            'Dear Customer, A/C X4321 credited with INR 5,000.00 on 21-Jul-26 by SALARY.',
        receivedAt: fallbackDate,
      );

      final record = await matcher.match(sms);
      expect(record, isNotNull);
      expect(record!.amount, 5000.00);
      expect(record.accountHint, 'xx4321');
      expect(record.merchantRaw, 'SALARY');
      expect(record.ts, DateTime.utc(2026, 7, 21));
      expect(record.parseConfidence, 0.85);
    });
  });
}
