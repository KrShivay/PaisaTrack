import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/category_visuals.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/recurring/recurring_screen.dart';

void main() {
  RecurringSery series({
    String id = 'series_1',
    String label = 'Netflix',
    String kind = 'subscription',
    String status = 'active',
    String? currencyCode = 'INR',
    String? currencySymbol = '₹',
  }) {
    return RecurringSery(
      id: id,
      merchantId: 'merchant_$id',
      label: label,
      expectedAmount: 499,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
      tolerancePct: 0.05,
      period: 'monthly',
      periodDays: 30,
      nextExpectedDate: DateTime.utc(2026, 8, 1),
      lastAmount: 499,
      amountTrend: 'flat',
      occurrences: 4,
      status: status,
      kind: kind,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    List<RecurringSery> rows,
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
              rows.map((r) => RecurringSeriesItem(series: r)).toList(),
            ),
          ),
        ],
        child: const MaterialApp(home: RecurringScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shows designed empty state', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('No recurring payments detected yet'), findsOneWidget);
    expect(
      find.textContaining('matching transactions arrive'),
      findsOneWidget,
    );
  });

  testWidgets('renders active series with Bloom components', (tester) async {
    await pumpScreen(tester, [
      series(id: '1', label: 'Netflix'),
      series(id: '2', label: 'Spotify'),
    ]);

    expect(find.text('Netflix'), findsAtLeast(1));
    expect(find.text('Spotify'), findsAtLeast(1));
    expect(find.byType(BloomCategoryTile), findsWidgets);
    expect(find.byType(BloomAmount), findsWidgets);
  });

  testWidgets('commitments are subtotaled by source currency', (tester) async {
    await pumpScreen(tester, [
      series(id: 'inr', label: 'INR plan'),
      series(
        id: 'usd',
        label: 'USD plan',
        currencyCode: 'USD',
        currencySymbol: r'$',
      ),
      series(
        id: 'bare',
        label: 'Dollar-symbol plan',
        currencyCode: null,
        currencySymbol: r'$',
      ),
    ]);

    expect(find.text('INR MONTHLY COMMITMENTS'), findsOneWidget);
    expect(find.textContaining('USD · 1 active'), findsOneWidget);
    expect(find.textContaining(r'$499.00 USD/mo'), findsOneWidget);
    expect(
      find.textContaining(r'$499.00 (currency unknown)/mo'),
      findsOneWidget,
    );
    expect(find.textContaining('no exchange rate'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders recharge and investment kinds with valid visuals',
      (tester) async {
    await pumpScreen(tester, [
      series(id: '3', label: 'Jio', kind: 'recharge'),
      series(id: '4', label: 'Mutual Fund', kind: 'investment'),
    ]);

    expect(find.text('Jio'), findsAtLeast(1));
    expect(find.text('Mutual Fund'), findsAtLeast(1));

    // Check that we find tiles (may be 4 due to dual-rendering in upcoming + all sections)
    final tiles =
        tester.widgetList<BloomCategoryTile>(find.byType(BloomCategoryTile));
    expect(tiles.length, greaterThanOrEqualTo(2));

    // Verify neither resolved to fallback color (0xFF94A3B8)
    for (final tile in tiles) {
      expect(
        CategoryVisuals.color(tile.categoryId).toARGB32(),
        isNot(0xFF94A3B8),
      );
    }
  });

  testWidgets('shows marked-recurring section with unmark and detail tap',
      (tester) async {
    tester.view.physicalSize = const Size(402, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recurringSeriesProvider.overrideWith((ref) => Stream.value(const [])),
          markedRecurringProvider.overrideWith(
            (ref) => Stream.value([
              MarkedRecurringItem(
                id: 't1',
                displayName: 'Gym Club',
                amount: 1200,
                ts: DateTime.utc(2026, 3, 5),
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: RecurringScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    expect(find.text('Marked recurring by you'), findsOneWidget);
    expect(find.text('Gym Club'), findsOneWidget);
    expect(find.byTooltip('Unmark recurring'), findsOneWidget);
  });

  test('markedRecurringProvider omits transactions covered by a series',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    Future<void> insert(String id, String raw, int day) async {
      final date = DateTime.utc(2026, 3, day);
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: date.millisecondsSinceEpoch,
              amount: 1200,
              direction: 'debit',
              channel: 'upi',
              merchantRaw: Value(raw),
              parseSource: 'template',
              confidenceJson: '{}',
              status: 'auto',
              recurringOverride: const Value('recurring'),
              createdAt: date,
              updatedAt: date,
            ),
          );
    }

    await insert('t1', 'Gym Club', 5);
    await insert('t2', 'Covered Co', 6);
    final covered = RecurringSery(
      id: 'sc',
      merchantId: 'merchant_evidence_COVEREDCO',
      label: 'Covered Co',
      expectedAmount: 1200,
      currencyCode: null,
      currencySymbol: null,
      tolerancePct: 0.05,
      period: 'monthly',
      periodDays: 30,
      nextExpectedDate: DateTime.utc(2026, 8, 1),
      lastAmount: 1200,
      amountTrend: 'flat',
      occurrences: 3,
      status: 'active',
      kind: 'subscription',
    );
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        recurringSeriesProvider.overrideWith(
          (ref) => Stream.value([RecurringSeriesItem(series: covered)]),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appDatabaseProvider.future);
    await container.read(recurringSeriesProvider.future);
    container.listen(markedRecurringProvider, (_, __) {});
    final items = await container.read(markedRecurringProvider.future);
    expect(items.map((i) => i.id), ['t1']);
    expect(items.single.displayName, 'Gym Club');
  });
}
