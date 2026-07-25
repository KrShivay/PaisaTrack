import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/payee_label_repository.dart';
import 'package:paisatrack/features/settings/payee_labels_screen.dart';

void main() {
  testWidgets('filters payee identities by search query and unlabeled filter',
      (tester) async {
    const items = <PayeeIdentity>[
      PayeeIdentity(
        key: 'raw:swiggy food',
        displayName: 'Swiggy Food',
        userLabel: 'Swiggy',
        merchantId: 'm1',
        aliases: ['SWIGGY', 'SWIGGY INSTAMART'],
        transactionCount: 5,
      ),
      PayeeIdentity(
        key: 'raw:zomato delivery',
        displayName: 'Zomato Delivery',
        userLabel: null,
        merchantId: null,
        aliases: ['ZOMATO'],
        transactionCount: 2,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          payeeIdentitiesProvider.overrideWith((ref) => Stream.value(items)),
        ],
        child: const MaterialApp(home: PayeeLabelsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Swiggy Food'), findsOneWidget);
    expect(find.text('Zomato Delivery'), findsOneWidget);

    // Search query test
    await tester.enterText(
      find.byKey(const ValueKey('payee_labels_search_field')),
      'Zomato',
    );
    await tester.pumpAndSettle();

    expect(find.text('Swiggy Food'), findsNothing);
    expect(find.text('Zomato Delivery'), findsOneWidget);

    // Clear search
    await tester.enterText(
      find.byKey(const ValueKey('payee_labels_search_field')),
      '',
    );
    await tester.pumpAndSettle();

    // Filter by Unlabeled only
    await tester.tap(find.byKey(const ValueKey('unlabeled_filter_chip')));
    await tester.pumpAndSettle();

    expect(find.text('Swiggy Food'), findsNothing);
    expect(find.text('Zomato Delivery'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
