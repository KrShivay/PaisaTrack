import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/theme/category_visuals.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_category_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BloomCategoryTile Icon Resolution (T-146a)', () {
    testWidgets('resolves explicit iconName correctly (e.g. restaurant)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BloomCategoryTile(
              categoryId: 'food_dining',
              iconName: 'restaurant',
            ),
          ),
        ),
      );

      final iconFinder = find.byType(Icon);
      expect(iconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.icon, equals(Icons.restaurant));
    });

    testWidgets('falls back to categoryId mapped icon when iconName is null (food -> Icons.restaurant)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BloomCategoryTile(
              categoryId: 'food_dining',
              iconName: null,
            ),
          ),
        ),
      );

      final iconFinder = find.byType(Icon);
      expect(iconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.icon, equals(Icons.restaurant));
      expect(iconWidget.icon, isNot(equals(CategoryVisuals.fallbackIcon)));
    });

    testWidgets('groceries category falls back to Icons.local_grocery_store', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BloomCategoryTile(
              categoryId: 'groceries',
            ),
          ),
        ),
      );

      final iconWidget = tester.widget<Icon>(find.byType(Icon));
      expect(iconWidget.icon, equals(Icons.local_grocery_store));
    });

    testWidgets('transport category falls back to Icons.directions_car', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BloomCategoryTile(
              categoryId: 'transport',
            ),
          ),
        ),
      );

      final iconWidget = tester.widget<Icon>(find.byType(Icon));
      expect(iconWidget.icon, equals(Icons.directions_car));
    });
  });
}
