import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/app_state_views.dart';

void main() {
  testWidgets('error state scrolls instead of overflowing at short heights',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 180,
              child: ErrorStateView(
                message: 'Could not load transactions.',
                onRetry: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
