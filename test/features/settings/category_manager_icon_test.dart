import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    await tester.enterText(find.byType(TextField), 'Cigarette');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    expect(saved?.name, 'Cigarette');
    expect(saved?.icon, 'smoking_rooms');

    await tester.tap(find.byKey(const ValueKey('category_icon_local_cafe')));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    expect(saved?.icon, 'local_cafe');
  });
}
