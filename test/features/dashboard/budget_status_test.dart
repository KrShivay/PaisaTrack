import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';

void main() {
  group('BudgetStatus (owner report 2026-10-11)', () {
    // Budget 1,50,000; spent 1,70,597.32; bills 24,000; 11 Oct => 21 days.
    final status = BudgetStatus(
      budget: 150000,
      spent: 170597.32,
      commitments: 24000,
      daysRemaining: daysRemainingInMonth(DateTime(2026, 10, 11)),
    );

    test('days remaining counts today and matches the card', () {
      expect(daysRemainingInMonth(DateTime(2026, 10, 11)), 21);
      expect(daysRemainingInMonth(DateTime(2026, 10, 31)), 1);
      expect(daysRemainingInMonth(DateTime(2026, 10, 1)), 31);
    });

    test('over budget never shows a negative safe-to-spend amount', () {
      expect(status.isOver, isTrue);
      expect(status.safePerDay, 0);
      expect(status.overspent, closeTo(20597.32, 0.001));
      expect(status.left, closeTo(-44597.32, 0.001));
    });

    test('under budget divides what is left after bills by days left', () {
      const ok = BudgetStatus(
        budget: 150000,
        spent: 60000,
        commitments: 24000,
        daysRemaining: 22,
      );
      expect(ok.isOver, isFalse);
      expect(ok.left, 66000);
      expect(ok.safePerDay, 3000);
    });
  });
}
