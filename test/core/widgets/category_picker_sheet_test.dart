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

    expect(find.text('MATCHES (2)'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Transfers'), findsOneWidget);
    expect(find.text('Food & Dining'), findsNothing);

    await tester.tap(find.text('Transfers').last);
    await tester.pumpAndSettle();

    expect(selected?.id, 'transfers');
  });

  testWidgets(
      'T-145b: pinned search field remains visible while scrolling and result count is shown',
      (tester) async {
    final manyCategories = List.generate(
      20,
      (i) => Category(
        id: 'cat_$i',
        name: 'Item Category ${i + 1}',
        icon: 'category',
        isSpending: true,
        sortOrder: i,
        isUserCreated: false,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
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

    // Enter query matching 20 items
    await tester.enterText(find.byType(TextField), 'Item');
    await tester.pumpAndSettle();

    // Verify result count next to Matches section label
    expect(find.text('MATCHES (20)'), findsOneWidget);

    // Scroll down list
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    // Search field remains pinned at top and visible
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('T-145a: honours keyboard insets', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 250)),
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: CategoryPickerSheet(
              title: 'Picker',
              categories: categories,
              currentCategoryId: 'food',
            ),
          ),
        ),
      ),
    );

    final paddings = tester.widgetList<Padding>(
      find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Padding),
      ),
    );

    expect(paddings.last.padding.resolve(TextDirection.ltr).bottom, 266);
  });
}
