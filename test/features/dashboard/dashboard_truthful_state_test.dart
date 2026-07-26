import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/features/dashboard/dashboard_screen.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/dashboard/streak_provider.dart';

void main() {
  testWidgets(
      'DashboardScreen renders dynamic greeting and non-hardcoded streak',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: DashboardScreen(),
        ),
      ),
    );

    // Verify sample hardcoded string 'Hey Shivay' does not appear
    expect(find.text('Hey Shivay'), findsNothing);

    // Verify hardcoded 'Lighter week than usual' does not appear
    expect(find.text('Lighter week than usual'), findsNothing);

    // Verify fallback hardcoded 6 day streak does not appear by default (defaults to 0 or derived)
    expect(find.text('6 day streak'), findsNothing);
    expect(find.textContaining('day streak'), findsOneWidget);
  });

  test('dashboardGreetingProvider returns valid non-empty greeting', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final greeting = container.read(dashboardGreetingProvider);
    expect(greeting, isNotEmpty);
    expect(greeting.startsWith('Good '), isTrue);
  });

  test('streakProvider returns 0 by default when no settings exist', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final streak = container.read(streakProvider);
    expect(streak, equals(0));
  });
}
