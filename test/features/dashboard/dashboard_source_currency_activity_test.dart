import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/dashboard/dashboard_widgets.dart';

void main() {
  testWidgets('dashboard discloses USD and unknown source totals separately',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardAggregateProvider.overrideWith(
            (ref) async => const DashboardAggregateSnapshot(
              debitTotal: 0,
              creditTotal: 0,
              previousSpend: 0,
              categories: [],
              merchants: [],
              trendByMonth: {},
              currencyTotals: [
                DashboardCurrencyAggregate(
                  currencyCode: 'USD',
                  currencySymbol: r'$',
                  debitTotal: 25,
                  creditTotal: 0,
                ),
                DashboardCurrencyAggregate(
                  currencyCode: null,
                  currencySymbol: r'$',
                  debitTotal: 999999999999,
                  creditTotal: 0,
                ),
                DashboardCurrencyAggregate(
                  currencyCode: 'INR',
                  currencySymbol: '₹',
                  debitTotal: 200,
                  creditTotal: 0,
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(body: BloomSourceCurrencyActivity()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OTHER SOURCE CURRENCIES · THIS PERIOD'), findsOneWidget);
    expect(find.textContaining(r'$25.00 USD'), findsOneWidget);
    expect(
      find.textContaining(r'$999999999999.00 (currency unknown)'),
      findsOneWidget,
    );
    expect(find.textContaining('₹200.00'), findsNothing);
    expect(find.textContaining('no exchange rate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
