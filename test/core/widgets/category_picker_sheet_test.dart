import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/core/widgets/category_picker_sheet.dart';
import 'package:paisatrack/data/db/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const categories = [
    Category(
      id: 'food',
      name: 'Food & Dining',
      icon: 'restaurant',
      isSpending: true,
      sortOrder: 1,
      isUserCreated: false,
    ),
    Category(
      id: 'food_delivery',
      name: 'Food Delivery',
      parentId: 'food',
      icon: 'delivery_dining',
      isSpending: true,
      sortOrder: 2,
      isUserCreated: false,
    ),
    Category(
      id: 'transport',
      name: 'Transport',
      icon: 'directions_car',
      isSpending: true,
      sortOrder: 3,
      isUserCreated: false,
    ),
    Category(
      id: 'transfers',
      name: 'Transfers',
      icon: 'swap_horiz',
      isSpending: false,
      sortOrder: 4,
      isUserCreated: false,
    ),
  ];

  testWidgets('shows suggested categories, search, and current selection',
      (tester) async {
    Category? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                selected = await showModalBottomSheet<Category>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const CategoryPickerSheet(
                    categories: categories,
                    currentCategoryId: 'transport',
                    suggestedCategoryIds: ['food', 'transfers'],
                    explanations: {
                      'food': 'Previously used for this merchant',
                    },
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Choose category'), findsOneWidget);
    expect(find.text('SUGGESTED'), findsOneWidget);
    expect(find.text('Previously used for this merchant'), findsOneWidget);
    expect(find.text('Subcategory of Food & Dining'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'trans');
    await tester.pumpAndSettle();

    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Transfers'), findsOneWidget);
    expect(find.text('Food & Dining'), findsNothing);

    await tester.tap(find.text('Transfers').last);
    await tester.pumpAndSettle();

    expect(selected?.id, 'transfers');
  });

  testWidgets('T-145a: full-screen category picker with keyboard inset shows at least 8 rows',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final manyCategories = List.generate(
      15,
      (i) => Category(
        id: 'cat_$i',
        name: 'Category ${i + 1}',
        icon: 'category',
        isSpending: true,
        sortOrder: i,
        isUserCreated: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            viewInsets: const EdgeInsets.only(bottom: 240),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                showBloomFullScreenSheet<Category>(
                  context: context,
                  title: 'Select Category',
                  showBack: true,
                  builder: (ctx) => CategoryPickerSheet(
                    categories: manyCategories,
                    title: 'Select Category',
                  ),
                );
              },
              child: const Text('Open Picker'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    final rowFinder = find.byType(ListTile);
    expect(rowFinder.evaluate().length, greaterThanOrEqualTo(8));
  });
}
