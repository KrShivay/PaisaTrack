import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/data/repositories/trends_inbox_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/home/home_shell.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';
import 'package:paisatrack/intelligence/claim.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'default inbox renders and Clear all is reversible via UndoController',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = _container(database);
    await _pumpInbox(tester, container);

    expect(find.text('Recorded fees'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Recorded fees'), findsNothing);
    expect(
      container.read(undoControllerProvider)?.id,
      'trends-inbox-clear-all',
    );

    expect(
      await container.read(undoControllerProvider.notifier).undo(),
      isTrue,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Recorded fees'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await database.close();
  });

  testWidgets(
      'History entry points keep cleared items reachable and restorable',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = _container(database);
    await _pumpInbox(tester, container);

    expect(find.text('History'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Recorded fees'), findsNothing);
    expect(find.text('View insight history (1)'), findsOneWidget);

    await tester.tap(find.text('View insight history (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Insight history'), findsOneWidget);
    expect(find.text('Recorded fees'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsOneWidget);

    Navigator.of(tester.element(find.text('Insight history'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Recorded fees'), findsOneWidget);
    expect(find.text('View insight history (1)'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await database.close();
  });

  testWidgets('period selection renders only claims for the selected period',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final container = _container(database);
    await _pumpInbox(tester, container);
    final current = insightMonthKeyForPeriod(
      container.read(dashboardPeriodProvider),
    );
    final previous = DateTime(
      int.parse(current.substring(0, 4)),
      int.parse(current.substring(5, 7)) - 1,
    );

    await tester.tap(find.text(container.read(dashboardPeriodProvider).label));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Previous month'));
    await tester.pumpAndSettle();

    expect(find.text('Recorded fees'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    final repository = TrendsInboxRepository(database);
    final previousKey =
        insightMonthKeyForPeriod(DashboardPeriod.month(previous));
    expect((await repository.readPeriod(previousKey)).single.isCurrent, isTrue);
    expect((await repository.readPeriod(current)).single.isCurrent, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await database.close();
  });

  test('period change skips a reconcile that still has prior-period claims',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = TrendsInboxRepository(database);
    await repository.reconcile(
      period: '2026-10',
      freshClaims: [_feesClaim('2026-10')],
    );
    await repository.reconcile(
      period: '2026-11',
      freshClaims: [_feesClaim('2026-11')],
    );
    final claims = StreamController<List<Insight>>.broadcast();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        dashboardPeriodProvider.overrideWith(
          (ref) => DashboardPeriod.month(DateTime(2026, 10, 15)),
        ),
        activeInsightsProvider.overrideWith((ref) {
          ref.watch(dashboardPeriodProvider);
          return claims.stream;
        }),
      ],
    );
    final subscription = container.listen(
      trendsInboxItemsProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(() async {
      subscription.close();
      await claims.close();
      container.dispose();
      await database.close();
    });
    await Future<void>.delayed(Duration.zero);
    claims.add([_feesClaim('2026-10')]);
    await container.read(trendsInboxItemsProvider.future);

    container.read(dashboardPeriodProvider.notifier).state =
        DashboardPeriod.month(DateTime(2026, 11, 15));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      (await repository.readPeriod('2026-11')).single.isCurrent,
      isTrue,
    );
  });

  testWidgets('stale inbox snapshots remain stored but are not rendered',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final currentPeriod = insightMonthKeyForPeriod(
      DashboardPeriod.month(DateTime.now()),
    );
    final repository = TrendsInboxRepository(database);
    await repository.reconcile(
      period: currentPeriod,
      freshClaims: [_feesClaim(currentPeriod)],
    );
    await repository.reconcile(period: currentPeriod, freshClaims: const []);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        dashboardAggregateProvider.overrideWith(
          (ref) async => const DashboardAggregateSnapshot(
            debitTotal: 0,
            creditTotal: 0,
            previousSpend: 0,
            categories: [],
            merchants: [],
            trendByMonth: {},
          ),
        ),
        activeInsightsProvider.overrideWith((ref) => Stream.value(const [])),
      ],
    );
    await _pumpInbox(tester, container);

    expect(await repository.readPeriod(currentPeriod), hasLength(1));
    expect(find.text('Recorded fees'), findsNothing);
    expect(find.textContaining('No longer current'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await database.close();
  });

  testWidgets(
      'New remains visible during a Trends visit and clears on tab leave',
      (tester) async {
    var seenCalls = 0;
    final container = _shellInboxContainer(() async {
      seenCalls++;
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final newBadge = _semanticsLabel('Trends, 1 new insights');
    expect(
      newBadge,
      findsOneWidget,
      reason:
          'Inbox state: ${container.read(trendsInboxItemsProvider).valueOrNull?.map((item) => '${item.state}/${item.isCurrent}').toList()}; count: ${tester.widget<HomeFloatingNavPill>(find.byType(HomeFloatingNavPill)).trendsNewCount}',
    );
    await tester.tap(newBadge);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('New'), findsOneWidget);
    expect(_semanticsLabel('Trends, 1 new insights'), findsOneWidget);

    await tester.tap(_semanticsLabel('Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(seenCalls, 1);
    expect(_semanticsLabel('Trends'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });

  testWidgets('backgrounding Trends marks its new items once', (tester) async {
    var seenCalls = 0;
    final container = _shellInboxContainer(() async {
      seenCalls++;
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomeShell()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(_semanticsLabel('Trends, 1 new insights'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(seenCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });
}

Finder _semanticsLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == label,
    );

final _shellInboxStateProvider =
    StateProvider<TrendsInboxState>((ref) => TrendsInboxState.newItem);

ProviderContainer _shellInboxContainer(Future<void> Function() onSeen) {
  final period =
      insightMonthKeyForPeriod(DashboardPeriod.month(DateTime.now()));
  final insight = _feesClaim(period);
  final item = TrendsInboxItem(
    key: 'new-claim',
    state: TrendsInboxState.newItem,
    isCurrent: true,
    insight: insight,
    claim: const ClaimValidator().parse(insight)!,
  );
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith(
        (ref) => Completer<AppDatabase>().future,
      ),
      trendsInboxItemsProvider.overrideWith((ref) {
        final state = ref.watch(_shellInboxStateProvider);
        return Stream.value([
          TrendsInboxItem(
            key: item.key,
            state: state,
            isCurrent: item.isCurrent,
            insight: item.insight,
            claim: item.claim,
          ),
        ]);
      }),
      markTrendsInboxSeenProvider.overrideWith(
        (ref) => (keys) async {
          expect(keys, ['new-claim']);
          await onSeen();
          ref.read(_shellInboxStateProvider.notifier).state =
              TrendsInboxState.seen;
        },
      ),
    ],
  );
}

ProviderContainer _container(AppDatabase database) => ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        dashboardAggregateProvider.overrideWith(
          (ref) async => const DashboardAggregateSnapshot(
            debitTotal: 0,
            creditTotal: 0,
            previousSpend: 0,
            categories: [],
            merchants: [],
            trendByMonth: {},
          ),
        ),
        activeInsightsProvider.overrideWith((ref) {
          final period = insightMonthKeyForPeriod(
            ref.watch(dashboardPeriodProvider),
          );
          return Stream.value([_feesClaim(period)]);
        }),
      ],
    );

Future<void> _pumpInbox(
  WidgetTester tester,
  ProviderContainer container,
) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: InsightsScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Insight _feesClaim(String period) {
  final id = 'fees_total:$period:phone:INR';
  return Insight(
    id: id,
    period: period,
    kind: 'fees_total',
    payloadJson: jsonEncode({
      'claim': {
        'v': 1,
        'calc': 'fees_total@1',
        'claim_id': id,
        'basis': 'observed',
        'scope': {
          'category_ids': ['phone'],
          'currency_code': 'INR',
          'currency_symbol': '₹',
        },
        'window': {
          'current': ['$period-01', '$period-15'],
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
      },
    }),
    dismissed: false,
  );
}
