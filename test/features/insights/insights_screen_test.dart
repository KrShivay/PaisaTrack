import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';

void main() {
  test('insight period key uses the period calendar across UTC month edge', () {
    const calendar = FinancialCalendar.fixed(
      Duration(hours: 5, minutes: 30),
    );
    final period = DashboardPeriod.month(
      DateTime.utc(2026, 10, 15, 12),
      calendar: calendar,
    );

    expect(period.start, DateTime.utc(2026, 9, 30, 18, 30));
    expect(insightMonthKeyForPeriod(period), '2026-10');
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(402, 874),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardAggregateProvider
              .overrideWith((ref) async => _emptyDashboardAggregate),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: const InsightsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('renders Bloom Trends header and 6-month spend chart',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Trends'), findsOneWidget);
    expect(find.text('SPEND TREND (LAST 6 MONTHS)'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('MONTH OVER MONTH'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MONTH OVER MONTH'), findsOneWidget);
  });

  testWidgets('unknown and injected narrative rows never render',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const injected = Insight(
      id: 'narrative:2026-07',
      period: '2026-07',
      kind: 'narrative',
      payloadJson: '{"body":"Injected LLM prose should not render"}',
      dismissed: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardAggregateProvider
              .overrideWith((ref) async => _emptyDashboardAggregate),
          trendsInboxEnabledProvider.overrideWith((ref) => false),
          activeInsightsProvider
              .overrideWith((ref) => Stream.value([injected])),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Injected LLM prose'), findsNothing);
  });

  testWidgets('rollback flag keeps the existing fresh insight feed',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const claimId = 'fees_total:2026-10:phone:INR';
    final claim = {
      'v': 1,
      'calc': 'fees_total@1',
      'claim_id': claimId,
      'basis': 'observed',
      'scope': {
        'category_ids': ['phone'],
        'currency_code': 'INR',
        'currency_symbol': '₹',
      },
      'window': {
        'current': ['2026-10-01', '2026-10-15'],
        'previous': null,
        'partial': true,
      },
      'metrics': {'total': 12.0},
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
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardAggregateProvider
              .overrideWith((ref) async => _emptyDashboardAggregate),
          trendsInboxEnabledProvider.overrideWith((ref) => false),
          activeInsightsProvider.overrideWith(
            (ref) => Stream.value([
              Insight(
                id: claimId,
                period: '2026-10',
                kind: 'fees_total',
                payloadJson: jsonEncode({'claim': claim}),
                dismissed: false,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Recorded fees'), findsOneWidget);
    expect(find.text('INSIGHTS'), findsNothing);
  });

  testWidgets(
      'claim title names include nested categories outside the spend mix',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'parent_food',
            name: 'Food',
            icon: 'food',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: true,
          ),
        );
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'custom_child',
            name: 'Child Food',
            parentId: const Value('parent_food'),
            icon: 'category',
            isSpending: true,
            sortOrder: 2,
            isUserCreated: true,
          ),
        );
    final period = insightMonthKeyForPeriod(
      DashboardPeriod.month(DateTime.now()),
    );
    final periodParts = period.split('-').map(int.parse).toList();
    final previousDate = DateTime(periodParts[0], periodParts[1] - 1);
    final previousPeriod = '${previousDate.year.toString().padLeft(4, '0')}-'
        '${previousDate.month.toString().padLeft(2, '0')}';
    final claimId = 'category_delta:$period:custom_child:INR';
    final claim = {
      'v': 1,
      'calc': 'category_delta@1',
      'claim_id': claimId,
      'basis': 'observed',
      'scope': {
        'category_id': 'custom_child',
        'currency_code': 'INR',
        'currency_symbol': '₹',
      },
      'window': {
        'current': ['$period-01', '$period-10'],
        'previous': ['$previousPeriod-01', '$previousPeriod-10'],
        'partial': true,
      },
      'metrics': {
        'current_total': 0.0,
        'previous_total': 12345.0,
        'delta_fraction': -1.0,
      },
      'evidence': {
        'ids': ['previous_row'],
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
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          dashboardAggregateProvider
              .overrideWith((ref) async => _emptyDashboardAggregate),
          trendsInboxEnabledProvider.overrideWith((ref) => false),
          activeInsightsProvider.overrideWith(
            (ref) => Stream.value([
              Insight(
                id: claimId,
                period: period,
                kind: 'category_delta',
                payloadJson: jsonEncode({'claim': claim}),
                dismissed: false,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Child Food spending'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await database.close();
  });

  testWidgets('Why opens exactly claim evidence and labels truncation',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final database = AppDatabase(NativeDatabase.memory());
    Set<String>? requestedIds;
    TransactionListItem evidenceRow(String id, String name, double amount) =>
        TransactionListItem(
          id: id,
          ts: DateTime.utc(2026, 7, 2),
          amount: amount,
          direction: TransactionDirection.debit,
          displayName: name,
          categoryName: 'Food',
          categoryId: 'food',
          categoryIcon: 'food',
        );
    const claimId = 'category_delta:2026-07:food:INR';
    final claimRow = Insight(
      id: claimId,
      period: '2026-07',
      kind: 'category_delta',
      dismissed: false,
      payloadJson: jsonEncode({
        'claim': {
          'v': 1,
          'calc': 'category_delta@1',
          'claim_id': claimId,
          'basis': 'observed',
          'scope': {
            'category_id': 'food',
            'currency_code': 'INR',
            'currency_symbol': '₹',
          },
          'window': {
            'current': ['2026-07-01', '2026-07-10'],
            'previous': ['2026-06-01', '2026-06-10'],
            'partial': true,
          },
          'metrics': {
            'current_total': 150,
            'previous_total': 100,
            'delta_fraction': 0.5,
          },
          'evidence': {
            'ids': ['evidence_a', 'evidence_b'],
            'total_count': 3,
            'truncated': true,
          },
          'coverage': {
            'rows': 4,
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
          'input_hash': '0000000000000000',
        },
      }),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          dashboardAggregateProvider
              .overrideWith((ref) async => _emptyDashboardAggregate),
          trendsInboxEnabledProvider.overrideWith((ref) => false),
          activeInsightsProvider
              .overrideWith((ref) => Stream.value([claimRow])),
          evidenceTransactionPageProvider.overrideWith((ref, filters) {
            requestedIds = filters.ids;
            return Stream.value(
              ActivityTransactionPage(
                rows: [
                  evidenceRow('evidence_a', 'Evidence A', 100),
                  evidenceRow('evidence_b', 'Evidence B', 150),
                ],
                hasMore: false,
              ),
            );
          }),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Why?'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(find.text('Showing 2 of 3 supporting transactions'), findsOneWidget);
    expect(find.text('Evidence A'), findsOneWidget);
    expect(find.text('Evidence B'), findsOneWidget);
    expect(requestedIds, {'evidence_a', 'evidence_b'});
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });

  testWidgets('offers retry when analytics fail and recovers on retry',
      (tester) async {
    var attempts = 0;
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardAggregateProvider.overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw StateError('offline');
            return _emptyDashboardAggregate;
          }),
          activeInsightsProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(home: InsightsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Couldn't load spending analytics."), findsOneWidget);
    expect(find.textContaining('Pull to refresh'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(attempts, 2);
    expect(find.text("Couldn't load spending analytics."), findsNothing);
    expect(find.text('SPEND TREND (LAST 6 MONTHS)'), findsOneWidget);
  });

  for (final size in [const Size(320, 568), const Size(600, 900)]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets(
        'Trends has no overflow at ${size.width.toInt()}px and $scale× text',
        (tester) async {
          await pumpScreen(tester, size: size, textScale: scale);

          expect(find.text('Trends'), findsOneWidget);
          if (scale >= 1.5) {
            final recurring = find.byTooltip('Recurring transactions');
            expect(recurring, findsOneWidget);
            expect(tester.getSize(recurring), const Size(48, 48));
          } else {
            expect(find.text('Recurring'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

const _emptyDashboardAggregate = DashboardAggregateSnapshot(
  debitTotal: 0,
  creditTotal: 0,
  previousSpend: 0,
  categories: [],
  merchants: [],
  trendByMonth: {},
);
