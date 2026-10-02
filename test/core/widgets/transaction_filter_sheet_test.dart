import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/core/widgets/transaction_filter_sheet.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';

void main() {
  const calendar = FinancialCalendar.fixed(Duration(hours: -5));
  final item = TransactionListItem(
    id: 'txn_1',
    ts: DateTime.utc(2026, 7, 6, 9),
    amount: 610.83,
    direction: TransactionDirection.debit,
    displayName: 'Zomato',
    categoryName: 'Food & Dining',
    categoryId: 'food',
    categoryIcon: 'restaurant',
    merchantId: 'merchant_zomato',
    merchantRaw: 'zomato@paytm',
    accountHint: 'xx6265',
    channel: 'upi',
    note: 'Team lunch',
    reference: 'UTR123456',
    status: 'needs_review',
    parseSource: 'template',
  );

  test('search matches every supported transaction field', () {
    const filters = TransactionFilters();
    for (final query in [
      'zomato',
      'food',
      '610.83',
      'xx6265',
      'upi',
      'team lunch',
      'utr123456',
      'needs review',
      'sms',
    ]) {
      expect(filters.matchesSearch(item, query), isTrue, reason: query);
    }
    expect(filters.matchesSearch(item, 'salary'), isFalse);
  });

  test('equal id sets produce equal provider family keys', () {
    final first = TransactionFilters(
      ids: {'txn_1', 'txn_2'},
      dateRange: DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      ),
    );
    final second = TransactionFilters(
      ids: {'txn_2', 'txn_1'},
      dateRange: DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      ),
    );
    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('evidence id filters match only the cited rows', () {
    const filters = TransactionFilters(ids: {'txn_1'});
    final unrelated = TransactionListItem(
      id: 'unrelated',
      ts: item.ts,
      amount: item.amount,
      direction: item.direction,
      displayName: item.displayName,
      categoryName: item.categoryName,
      categoryId: item.categoryId,
      categoryIcon: item.categoryIcon,
    );
    expect(
      filters.matches(
        item,
        calendar: calendar,
        recurringMerchantIds: const {},
        anomalyTransactionIds: const {},
      ),
      isTrue,
    );
    expect(
      filters.matches(
        unrelated,
        calendar: calendar,
        recurringMerchantIds: const {},
        anomalyTransactionIds: const {},
      ),
      isFalse,
    );
  });

  test('date range includes the selected start and end calendar days', () {
    final range = DateTimeRange(
      start: DateTime(2026, 7, 2),
      end: DateTime(2026, 7, 2),
    );
    final filters = TransactionFilters(dateRange: range);
    final startOfDay = TransactionListItem(
      id: 'start',
      ts: DateTime.utc(2026, 7, 2, 5, 30), // 00:30 at UTC−05:00
      amount: item.amount,
      direction: item.direction,
      displayName: item.displayName,
      categoryName: item.categoryName,
      categoryId: item.categoryId,
      categoryIcon: item.categoryIcon,
    );
    final endOfDay = TransactionListItem(
      id: 'end',
      ts: DateTime.utc(2026, 7, 3, 4, 59), // 23:59 at UTC−05:00
      amount: item.amount,
      direction: item.direction,
      displayName: item.displayName,
      categoryName: item.categoryName,
      categoryId: item.categoryId,
      categoryIcon: item.categoryIcon,
    );

    expect(
      filters.matches(
        startOfDay,
        calendar: calendar,
        recurringMerchantIds: const {},
        anomalyTransactionIds: const {},
      ),
      isTrue,
    );
    expect(
      filters.matches(
        endOfDay,
        calendar: calendar,
        recurringMerchantIds: const {},
        anomalyTransactionIds: const {},
      ),
      isTrue,
    );
  });

  test('complete filters combine with AND semantics', () {
    final filters = TransactionFilters(
      dateRange: DateTimeRange(
        start: DateTime(2026, 7, 1),
        end: DateTime(2026, 7, 31),
      ),
      categoryId: 'food',
      merchant: 'Zomato',
      account: 'xx6265',
      channel: 'upi',
      minimumAmount: 500,
      maximumAmount: 700,
      review: TransactionReviewFilter.needsReview,
      recurring: TransactionRecurringFilter.recurring,
      source: TransactionSourceFilter.sms,
      anomaly: TransactionAnomalyFilter.flagged,
    );

    expect(
      filters.matches(
        item,
        calendar: calendar,
        recurringMerchantIds: const {'merchant_zomato'},
        anomalyTransactionIds: const {'txn_1'},
      ),
      isTrue,
    );
    expect(
      filters.matches(
        item,
        calendar: calendar,
        recurringMerchantIds: const {'merchant_zomato'},
        anomalyTransactionIds: const {},
      ),
      isFalse,
    );
  });

  test('clearing one filter preserves the others', () {
    const filters = TransactionFilters(
      categoryId: 'food',
      categoryName: 'Food & Dining',
      minimumAmount: 500,
      maximumAmount: 700,
      review: TransactionReviewFilter.needsReview,
    );

    expect(filters.activeCount, 3);
    final updated = filters.clear(TransactionFilterField.amount);
    expect(updated.minimumAmount, isNull);
    expect(updated.maximumAmount, isNull);
    expect(updated.categoryId, 'food');
    expect(updated.review, TransactionReviewFilter.needsReview);
  });
}
