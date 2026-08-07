import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/shadow_pipeline.dart';

void main() {
  const calculator = ShadowDiffCalculator();

  test('identical snapshots produce an empty diff', () {
    final production = [
      const ProductionSnapshot(
        sourceId: 'sms_1',
        amountPaise: 44900,
        direction: 'debit',
        merchantKey: 'merchant:food',
        categoryId: 'food_dining',
      ),
    ];

    final diff = calculator.compare(
      production: production,
      shadow: [
        const ShadowSnapshot(
          sourceId: 'sms_1',
          outcome: ShadowOutcome.parsed,
          amountPaise: 44900,
          direction: 'debit',
          merchantKey: 'merchant:food',
          categoryId: 'food_dining',
        ),
      ],
    );

    expect(diff.isEmpty, isTrue);
    expect(diff.differences, isEmpty);
  });

  test('counts gained, lost, amount, and label differences once', () {
    final diff = calculator.compare(
      production: const [
        ProductionSnapshot(
          sourceId: 'sms_lost',
          amountPaise: 100,
          direction: 'debit',
        ),
        ProductionSnapshot(
          sourceId: 'sms_amount',
          amountPaise: 100,
          direction: 'debit',
          categoryId: 'food_dining',
        ),
        ProductionSnapshot(
          sourceId: 'sms_label',
          amountPaise: 200,
          direction: 'debit',
          categoryId: 'food_dining',
        ),
      ],
      shadow: const [
        ShadowSnapshot(
          sourceId: 'sms_lost',
          outcome: ShadowOutcome.unparsed,
        ),
        ShadowSnapshot(
          sourceId: 'sms_amount',
          outcome: ShadowOutcome.parsed,
          amountPaise: 120,
          direction: 'debit',
          categoryId: 'food_dining',
        ),
        ShadowSnapshot(
          sourceId: 'sms_label',
          outcome: ShadowOutcome.parsed,
          amountPaise: 200,
          direction: 'credit',
          categoryId: 'transport',
        ),
        ShadowSnapshot(
          sourceId: 'sms_gained',
          outcome: ShadowOutcome.parsed,
          amountPaise: 300,
          direction: 'debit',
        ),
      ],
    );

    expect(diff.gained, 1);
    expect(diff.lost, 1);
    expect(diff.amountDeltas, 1);
    expect(diff.labelDisagreements, 1);
    expect(diff.differences, hasLength(4));
  });
}
