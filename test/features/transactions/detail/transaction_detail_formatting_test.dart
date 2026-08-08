import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart' show Category, Transaction;
import 'package:paisatrack/features/transactions/detail/transaction_detail_formatting.dart';

// Minimal Transaction fixture — only the fields each test cares about.
Transaction _txn({
  String? ownedTransferId,
  String? merchantRaw,
  bool isAnalyticsExcluded = false,
}) =>
    Transaction(
      id: 'txn_test',
      ts: 0,
      amount: 100,
      direction: 'debit',
      channel: 'upi',
      parseSource: 'template',
      confidenceJson: '{}',
      status: 'needs_review',
      isDeleted: false,
      isAnalyticsExcluded: isAnalyticsExcluded,
      lifecycleState: 'settled',
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      ownedTransferId: ownedTransferId,
      merchantRaw: merchantRaw,
    );

Category _cat(String id, {String name = ''}) => Category(
      id: id,
      name: name.isEmpty ? id : name,
      icon: 'category',
      isSpending: true,
      sortOrder: 0,
      isUserCreated: false,
    );

void main() {
  group('chipCategories', () {
    final food = _cat('food', name: 'Food');
    final shopping = _cat('shopping', name: 'Shopping');
    final travel = _cat('travel', name: 'Travel');
    final health = _cat('health', name: 'Health');
    final all = [food, shopping, travel, health];

    test('always starts with currentCat', () {
      final chips = chipCategories(shopping, all, []);
      expect(chips.first.id, 'shopping');
    });

    test('fills from suggestedIds up to 3', () {
      final chips = chipCategories(food, all, ['shopping', 'travel']);
      expect(chips.map((c) => c.id), ['food', 'shopping', 'travel']);
    });

    test('skips currentCat duplicate in suggestedIds, fills from allCategories',
        () {
      // 'food' in suggestions is skipped; fallback fills 3rd slot
      final chips = chipCategories(food, all, ['food', 'shopping']);
      expect(chips.first.id, 'food');
      expect(chips.map((c) => c.id), contains('shopping'));
      expect(chips.where((c) => c.id == 'food').length, 1); // no dup
      expect(chips.length, 3);
    });

    test('skips uncategorized in suggestedIds', () {
      final chips = chipCategories(food, all, ['uncategorized', 'shopping']);
      expect(chips.map((c) => c.id), isNot(contains('uncategorized')));
      expect(chips.map((c) => c.id), contains('shopping'));
    });

    test('falls back to allCategories when suggestions are short', () {
      final chips = chipCategories(food, all, ['shopping']);
      expect(chips.length, 3);
      expect(chips.map((c) => c.id).contains('travel'), isTrue);
    });

    test('caps at 3 even with many suggestions', () {
      final chips =
          chipCategories(food, all, ['shopping', 'travel', 'health']);
      expect(chips.length, 3);
    });

    test('no duplicates when fallback overlaps suggestions', () {
      final chips = chipCategories(food, all, ['shopping']);
      final ids = chips.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('ignores unknown suggestion ids', () {
      final chips = chipCategories(food, all, ['unknown_id', 'shopping']);
      expect(chips.map((c) => c.id), contains('shopping'));
    });
  });

  group('exclusionReasonFor', () {
    test('null when ordinary transaction', () {
      expect(exclusionReasonFor(_txn(merchantRaw: 'Zomato')), isNull);
    });

    test('self-transfer when ownedTransferId set', () {
      expect(
        exclusionReasonFor(_txn(ownedTransferId: 'txn_other')),
        contains('Self-transfer'),
      );
    });

    test('credit card bill merchant pattern alone returns null', () {
      // merchant-pattern heuristics were removed — only ownedTransferId /
      // isAnalyticsExcluded drive SQL exclusion
      expect(
        exclusionReasonFor(_txn(merchantRaw: 'HDFC CREDIT CARD PAYMENT')),
        isNull,
      );
    });

    test('ATM withdrawal merchant pattern alone returns null', () {
      expect(
        exclusionReasonFor(_txn(merchantRaw: 'SBI ATM WITHDRAWAL')),
        isNull,
      );
    });

    test('analytics excluded flag', () {
      expect(
        exclusionReasonFor(_txn(isAnalyticsExcluded: true)),
        contains('Excluded from analytics'),
      );
    });

    test('ownedTransferId takes priority over merchant patterns', () {
      final reason = exclusionReasonFor(
        _txn(
          ownedTransferId: 'txn_other',
          merchantRaw: 'HDFC CREDIT CARD PAYMENT',
        ),
      );
      expect(reason, contains('Self-transfer'));
    });

    test('isAnalyticsExcluded fires even with ATM merchant name', () {
      // ownedTransferId check happens first, then isAnalyticsExcluded
      final reason = exclusionReasonFor(
        _txn(merchantRaw: 'SBI ATM', isAnalyticsExcluded: true),
      );
      expect(reason, contains('Excluded from analytics'));
    });
  });

  group('formatDetailDate', () {
    test('formats midnight as 12:00 am', () {
      // Use UTC and force local interpretation
      final date = DateTime(2024, 1, 5, 0, 0).toUtc();
      final result = formatDetailDate(date);
      // Month, day, year, and am/pm must be present
      expect(result, contains('12:00 am'));
      expect(result, contains('2024'));
    });

    test('formats noon as 12:00 pm', () {
      final date = DateTime(2024, 6, 15, 12, 0);
      final result = formatDetailDate(date);
      expect(result, contains('12:00 pm'));
      expect(result, contains('Jun'));
      expect(result, contains('15'));
    });

    test('formats 1 pm correctly', () {
      final date = DateTime(2024, 12, 31, 13, 5);
      final result = formatDetailDate(date);
      expect(result, contains('1:05 pm'));
      expect(result, contains('Dec'));
    });

    test('pads minutes to two digits', () {
      final date = DateTime(2024, 3, 7, 9, 3);
      final result = formatDetailDate(date);
      expect(result, contains(':03'));
    });

    test('all 12 month abbreviations appear for matching month', () {
      const abbrevs = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      for (var m = 1; m <= 12; m++) {
        final result = formatDetailDate(DateTime(2024, m, 1, 10, 0));
        expect(
          result,
          contains(abbrevs[m - 1]),
          reason: 'month $m should abbreviate to ${abbrevs[m - 1]}',
        );
      }
    });
  });

  group('parserSourceLabel', () {
    test('template source', () {
      expect(parserSourceLabel('template', null), 'Template match');
    });

    test('generic source', () {
      expect(parserSourceLabel('generic', null), 'Pattern match');
    });

    test('llm source', () {
      expect(parserSourceLabel('llm', null), 'AI model');
    });

    test('manual source', () {
      expect(parserSourceLabel('manual', null), 'Manual entry');
    });

    test('null source falls back to Parsed', () {
      expect(parserSourceLabel(null, null), 'Parsed');
    });

    test('unknown source passes through verbatim', () {
      expect(parserSourceLabel('custom_parser', null), 'custom_parser');
    });

    test('appends confidence percentage', () {
      expect(parserSourceLabel('template', 0.91), 'Template match · 91%');
    });

    test('rounds confidence correctly', () {
      expect(parserSourceLabel('generic', 0.555), 'Pattern match · 56%');
    });

    test('no confidence suffix when parseConfidence is null', () {
      expect(parserSourceLabel('llm', null), isNot(contains('·')));
    });
  });
}
