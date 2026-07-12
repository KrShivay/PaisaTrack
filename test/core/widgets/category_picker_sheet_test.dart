import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/category_picker_sheet.dart';
import 'package:paisatrack/data/db/database.dart';

void main() {
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
      id: 'transport',
      name: 'Transport',
      icon: 'directions_car',
      isSpending: true,
      sortOrder: 2,
      isUserCreated: false,
    ),
    Category(
      id: 'transfers',
      name: 'Transfers',
      icon: 'swap_horiz',
      isSpending: false,
      sortOrder: 3,
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
}
