import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/template_engine/template_registry.dart';

void main() {
  group('HDFC Bank Template Registry', () {
    late TemplateRegistry registry;

    setUp(() {
      const source = '''{
        "sender_patterns": ["^[A-Z]{2}-HDFCBK(?:-[A-Z])?\$", "^[A-Z]{2}-HDFCBN(?:-[A-Z])?\$"],
        "templates": [
          {
            "id": "hdfc_upi_debit_v1",
            "regex": "Money Transfer: Rs\\\\.?\\\\s?(?<amount>[\\\\d,]+\\\\.?\\\\d*) debited from A/C x(?<account>\\\\d+) to (?<merchant>.+?) on (?<date>\\\\d{2}-[A-Za-z]{3}-\\\\d{2}) via UPI Ref (?<ref>\\\\d+)",
            "direction": "debit",
            "channel": "upi",
            "date_format": "dd-MMM-yy",
            "provenance": "device"
          },
          {
            "id": "hdfc_card_spent_v1",
            "regex": "Rs\\\\.?\\\\s?(?<amount>[\\\\d,]+\\\\.?\\\\d*) spent on HDFC Bank Card ending (?<account>\\\\d{4}) at (?<merchant>.+?) on (?<date>\\\\d{2}-[A-Za-z]{3}-\\\\d{2})",
            "direction": "debit",
            "channel": "card",
            "date_format": "dd-MMM-yy",
            "provenance": "device"
          }
        ]
      }''';
      registry = TemplateRegistry.fromJson(source);
    });

    test('matches HDFC sender patterns', () {
      expect(registry.matchesSender('VK-HDFCBK-A'), isTrue);
      expect(registry.matchesSender('AD-HDFCBN'), isTrue);
      expect(registry.matchesSender('VK-SBIUPI'), isFalse);
    });

    test('parses HDFC UPI debit template fields', () {
      const body =
          'Money Transfer: Rs 1,450.50 debited from A/C x5678 to Coffee Shop on 15-Jul-26 via UPI Ref 619283746510';
      final template = registry.templates.firstWhere((t) => t.id == 'hdfc_upi_debit_v1');
      final match = template.regex.firstMatch(body);

      expect(match, isNotNull);
      expect(match!.namedGroup('amount'), '1,450.50');
      expect(match.namedGroup('account'), '5678');
      expect(match.namedGroup('merchant'), 'Coffee Shop');
      expect(match.namedGroup('date'), '15-Jul-26');
      expect(match.namedGroup('ref'), '619283746510');
    });

    test('parses HDFC card spent template fields', () {
      const body =
          'Rs 890 spent on HDFC Bank Card ending 1234 at Supermarket on 20-Jul-26';
      final template = registry.templates.firstWhere((t) => t.id == 'hdfc_card_spent_v1');
      final match = template.regex.firstMatch(body);

      expect(match, isNotNull);
      expect(match!.namedGroup('amount'), '890');
      expect(match.namedGroup('account'), '1234');
      expect(match.namedGroup('merchant'), 'Supermarket');
      expect(match.namedGroup('date'), '20-Jul-26');
    });
  });

  group('ICICI Bank Template Registry', () {
    late TemplateRegistry registry;

    setUp(() {
      const source = '''{
        "sender_patterns": ["^[A-Z]{2}-ICICIB(?:-[A-Z])?\$", "^[A-Z]{2}-ICICIP(?:-[A-Z])?\$"],
        "templates": [
          {
            "id": "icici_upi_debit_v1",
            "regex": "Dear Customer, A/C X(?<account>\\\\d{4}) debited by Rs (?<amount>[\\\\d,]+\\\\.?\\\\d*) on (?<date>\\\\d{2}-[A-Za-z]{3}-\\\\d{2}) transfer to (?<merchant>.+?) UPI Ref (?<ref>\\\\d+)",
            "direction": "debit",
            "channel": "upi",
            "date_format": "dd-MMM-yy",
            "provenance": "device"
          },
          {
            "id": "icici_card_spent_v1",
            "regex": "INR (?<amount>[\\\\d,]+\\\\.?\\\\d*) spent on ICICI Bank Credit Card xx(?<account>\\\\d{4}) on (?<date>\\\\d{2}-[A-Za-z]{3}-\\\\d{2}) at (?<merchant>.+?)\\\\.",
            "direction": "debit",
            "channel": "card",
            "date_format": "dd-MMM-yy",
            "provenance": "device"
          }
        ]
      }''';
      registry = TemplateRegistry.fromJson(source);
    });

    test('matches ICICI sender patterns', () {
      expect(registry.matchesSender('DM-ICICIB'), isTrue);
      expect(registry.matchesSender('AX-ICICIP-S'), isTrue);
      expect(registry.matchesSender('VK-AXISBK'), isFalse);
    });

    test('parses ICICI UPI debit template fields', () {
      const body =
          'Dear Customer, A/C X4321 debited by Rs 250.00 on 18-Jul-26 transfer to Bookstore UPI Ref 987654321012';
      final template = registry.templates.firstWhere((t) => t.id == 'icici_upi_debit_v1');
      final match = template.regex.firstMatch(body);

      expect(match, isNotNull);
      expect(match!.namedGroup('amount'), '250.00');
      expect(match.namedGroup('account'), '4321');
      expect(match.namedGroup('merchant'), 'Bookstore');
      expect(match.namedGroup('date'), '18-Jul-26');
      expect(match.namedGroup('ref'), '987654321012');
    });

    test('parses ICICI credit card spent template fields', () {
      const body =
          'INR 3,200.00 spent on ICICI Bank Credit Card xx9876 on 22-Jul-26 at Electronics Store.';
      final template = registry.templates.firstWhere((t) => t.id == 'icici_card_spent_v1');
      final match = template.regex.firstMatch(body);

      expect(match, isNotNull);
      expect(match!.namedGroup('amount'), '3,200.00');
      expect(match.namedGroup('account'), '9876');
      expect(match.namedGroup('merchant'), 'Electronics Store');
      expect(match.namedGroup('date'), '22-Jul-26');
    });
  });
}
