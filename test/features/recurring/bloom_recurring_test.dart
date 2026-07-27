import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/recurring/recurring_screen.dart';

RecurringSery testSeries({
  required String id,
  required String label,
  required double amount,
}) {
  final now = DateTime.now();
  return RecurringSery(
    id: id,
    merchantId: 'm_$id',
    label: label,
    expectedAmount: amount,
    tolerancePct: 0.05,
    period: 'monthly',
    periodDays: 30,
    nextExpectedDate: now.add(const Duration(days: 6)),
    lastAmount: amount,
    amountTrend: 'flat',
    occurrences: 3,
    status: 'active',
    kind: 'expense',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRecurring(
    WidgetTester tester,
    List<RecurringSery> seriesList,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recurringSeriesProvider.overrideWith(
            (ref) => Stream.value(
              seriesList
                  .map((r) => RecurringSeriesItem(series: r))
                  .toList(),
            ),
          ),
        ],
        child: const MaterialApp(
          home: RecurringScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom RecurringScreen', () {
    testWidgets('renders commitments summary card and header', (tester) async {
      await pumpRecurring(tester, const []);

      expect(find.text('Recurring'), findsOneWidget);
      expect(find.text('MONTHLY COMMITMENTS'), findsOneWidget);
      expect(find.text('No recurring payments detected yet'), findsOneWidget);
    });

    testWidgets('renders active subscription rows with Bloom components',
        (tester) async {
      final items = [
        testSeries(
          id: '1',
          label: 'Netflix',
          amount: 649.0,
        ),
        testSeries(
          id: '2',
          label: 'Airtel Broadband',
          amount: 1199.0,
        ),
      ];

      await pumpRecurring(tester, items);

      expect(find.text('Netflix'), findsAtLeast(1));
      expect(find.text('Airtel Broadband'), findsAtLeast(1));
      expect(find.byType(BloomCategoryTile), findsWidgets);
      expect(find.byType(BloomAmount), findsWidgets);
    });
  });
}
