import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/category_visuals.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/recurring/recurring_screen.dart';

void main() {
  RecurringSery series({
    String id = 'series_1',
    String label = 'Netflix',
    String kind = 'subscription',
    String status = 'active',
  }) {
    return RecurringSery(
      id: id,
      merchantId: 'merchant_$id',
      label: label,
      expectedAmount: 499,
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

  testWidgets('renders recharge and investment kinds with valid visuals', (tester) async {
    await pumpScreen(tester, [
      series(id: '3', label: 'Jio', kind: 'recharge'),
      series(id: '4', label: 'Mutual Fund', kind: 'investment'),
    ]);

    expect(find.text('Jio'), findsAtLeast(1));
    expect(find.text('Mutual Fund'), findsAtLeast(1));
    
    // Check that we find tiles (may be 4 due to dual-rendering in upcoming + all sections)
    final tiles = tester.widgetList<BloomCategoryTile>(find.byType(BloomCategoryTile));
    expect(tiles.length, greaterThanOrEqualTo(2));

    // Verify neither resolved to fallback color (0xFF94A3B8)
    for (final tile in tiles) {
      expect(CategoryVisuals.color(tile.categoryId).toARGB32(), isNot(0xFF94A3B8));
    }
  });
}
