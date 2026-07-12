import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';

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

    expect(find.textContaining('report'), findsOneWidget);
    expect(find.text('Month-end forecast'), findsOneWidget);
    expect(find.text('Unusual spending detected'), findsOneWidget);
    expect(find.text('Possible duplicate subscription'), findsOneWidget);
    expect(find.text('Fees and penalties'), findsOneWidget);
    expect(find.text('secret_internal_id'), findsNothing);
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
