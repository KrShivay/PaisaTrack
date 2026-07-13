import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/settings/category_manager_screen.dart';

void main() {
  testWidgets('suggests an icon on create and allows editing it',
      (tester) async {
    CategoryEditorResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CategoryEditorDialog(
            title: 'Add category',
            onSave: (value) => saved = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'Cigarette');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Create category'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create category'),
    );
    expect(saved?.name, 'Cigarette');
    expect(saved?.icon, 'smoking_rooms');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('category_icon_local_cafe')),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('category_icon_local_cafe')));
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Create category'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(
      find.widgetWithText(FilledButton, 'Create category'),
    );
    expect(saved?.icon, 'local_cafe');
  });

  testWidgets('blocks duplicate names and exposes category type',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryEditorDialog(
            title: 'Create category',
            existingNames: {'Groceries'},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'groceries');
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Create category'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create category'));
    await tester.pump();

    expect(
      find.text('A category with this name already exists'),
      findsOneWidget,
    );
    expect(find.text('Transfer / excluded'), findsOneWidget);
  });

  testWidgets('manager searches categories and uses one overflow per row',
      (tester) async {
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
        id: 'custom',
        name: 'Coffee Runs',
        icon: 'local_cafe',
        isSpending: true,
        sortOrder: 2,
        isUserCreated: true,
      ),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryManagerListProvider.overrideWith(
            (ref) => Stream.value(categories),
          ),
        ],
        child: const MaterialApp(home: CategoryManagerScreen()),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.more_vert), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), 'coffee');
    await tester.pump();

    expect(find.text('Coffee Runs'), findsOneWidget);
    expect(find.text('Food & Dining'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });
}
