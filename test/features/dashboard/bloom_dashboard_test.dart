import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/budget_repository.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/dashboard/dashboard_screen.dart';
import 'package:paisatrack/features/dashboard/dashboard_widgets.dart';
import '../../support/drift_widget_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDashboard(
    WidgetTester tester,
    AppDatabase database, {
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
          appDatabaseProvider.overrideWith((ref) async => database),
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
          home: const BloomUndoToastHost(child: DashboardScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Bloom DashboardScreen', () {
    testWidgets('renders greeting, mascot, and streak chip', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await pumpDashboard(tester, database);

      expect(find.textContaining('Good '), findsOneWidget);
      expect(find.textContaining('streak'), findsOneWidget);
      expect(find.byType(BloomMascot), findsOneWidget);

      await database.close();
    });

    testWidgets('renders Hero Ring and metric switcher pills', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await pumpDashboard(tester, database);

      expect(find.byType(BloomHeroRing), findsOneWidget);
      expect(find.text('Safe today'), findsOneWidget);
      expect(find.text('Net flow'), findsOneWidget);
      expect(find.text('Burn'), findsOneWidget);
      expect(find.text('Runway'), findsOneWidget);

      await database.close();
    });

    testWidgets('tapping metric switcher pill changes selected metric',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await pumpDashboard(tester, database);

      // Tap Net flow
      await tester.tap(find.text('Net flow'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('NET FLOW'), findsOneWidget);

      // Tap Burn
      await tester.tap(find.text('Burn'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('BURN RATE'), findsOneWidget);

      await database.close();
    });

    testWidgets('metric choices stay semantic and tappable at 320dp and 2x',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      final semantics = tester.ensureSemantics();
      var semanticsDisposed = false;
      addTearDown(() {
        if (!semanticsDisposed) semantics.dispose();
      });
      await pumpDashboard(
        tester,
        database,
        size: const Size(320, 568),
        textScale: 2,
      );

      await tester.scrollUntilVisible(find.text('Safe today'), 180);
      final selected = find.bySemanticsLabel('Safe today');
      await tester.ensureVisible(selected);
      await tester.pump(const Duration(milliseconds: 300));
      final selectedNode = tester.getSemantics(selected);
      final selectedSemanticRect = MatrixUtils.transformRect(
        selectedNode.transform ?? Matrix4.identity(),
        selectedNode.rect,
      );
      final selectedData = selectedNode.getSemanticsData();
      expect(selectedData.flagsCollection.isButton, isTrue);
      expect(selectedData.flagsCollection.isSelected.toBoolOrNull(), isTrue);
      expect(selectedSemanticRect.height, greaterThanOrEqualTo(48));
      expect(selectedSemanticRect.width, greaterThanOrEqualTo(48));
      expect(tester.getRect(selected).height, greaterThanOrEqualTo(48));
      expect(tester.getRect(selected).width, greaterThanOrEqualTo(48));

      final next = find.bySemanticsLabel('Net flow');
      await tester.scrollUntilVisible(find.text('Net flow'), 180);
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      final nextNode = tester.getSemantics(next);
      final nextSemanticRect = MatrixUtils.transformRect(
        nextNode.transform ?? Matrix4.identity(),
        nextNode.rect,
      );
      expect(
        nextNode.getSemanticsData().flagsCollection.isSelected.toBoolOrNull(),
        isFalse,
      );
      final nextRect = tester.getRect(next);
      expect(nextSemanticRect.height, greaterThanOrEqualTo(48));
      expect(nextSemanticRect.width, greaterThanOrEqualTo(48));
      expect(nextRect.height, greaterThanOrEqualTo(48));
      expect(nextRect.width, greaterThanOrEqualTo(48));
      await tester.tapAt(Offset(nextRect.right - 1, nextRect.bottom - 1));
      await tester.pump();
      expect(
        tester
            .getSemantics(next)
            .getSemanticsData()
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isTrue,
      );
      expect(
        tester
            .getSemantics(selected)
            .getSemanticsData()
            .flagsCollection
            .isSelected
            .toBoolOrNull(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
      semanticsDisposed = true;
      await database.close();
    });

    testWidgets('metric choices keep intrinsic widths in the normal layout',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await pumpDashboard(tester, database);

      final safe = tester.getRect(find.bySemanticsLabel('Safe today'));
      final netFlow = tester.getRect(find.bySemanticsLabel('Net flow'));
      final burn = tester.getRect(find.bySemanticsLabel('Burn'));
      expect(safe.width, lessThan(160));
      expect(netFlow.width, lessThan(160));
      expect(burn.width, lessThan(160));
      expect(safe.top, netFlow.top);
      expect(netFlow.top, burn.top);
      expect(tester.takeException(), isNull);
      await database.close();
    });

    testWidgets('insight card renders nothing when no insights exist',
        (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      await pumpDashboard(tester, database);

      // No fabricated insight strings
      expect(find.textContaining('Blinkit'), findsNothing);
      expect(find.text('Sure'), findsNothing);
      expect(find.textContaining('Cap set'), findsNothing);

      await database.close();
    });

    testWidgets('monthly budget dialog validates and saves its action result',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var semanticsDisposed = false;
      addTearDown(() {
        if (!semanticsDisposed) semantics.dispose();
      });
      final database = AppDatabase(NativeDatabase.memory());
      var databaseClosed = false;
      addTearDown(() async {
        if (!databaseClosed) await unmountAndCloseDatabase(tester, database);
      });
      await pumpDashboard(
        tester,
        database,
        size: const Size(320, 568),
        textScale: 2,
      );

      // The budget action follows the dashboard content, so reveal it in the
      // real compact viewport before checking its accessible bounds.
      await tester.scrollUntilVisible(find.text('Set monthly budget'), 160);
      expect(find.text('Set monthly budget'), findsOneWidget);
      final button = find.bySemanticsLabel(RegExp('Set monthly budget'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final data = tester.getSemantics(button).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(tester.getSemantics(button).rect.height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(button).rect.width, greaterThanOrEqualTo(48));
      final rect = tester.getRect(button);
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.width, greaterThanOrEqualTo(48));
      await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Set Monthly Budget'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter an amount'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '12000');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Set Monthly Budget'), findsNothing);
      expect(
        await database.select(database.baselines).get(),
        isNotEmpty,
      );

      semantics.dispose();
      semanticsDisposed = true;
      await unmountAndCloseDatabase(tester, database);
      databaseClosed = true;
    });

    testWidgets('budget card keeps full amounts readable at 2x text',
        (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            monthlyBudgetProvider.overrideWith((ref) async => 12000),
            monthDirectionTotalsProvider.overrideWith(
              (ref) => const AsyncData(
                MonthDirectionTotals(debitTotal: 0, creditTotal: 0),
              ),
            ),
            commitmentsTotalProvider.overrideWith((ref) => 0),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(child: BloomBudgetCard()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('spent of ₹12,000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('All categories action is named and activates at its edge',
        (tester) async {
      final semantics = tester.ensureSemantics();
      var semanticsDisposed = false;
      addTearDown(() {
        if (!semanticsDisposed) semantics.dispose();
      });
      var calls = 0;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryBreakdownProvider.overrideWithValue(
              const AsyncData([
                CategorySlice(
                  categoryId: 'food',
                  name: 'Food',
                  icon: 'food',
                  total: 1234567.89,
                  share: 1,
                ),
              ]),
            ),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: BloomTopCategoriesSection(onViewAll: () => calls++),
            ),
          ),
        ),
      );

      final section = tester.element(find.byType(BloomTopCategoriesSection));
      expect(MediaQuery.sizeOf(section), const Size(320, 568));
      expect(MediaQuery.textScalerOf(section).scale(10), 20);
      expect(tester.takeException(), isNull);

      final action = find.bySemanticsLabel('View all categories');
      final data = tester.getSemantics(action).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(tester.getSemantics(action).rect.height, greaterThanOrEqualTo(48));
      expect(tester.getSemantics(action).rect.width, greaterThanOrEqualTo(48));
      final rect = tester.getRect(action);
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.width, greaterThanOrEqualTo(48));
      final actionText = tester.renderObject<RenderParagraph>(
        find.text('All →'),
      );
      expect(actionText.didExceedMaxLines, isFalse);
      final categoryAmount = tester.renderObject<RenderParagraph>(
        find.text('₹12,34,567.89'),
      );
      expect(categoryAmount.didExceedMaxLines, isFalse);
      await tester.tapAt(Offset(rect.right - 1, rect.bottom - 1));
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      semanticsDisposed = true;
    });

    testWidgets('completeness note appears when spending is excluded',
        (tester) async {
      tester.view.physicalSize = const Size(402, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final database = AppDatabase(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => database),
            dashboardPeriodProvider.overrideWith(
              (ref) => DashboardPeriod.month(DateTime(2026, 7, 15)),
            ),
            dashboardAggregateProvider.overrideWith(
              (ref) async => const DashboardAggregateSnapshot(
                debitTotal: 500,
                creditTotal: 0,
                previousSpend: 0,
                categories: [],
                merchants: [],
                trendByMonth: {},
                excludedDebitTotal: 1700,
                excludedDebitCount: 2,
              ),
            ),
          ],
          child: const MaterialApp(
            home: BloomUndoToastHost(child: DashboardScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.textContaining(
          'Owned transfers and transactions excluded from analytics',
        ),
        findsOneWidget,
      );
      expect(find.text('Period: July 2026'), findsOneWidget);
      expect(
        find.textContaining(
          'settled debit transactions in spending categories',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'missing or unrecorded transactions are not visible',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('For spending, pending, reversed or failed'),
        findsOneWidget,
      );

      await database.close();
    });

    testWidgets(
        'scope disclosure labels aggregate loading without showing zero',
        (tester) async {
      tester.view.physicalSize = const Size(402, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final database = AppDatabase(NativeDatabase.memory());
      final aggregateCompleter = Completer<DashboardAggregateSnapshot>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => database),
            dashboardAggregateProvider.overrideWith(
              (ref) => aggregateCompleter.future,
            ),
          ],
          child: const MaterialApp(
            home: BloomUndoToastHost(child: DashboardScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Updating totals for this period…'), findsOneWidget);
      expect(
        find.textContaining(
          'Owned transfers and transactions excluded from analytics',
        ),
        findsNothing,
      );

      aggregateCompleter.complete(
        const DashboardAggregateSnapshot(
          debitTotal: 0,
          creditTotal: 0,
          previousSpend: 0,
          categories: [],
          merchants: [],
          trendByMonth: {},
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Updating totals for this period…'), findsNothing);
      expect(
        find.textContaining(
          'Owned transfers and transactions excluded from analytics',
        ),
        findsNothing,
      );

      await database.close();
    });

    testWidgets('scope disclosure marks aggregate errors as unavailable',
        (tester) async {
      tester.view.physicalSize = const Size(402, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final database = AppDatabase(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => database),
            dashboardAggregateProvider.overrideWith(
              (ref) => Future.error(StateError('database unavailable')),
            ),
          ],
          child: const MaterialApp(
            home: BloomUndoToastHost(child: DashboardScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.text(
          'Totals are unavailable while transaction data could not be loaded.',
        ),
        findsOneWidget,
      );

      await database.close();
    });
  });
}

const _emptyDashboardAggregate = DashboardAggregateSnapshot(
  debitTotal: 0,
  creditTotal: 0,
  previousSpend: 0,
  categories: [],
  merchants: [],
  trendByMonth: {},
);
