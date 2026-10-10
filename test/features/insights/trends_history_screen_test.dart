import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/trends_inbox_repository.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';
import 'package:paisatrack/features/insights/trends_history_screen.dart';

void main() {
  late AppDatabase database;
  late TrendsInboxRepository repository;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = TrendsInboxRepository(database);
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        trendsInboxItemsProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
  });

  Future<void> seed() async {
    await repository.reconcile(
      period: '2026-09',
      freshClaims: [_claim('fees_total', '2026-09')],
    );
    await repository.reconcile(
      period: '2026-10',
      freshClaims: [
        _claim('fees_total', '2026-10'),
        _claim('category_delta', '2026-10'),
      ],
    );
    final all = await repository.readAll();
    final septemberKey =
        all.firstWhere((i) => i.insight.period == '2026-09').key;
    await repository.clear(septemberKey);
    final octoberFees = all.firstWhere(
      (i) => i.insight.period == '2026-10' && i.insight.kind == 'fees_total',
    );
    await repository.moveToLater(octoberFees.key);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await database.close();
  }

  // Drift completes queries on real time, so give it a real tick per frame.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpHistory(WidgetTester tester) async {
    await tester.runAsync(seed);
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TrendsHistoryScreen()),
      ),
    );
    await settle(tester);
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Finder chip(String label) => find.widgetWithText(ChoiceChip, label);

  testWidgets('lists every retained item grouped by month, newest first',
      (tester) async {
    await pumpHistory(tester);

    expect(find.text('OCTOBER 2026'), findsOneWidget);
    expect(find.text('SEPTEMBER 2026'), findsOneWidget);
    expect(find.text('Recorded fees'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('OCTOBER 2026')).dy,
      lessThan(tester.getTopLeft(find.text('SEPTEMBER 2026')).dy),
    );
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Clear'), findsNWidgets(2));
    await finish(tester);
  });

  testWidgets('state, month and type filters narrow the list with empty state',
      (tester) async {
    await pumpHistory(tester);

    await tapAndSettle(tester, chip('Later'));
    expect(find.text('Recorded fees'), findsOneWidget);
    expect(find.text('Restore'), findsNothing);

    await tapAndSettle(tester, chip('All'));
    await tapAndSettle(tester, chip('September 2026'));
    expect(find.text('OCTOBER 2026'), findsNothing);
    expect(find.text('Recorded fees'), findsOneWidget);

    await tapAndSettle(tester, chip('All months'));
    await tapAndSettle(tester, chip('Category delta'));
    expect(find.text('Recorded fees'), findsNothing);
    expect(find.text('SEPTEMBER 2026'), findsNothing);
    expect(find.text('OCTOBER 2026'), findsOneWidget);

    await tapAndSettle(tester, chip('Cleared'));
    expect(find.text('No insights match these filters.'), findsOneWidget);
    expect(chip('Fees total'), findsOneWidget);
    expect(chip('Missing type'), findsNothing);
    await finish(tester);
  });

  testWidgets('Restore returns a cleared item to the live inbox',
      (tester) async {
    await pumpHistory(tester);
    await tapAndSettle(tester, chip('Cleared'));
    expect(find.text('Recorded fees'), findsOneWidget);

    await tapAndSettle(tester, find.text('Restore'));

    expect(find.text('No insights match these filters.'), findsOneWidget);
    final september = container
        .read(trendsInboxHistoryProvider)
        .requireValue
        .firstWhere((i) => i.insight.period == '2026-09');
    expect(september.state, TrendsInboxState.seen);
    await finish(tester);
  });

  testWidgets('Clear moves a non-cleared item into Cleared', (tester) async {
    await pumpHistory(tester);
    await tapAndSettle(tester, chip('Later'));

    await tapAndSettle(tester, find.text('Clear'));

    expect(find.text('No insights match these filters.'), findsOneWidget);
    await tapAndSettle(tester, chip('Cleared'));
    expect(find.text('Recorded fees'), findsNWidgets(2));
    await finish(tester);
  });

  test('filter and grouping helpers', () async {
    await seed();
    final all = await repository.readAll();
    expect(
      filterTrendsHistory(all, state: TrendsHistoryStateFilter.cleared),
      hasLength(1),
    );
    expect(
      filterTrendsHistory(all, kind: 'fees_total', period: '2026-10'),
      hasLength(1),
    );
    expect(
      groupTrendsHistoryByPeriod(all).map((g) => g.key).toList(),
      ['2026-10', '2026-09'],
    );
    container.dispose();
    await database.close();
  });
}

Insight _claim(String kind, String period) {
  final id = '$kind:$period:food:INR';
  final isDelta = kind == 'category_delta';
  return Insight(
    id: id,
    period: period,
    kind: kind,
    payloadJson: jsonEncode({
      'claim': {
        'v': 1,
        'calc': '$kind@1',
        'claim_id': id,
        'basis': 'observed',
        'scope': isDelta
            ? {
                'category_id': 'food',
                'currency_code': 'INR',
                'currency_symbol': '₹',
              }
            : {
                'category_ids': ['food'],
                'currency_code': 'INR',
                'currency_symbol': '₹',
              },
        'window': {
          'current': ['$period-01', '$period-15'],
          'previous': isDelta ? ['$period-01', '$period-15'] : null,
          'partial': true,
        },
        'metrics': isDelta
            ? {
                'current_total': 120.0,
                'previous_total': 100.0,
                'delta_fraction': 0.2,
              }
            : {'total': 12.0},
        'evidence': {
          'ids': ['txn-1'],
          'total_count': 1,
          'truncated': false,
        },
        'coverage': {
          'rows': 1,
          'unreviewed': 0,
          'unknown_currency': 0,
          'excluded': {
            'not_settled': 0,
            'owned_transfer': 0,
            'analytics_excluded': 0,
            'non_spending': 0,
            'credit': 0,
          },
        },
        'input_hash': '0123456789abcdef',
      },
    }),
    dismissed: false,
  );
}
