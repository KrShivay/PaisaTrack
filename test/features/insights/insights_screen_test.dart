import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';

void main() {
  Insight insight(String id, String kind, Map<String, Object?> payload) =>
      Insight(
        id: id,
        period: '${DateTime.now().year}-'
            '${DateTime.now().month.toString().padLeft(2, '0')}',
        kind: kind,
        payloadJson: jsonEncode(payload),
        dismissed: false,
      );

  Future<void> pumpRows(WidgetTester tester, List<Insight> rows) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeInsightsProvider.overrideWith((ref) => Stream.value(rows)),
          transactionListProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows designed empty state', (tester) async {
    await pumpRows(tester, const []);
    expect(find.text('No unusual changes detected'), findsOneWidget);
    expect(find.textContaining('currently consistent'), findsOneWidget);
  });

  testWidgets('renders report, suggestions, and anomaly explanations',
      (tester) async {
    await pumpRows(tester, [
      insight('forecast', 'forecast', {
        'projected_spend': 1200,
        'deviation_fraction': 0.2,
      }),
      insight('anomaly', 'anomaly', {
        'aggregate': 900,
        'threshold': 500,
        'top_transaction_ids': ['secret_internal_id'],
      }),
      insight('duplicate', 'duplicate_subscription', {
        'label': 'Streaming',
        'monthly_total': 700,
      }),
      insight('fees', 'fees_total', {'total': 125, 'count': 2}),
    ]);

    expect(find.textContaining('overview'), findsOneWidget);
    expect(find.text('Month-end forecast'), findsOneWidget);
    expect(find.text('Unusual spending detected'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Possible duplicate subscription'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Possible duplicate subscription'), findsOneWidget);
    expect(find.text('Fees and penalties'), findsOneWidget);
    expect(find.text('secret_internal_id'), findsNothing);
  });

  testWidgets('shows deterministic analytics without generated insights',
      (tester) async {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month, 5).toUtc();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeInsightsProvider.overrideWith((ref) => Stream.value(const [])),
          transactionListProvider.overrideWith(
            (ref) => Stream.value([
              TransactionListItem(
                id: 'txn_food',
                ts: current,
                amount: 610.83,
                direction: TransactionDirection.debit,
                displayName: 'Zomato',
                categoryName: 'Food & Dining',
                categoryId: 'food',
                categoryIcon: 'restaurant',
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Monthly spending'), findsOneWidget);
    expect(find.text('₹610.83'), findsWidgets);
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('Top merchants'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No unusual changes detected'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No unusual changes detected'), findsOneWidget);
  });

  testWidgets('dismiss control persists the hidden state', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now();
    final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    await database.into(database.insights).insert(
          InsightsCompanion.insert(
            id: 'fees:$period',
            period: period,
            kind: 'fees_total',
            payloadJson: jsonEncode({'total': 25, 'count': 1}),
          ),
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          activeInsightsProvider.overrideWith(
            (ref) => Stream.value([
              insight('fees:$period', 'fees_total', {
                'total': 25,
                'count': 1,
              }),
            ]),
          ),
          transactionListProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Dismiss Fees and penalties'));
    await tester.pumpAndSettle();

    expect(
      (await database.select(database.insights).getSingle()).dismissed,
      isTrue,
    );
    expect(find.text('Insight dismissed'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  });
}
