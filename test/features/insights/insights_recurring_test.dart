import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';
import 'package:paisatrack/features/recurring/recurring_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('RecurringScreen renders commitments and statuses',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final now = DateTime.now();

    final item1 = RecurringSery(
      id: 'rec_1',
      merchantId: 'm_netflix',
      label: 'Netflix Subscription',
      expectedAmount: 649.0,
      tolerancePct: 0.05,
      period: 'monthly',
      periodDays: 30,
      nextExpectedDate: now.add(const Duration(days: 3)),
      lastAmount: 649.0,
      amountTrend: 'stable',
      occurrences: 5,
      status: 'active',
      kind: 'subscription',
    );

    final item2 = RecurringSery(
      id: 'rec_2',
      merchantId: 'm_gym',
      label: 'Cult Pass',
      expectedAmount: 1500.0,
      tolerancePct: 0.05,
      period: 'monthly',
      periodDays: 30,
      nextExpectedDate: now.add(const Duration(days: 20)),
      lastAmount: 1200.0,
      amountTrend: 'rising',
      occurrences: 3,
      status: 'price_changed',
      kind: 'subscription',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recurringSeriesProvider
              .overrideWith((ref) => Stream.value([item1, item2])),
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const RecurringScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Recurring'), findsOneWidget);
    expect(find.text('Netflix Subscription'), findsAtLeast(1));
    expect(find.text('Cult Pass'), findsOneWidget);
    expect(find.text('Price Changed'), findsOneWidget);
  });

  testWidgets('InsightsScreen renders trends and active insights',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const insightRow = Insight(
      id: 'fees_total:2026-07',
      period: '2026-07',
      kind: 'fees_total',
      payloadJson: '{"total": 150.0, "count": 2}',
      dismissed: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeInsightsProvider
              .overrideWith((ref) => Stream.value([insightRow])),
          sixMonthTrendProvider.overrideWith((ref) => const []),
          monthOverMonthSpendProvider.overrideWith(
            (ref) => const MonthOverMonthSpend(
              current: 0,
              previous: 0,
              pctChange: 0,
            ),
          ),
          monthDirectionTotalsProvider.overrideWith(
            (ref) => const MonthDirectionTotals(debitTotal: 0, creditTotal: 0),
          ),
          categoryBreakdownProvider.overrideWith((ref) => const []),
          topMerchantsProvider.overrideWith((ref) => const []),
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: const InsightsScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Trends'), findsOneWidget);
    expect(find.text('Fees & Charges Alert'), findsOneWidget);
  });
}
