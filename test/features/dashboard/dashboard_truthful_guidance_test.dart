import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/budget_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/dashboard/dashboard_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

TransactionListItem _item({
  required String id,
  required DateTime ts,
  required double amount,
  required TransactionDirection direction,
  String? displayName,
  String? categoryId,
  String? categoryName,
  String? categoryIcon,
  bool categoryIsSpending = true,
  bool includeInAnalytics = true,
  bool isOwnedTransfer = false,
}) {
  return TransactionListItem(
    id: id,
    ts: ts,
    amount: amount,
    direction: direction,
    displayName: displayName ?? id,
    categoryName: categoryName,
    categoryId: categoryId,
    categoryIcon: categoryIcon,
    categoryIsSpending: categoryIsSpending,
    includeInAnalytics: includeInAnalytics,
    isOwnedTransfer: isOwnedTransfer,
  );
}

Future<ProviderContainer> _ready(
  List<TransactionListItem> items, {
  DashboardPeriod? period,
  double? budget,
}) async {
  final container = ProviderContainer(
    overrides: [
      transactionListProvider.overrideWith((ref) => Stream.value(items)),
      if (period != null) dashboardPeriodProvider.overrideWith((ref) => period),
      if (budget != null)
        monthlyBudgetProvider
            .overrideWith((ref) => Future<double?>.value(budget)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(transactionListProvider.future);
  if (budget != null) {
    await container.read(monthlyBudgetProvider.future);
  }
  return container;
}

void main() {
  final now = DateTime.now();

  group('Period-gated guidance providers', () {
    test(
        'safeTodayValueProvider returns null for historical period even with budget',
        () async {
      final period = DashboardPeriod.month(
        DateTime(now.year, now.month - 2),
      );
      final c = await _ready(
        [
          _item(
            id: 'a',
            ts: DateTime(now.year, now.month - 2, 10),
            amount: 300,
            direction: TransactionDirection.debit,
          ),
        ],
        period: period,
        budget: 50000,
      );
      expect(
        c.read(safeTodayValueProvider),
        isNull,
        reason:
            'Safe-today is meaningless for a historical month; must be null',
      );
    });

    test(
        'commitmentsTotalProvider returns 0 for historical period',
        () async {
      final period = DashboardPeriod.month(
        DateTime(now.year, now.month - 2),
      );
      final c = await _ready([], period: period);
      expect(c.read(commitmentsTotalProvider), 0);
    });

    test(
        'runwayValueProvider returns null for historical period even with budget',
        () async {
      final period = DashboardPeriod.month(
        DateTime(now.year, now.month - 2),
      );
      final c = await _ready(
        [
          _item(
            id: 'a',
            ts: DateTime(now.year, now.month - 2, 10),
            amount: 300,
            direction: TransactionDirection.debit,
          ),
        ],
        period: period,
        budget: 50000,
      );
      expect(
        c.read(runwayValueProvider),
        isNull,
        reason: 'Runway is meaningless for a historical month; must be null',
      );
    });

    test(
        'projectedMonthEndSpendProvider returns null for historical period',
        () async {
      final period = DashboardPeriod.month(
        DateTime(now.year, now.month - 2),
      );
      final c = await _ready(
        [
          _item(
            id: 'a',
            ts: DateTime(now.year, now.month - 2, 10),
            amount: 300,
            direction: TransactionDirection.debit,
          ),
        ],
        period: period,
      );
      expect(c.read(projectedMonthEndSpendProvider), isNull);
    });

    test(
        'safeTodayValueProvider returns a value for the current month with budget',
        () async {
      final c = await _ready(
        [
          _item(
            id: 'a',
            ts: DateTime(now.year, now.month, 5, 12),
            amount: 300,
            direction: TransactionDirection.debit,
          ),
        ],
        budget: 50000,
      );
      final safe = c.read(safeTodayValueProvider);
      expect(safe, isNotNull);
      expect(safe, isPositive);
    });
  });

  group('No hardcoded data ships', () {
    testWidgets('No Blinkit, 48k, or fabricated cap strings in dashboard',
        (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transactionListProvider
                .overrideWith((ref) => Stream.value(const [])),
            dashboardAggregateProvider.overrideWith(
              (ref) => Future.error(StateError('no db')),
            ),
          ],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // No fabricated Blinkit insight
      expect(find.textContaining('Blinkit'), findsNothing);
      // No hardcoded 48k budget
      expect(find.textContaining('48k'), findsNothing);
      expect(find.textContaining('48,000'), findsNothing);
      // No fabricated cap
      expect(find.textContaining('2,000/week'), findsNothing);
      expect(find.textContaining('Cap set'), findsNothing);
    });

    testWidgets('Budget card has no pre-filled amount', (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            transactionListProvider
                .overrideWith((ref) => Stream.value(const [])),
            dashboardAggregateProvider.overrideWith(
              (ref) => Future.error(StateError('no db')),
            ),
          ],
          child: const MaterialApp(home: DashboardScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Should show set budget prompt without a hardcoded amount
      expect(find.text('Set monthly budget'), findsOneWidget);
      expect(find.textContaining('Set ₹'), findsNothing);
    });
  });
}
