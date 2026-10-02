import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
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
      currencyCode: 'INR',
      currencySymbol: '₹',
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
      currencyCode: 'INR',
      currencySymbol: '₹',
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
          recurringSeriesProvider.overrideWith(
            (ref) => Stream.value([
              RecurringSeriesItem(series: item1),
              RecurringSeriesItem(series: item2),
            ]),
          ),
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

  testWidgets('InsightsScreen hides legacy untyped insight rows',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const insightRow = Insight(
      id: 'category_delta:2026-07:Food',
      period: '2026-07',
      kind: 'category_delta',
      payloadJson:
          '{"category_name":"Food","delta_fraction":0.2,"currency_code":"INR","current_start":"2026-07-01","current_end":"2026-07-03","previous_start":"2026-06-01","previous_end":"2026-06-03"}',
      dismissed: false,
    );
    const legacyInsightRow = Insight(
      id: 'category_delta:2026-07:Transport',
      period: '2026-07',
      kind: 'category_delta',
      payloadJson:
          '{"category_name":"Transport","delta_fraction":0.1,"currency_code":"INR"}',
      dismissed: false,
    );
    const feesInsightRow = Insight(
      id: 'fees_total:2026-07',
      period: '2026-07',
      kind: 'fees_total',
      payloadJson: '{"total":32,"currency_code":"INR"}',
      dismissed: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeInsightsProvider.overrideWith(
            (ref) => Stream.value([
              insightRow,
              legacyInsightRow,
              feesInsightRow,
            ]),
          ),
          trendsInboxItemsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          dashboardAggregateProvider.overrideWith(
            (ref) async => const DashboardAggregateSnapshot(
              debitTotal: 0,
              creditTotal: 0,
              previousSpend: 0,
              categories: [],
              merchants: [],
              trendByMonth: {},
            ),
          ),
          sixMonthTrendProvider.overrideWith(
            (ref) => const AsyncData<List<MonthPoint>>([]),
          ),
          monthOverMonthSpendProvider.overrideWith(
            (ref) => const AsyncData(
              MonthOverMonthSpend(
                current: 0,
                previous: 0,
                pctChange: 0,
              ),
            ),
          ),
          monthDirectionTotalsProvider.overrideWith(
            (ref) => const AsyncData(
              MonthDirectionTotals(debitTotal: 0, creditTotal: 0),
            ),
          ),
          categoryBreakdownProvider.overrideWith(
            (ref) => const AsyncData<List<CategorySlice>>([]),
          ),
          topMerchantsProvider.overrideWith(
            (ref) => const AsyncData<List<MerchantStat>>([]),
          ),
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
    expect(find.text('Category Shift'), findsNothing);
    expect(find.text('Fees & Charges Alert'), findsNothing);
    expect(find.textContaining('Food spending increased'), findsNothing);
    expect(find.textContaining('Transport spending increased'), findsNothing);
  });
}
