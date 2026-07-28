import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/category_visuals.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_category_tile.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/recurring/recurring_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Recurring Series Category Tint (T-146b)', () {
    testWidgets('recurring row for a food merchant carries the food hue, not slate', (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final foodSeries = RecurringSery(
        id: 'series_food_001',
        merchantId: 'm_swiggy',
        label: 'Swiggy One',
        expectedAmount: 149.0,
        tolerancePct: 0.1,
        period: 'monthly',
        periodDays: 30,
        nextExpectedDate: now.add(const Duration(days: 5)),
        lastAmount: 149.0,
        amountTrend: 'stable',
        occurrences: 4,
        status: 'active',
        kind: 'subscription',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recurringSeriesProvider.overrideWith(
              (ref) => Stream.value([
                RecurringSeriesItem(
                  series: foodSeries,
                  categoryHint: 'food_dining',
                ),
              ]),
            ),
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

      final tileFinder = find.byType(BloomCategoryTile);
      expect(tileFinder, findsAtLeast(1));
      final tileWidget = tester.widgetList<BloomCategoryTile>(tileFinder).first;

      // Verify categoryId passed to BloomCategoryTile is resolved food_dining, not subscription or null
      expect(tileWidget.categoryId, equals('food_dining'));

      // Verify Color resolved by CategoryVisuals.color is food hue (0xFFF97316), not slate (0xFF94A3B8)
      final resolvedColor = CategoryVisuals.color(tileWidget.categoryId);
      expect(resolvedColor, equals(const Color(0xFFF97316)));
      expect(resolvedColor, isNot(equals(CategoryVisuals.fallbackColor)));
    });
  });
}
