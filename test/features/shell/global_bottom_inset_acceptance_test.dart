import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/models/transaction_confidence_trail.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/data/repositories/budget_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_providers.dart';
import 'package:paisatrack/features/home/home_shell.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/not_transactions_screen.dart';
import 'package:paisatrack/features/settings/settings_screen.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';

import '../../support/fake_activity_transaction_page_controller.dart';
import '../../support/fake_sms_permission_gate.dart';

const _navigationKey = ValueKey('floating_navigation_pill');
const _emptyDashboardAggregate = DashboardAggregateSnapshot(
  debitTotal: 0,
  creditTotal: 0,
  previousSpend: 0,
  categories: [],
  merchants: [],
  trendByMonth: {},
);

final _detailRouteItem = TransactionListItem(
  id: 'synthetic_detail_route',
  ts: DateTime.utc(2026, 9, 30),
  amount: 449,
  currencyCode: 'INR',
  currencySymbol: '₹',
  direction: TransactionDirection.debit,
  displayName: 'Synthetic route payee',
  categoryName: 'Food & Dining',
  categoryId: 'food_dining',
  categoryIcon: 'restaurant',
  status: 'confirmed',
  parseSource: 'template',
  merchantRaw: 'Synthetic route payee',
);

final _detailRouteDetail = TransactionDetail(
  txn: Transaction(
    id: 'synthetic_detail_route',
    ts: DateTime.utc(2026, 9, 30).millisecondsSinceEpoch,
    amount: 449,
    currencyCode: 'INR',
    currencySymbol: '₹',
    direction: 'debit',
    channel: 'upi',
    categoryId: 'food_dining',
    merchantRaw: 'Synthetic route payee',
    parseSource: 'template',
    confidenceJson: '{}',
    status: 'confirmed',
    isDeleted: false,
    isNotTransaction: false,
    isAnalyticsExcluded: false,
    lifecycleState: 'settled',
    createdAt: DateTime.utc(2026, 9, 30),
    updatedAt: DateTime.utc(2026, 9, 30),
  ),
  merchantName: 'Synthetic route payee',
  categoryName: 'Food & Dining',
  categoryIcon: 'restaurant',
  parseConfidence: 0.98,
  confidenceTrail: TransactionConfidenceTrail.fromJson('{}'),
  isLowTrustParse: false,
);

final _sortRouteItems = <TransactionReviewItem>[
  for (var index = 0; index < 2; index++)
    TransactionReviewItem(
      id: index == 0 ? _detailRouteItem.id : 'synthetic_sort_second',
      ts: _detailRouteItem.ts,
      amount: _detailRouteItem.amount,
      direction: _detailRouteItem.direction,
      displayName: 'Synthetic Sort item ${index + 1}',
      categoryName: _detailRouteItem.categoryName,
      categoryId: _detailRouteItem.categoryId,
      categoryIcon: _detailRouteItem.categoryIcon,
      status: 'needs_review',
    ),
];

const _destinations = <HomeNavigationDestination>[
  HomeNavigationDestination(
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  HomeNavigationDestination(
    label: 'Activity',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
  ),
  HomeNavigationDestination(
    label: 'Sort',
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check_rounded,
  ),
  HomeNavigationDestination(
    label: 'Trends',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights_rounded,
  ),
];

class _RouteShell extends StatefulWidget {
  const _RouteShell({required this.initialScreen, this.initialTab = 0});

  final Widget initialScreen;
  final int initialTab;

  @override
  State<_RouteShell> createState() => _RouteShellState();
}

class _RouteShellState extends State<_RouteShell> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late int _currentTab = widget.initialTab;

  Widget _screenForTab(int index) => switch (index) {
        0 => const Scaffold(body: Center(child: Text('Synthetic Home route'))),
        1 => const TransactionsScreen(),
        2 => const WeeklyReviewScreen(),
        _ => const InsightsScreen(),
      };

  void _selectTab(int index) {
    setState(() => _currentTab = index);
    _navigatorKey.currentState!.pushReplacement(
      MaterialPageRoute<void>(builder: (_) => _screenForTab(index)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceMediaQuery = MediaQuery.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaQuery(
          data: BloomBottomInset.forTabContent(deviceMediaQuery),
          child: Navigator(
            key: _navigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => widget.initialScreen,
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: deviceMediaQuery.padding.bottom + kBottomNavBottomGap,
          child: Material(
            type: MaterialType.transparency,
            child: HomeFloatingNavPill(
              key: _navigationKey,
              currentIndex: _currentTab,
              destinations: _destinations,
              onTabSelected: _selectTab,
              onAskTapped: () {},
              isDark: true,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _pumpRoutes(
  WidgetTester tester, {
  required Widget initialScreen,
  int initialTab = 0,
  Size size = const Size(402, 874),
  double systemBottomInset = 24,
  double textScale = 1,
  List<Override> providerOverrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = FakeViewPadding(bottom: systemBottomInset);
  tester.view.viewInsets = const FakeViewPadding();
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...providerOverrides,
        dashboardAggregateProvider.overrideWith(
          (ref) async => _emptyDashboardAggregate,
        ),
        activeInsightsProvider.overrideWith(
          (ref) => Stream<List<Insight>>.value(const []),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: MediaQuery(
                data: mediaQuery.copyWith(
                  textScaler: TextScaler.linear(textScale),
                ),
                child: child!,
              ),
            ),
          );
        },
        home: _RouteShell(
          initialScreen: initialScreen,
          initialTab: initialTab,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

class _FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

Future<AppDatabase> _settingsRouteDatabase() async {
  final database = AppDatabase(NativeDatabase.memory());
  final now = DateTime.utc(2026, 9, 30);
  for (var index = 0; index < 14; index++) {
    final transactionId = 'synthetic_not_transaction_$index';
    final smsId = 'synthetic_sms_$index';
    final updatedAt = now.subtract(Duration(minutes: index));
    await database.into(database.transactions).insert(
          TransactionsCompanion.insert(
            id: transactionId,
            ts: updatedAt.millisecondsSinceEpoch,
            amount: 100.0 + index,
            direction: 'debit',
            channel: 'upi',
            merchantRaw: Value('Synthetic history row $index'),
            parseSource: 'test_fixture',
            confidenceJson: '{}',
            status: 'confirmed',
            isNotTransaction: const Value(true),
            createdAt: updatedAt,
            updatedAt: updatedAt,
          ),
        );
    await database.into(database.smsDispositions).insert(
          SmsDispositionsCompanion.insert(
            smsId: smsId,
            transactionId: transactionId,
            disposition: 'not_transaction',
            createdAt: updatedAt,
          ),
        );
  }
  return database;
}

void _expectAboveNavigation(WidgetTester tester, Finder target) {
  final targetRect = tester.getRect(target);
  final navigationRect = tester.getRect(find.byType(HomeFloatingNavPill));
  expect(targetRect.bottom, lessThanOrEqualTo(navigationRect.top));
}

Future<void> _scrollToEnd(WidgetTester tester, Type screenType) async {
  final scrollable = find
      .descendant(
        of: find.byType(screenType),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sortRouteCases = <({
    String name,
    Size size,
    double inset,
    double textScale,
  })>[
    (
      name: 'standard portrait at default text',
      size: Size(402, 874),
      inset: 24,
      textScale: 1,
    ),
    (
      name: 'compact landscape at 1.5x text with gesture navigation',
      size: Size(568, 320),
      inset: 24,
      textScale: 1.5,
    ),
    (
      name: 'compact landscape at 2x text with three-button navigation',
      size: Size(568, 320),
      inset: 48,
      textScale: 2,
    ),
  ];
  for (final routeCase in sortRouteCases) {
    testWidgets(
      'Sort card, action, and detail stay tappable in ${routeCase.name}',
      (tester) async {
        await _pumpRoutes(
          tester,
          initialScreen: const Scaffold(
            body: Center(child: Text('Synthetic Home route')),
          ),
          size: routeCase.size,
          systemBottomInset: routeCase.inset,
          textScale: routeCase.textScale,
          providerOverrides: [
            reviewQueueProvider.overrideWith(
              (ref) => Stream.value(_sortRouteItems),
            ),
            transactionDetailProvider(_detailRouteItem.id).overrideWith(
              (ref) => Stream.value(_detailRouteDetail),
            ),
            categoryListProvider.overrideWith(
              (ref) => Stream.value(const <Category>[]),
            ),
            suggestedCategoriesProvider(_detailRouteItem.id)
                .overrideWith((ref) async => const <String>[]),
          ],
        );

        final sortTab = find.descendant(
          of: find.byType(HomeFloatingNavPill),
          matching: find.byIcon(Icons.fact_check_outlined),
        );
        expect(sortTab, findsOneWidget);
        await tester.tap(sortTab);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        final firstItem = find.text('Synthetic Sort item 1');
        expect(firstItem, findsOneWidget);
        final nav = find.byType(HomeFloatingNavPill);
        final navRect = tester.getRect(nav);
        final cardScroll = find.descendant(
          of: find.byType(WeeklyReviewScreen),
          matching: find.byType(Scrollable),
        );
        if (cardScroll.evaluate().isNotEmpty) {
          final scrollPosition =
              tester.state<ScrollableState>(cardScroll).position;
          await tester.drag(cardScroll, const Offset(0, -24));
          await tester.pump();
          expect(scrollPosition.pixels, greaterThan(0));
          await tester.ensureVisible(firstItem);
          await tester.pump();

          final cardViewport = tester.getRect(cardScroll);
          var titleRect = tester.getRect(firstItem);
          expect(titleRect.top, greaterThanOrEqualTo(cardViewport.top));
          for (var attempt = 0;
              titleRect.bottom > cardViewport.bottom && attempt < 10;
              attempt++) {
            final previousOffset = scrollPosition.pixels;
            await tester.drag(
              cardScroll,
              const Offset(0, -48),
            );
            await tester.pump();
            titleRect = tester.getRect(firstItem);
            expect(scrollPosition.pixels, greaterThan(previousOffset));
          }
          expect(titleRect.bottom, lessThanOrEqualTo(cardViewport.bottom));
          expect(titleRect.top, lessThanOrEqualTo(cardViewport.top));
        }
        final cardTitleRect = tester.getRect(firstItem);
        expect(cardTitleRect.top, greaterThanOrEqualTo(0));
        if (cardScroll.evaluate().isNotEmpty) {
          final cardViewport = tester.getRect(cardScroll);
          expect(cardViewport.bottom, lessThanOrEqualTo(navRect.top));
          expect(cardTitleRect.intersect(cardViewport).isEmpty, isFalse);
        } else {
          expect(cardTitleRect.bottom, lessThanOrEqualTo(navRect.top));
        }
        final cardTapArea = cardScroll.evaluate().isEmpty
            ? cardTitleRect
            : cardTitleRect.intersect(tester.getRect(cardScroll));
        await tester.tapAt(cardTapArea.center);
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        expect(find.byType(TransactionDetailScreen), findsOneWidget);
        expect(find.text(_detailRouteItem.displayName), findsOneWidget);
        Navigator.of(tester.element(find.byType(TransactionDetailScreen)))
            .pop();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump();

        final skipAction = find.byIcon(Icons.skip_next_rounded);
        expect(skipAction, findsOneWidget);
        expect(
          tester.getRect(skipAction).bottom,
          lessThanOrEqualTo(navRect.top),
        );
        await tester.tap(skipAction);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Synthetic Sort item 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  const settingsRouteCases = <({
    String name,
    Size size,
    double inset,
    double textScale,
  })>[
    (
      name: 'gesture navigation',
      size: Size(402, 874),
      inset: 24,
      textScale: 1,
    ),
    (
      name: 'three-button navigation',
      size: Size(402, 874),
      inset: 48,
      textScale: 1,
    ),
    (
      name: 'compact portrait at 2x text',
      size: Size(320, 568),
      inset: 24,
      textScale: 2,
    ),
    (
      name: 'compact landscape at 1.5x text with three-button navigation',
      size: Size(568, 320),
      inset: 48,
      textScale: 1.5,
    ),
    (
      name: 'compact landscape at 2x text with gesture navigation',
      size: Size(568, 320),
      inset: 24,
      textScale: 2,
    ),
  ];
  for (final routeCase in settingsRouteCases) {
    testWidgets(
      'Settings and Not transactions clear the real navigation pill in ${routeCase.name}',
      (tester) async {
        final database = await _settingsRouteDatabase();
        try {
          await _pumpRoutes(
            tester,
            initialScreen: const SettingsScreen(),
            size: routeCase.size,
            systemBottomInset: routeCase.inset,
            textScale: routeCase.textScale,
            providerOverrides: [
              appDatabaseProvider.overrideWith((ref) async => database),
              appSettingsControllerProvider
                  .overrideWith(() => _FakeAppSettingsController()),
              monthlyBudgetProvider.overrideWith((ref) async => null),
              smsPermissionGateProvider.overrideWithValue(
                FakeSmsPermissionGate(
                  initialStatus: SmsPermissionStatus.granted,
                ),
              ),
            ],
          );

          final notTransactionsAction = find.text('Not transactions');
          final settingsScrollable = find
              .descendant(
                of: find.byType(SettingsScreen),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            notTransactionsAction,
            200,
            scrollable: settingsScrollable,
          );
          await tester.ensureVisible(notTransactionsAction);
          await tester.pump(const Duration(milliseconds: 200));
          final settingsTile = find.ancestor(
            of: notTransactionsAction,
            matching: find.byType(ListTile),
          );
          expect(notTransactionsAction, findsOneWidget);
          final settingsPosition =
              tester.state<ScrollableState>(settingsScrollable).position;
          final tileBottom = tester.getRect(settingsTile).bottom;
          final pillTop = tester.getRect(find.byType(HomeFloatingNavPill)).top;
          if (tileBottom > pillTop) {
            settingsPosition.jumpTo(
              (settingsPosition.pixels + tileBottom - pillTop + 8)
                  .clamp(0.0, settingsPosition.maxScrollExtent)
                  .toDouble(),
            );
            await tester.pump();
          }
          _expectAboveNavigation(tester, settingsTile);
          await tester.tap(notTransactionsAction);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byType(NotTransactionsScreen), findsOneWidget);
          final historyScroll = find.descendant(
            of: find.byType(NotTransactionsScreen),
            matching: find.byType(Scrollable),
          );
          for (var frame = 0;
              frame < 10 && historyScroll.evaluate().isEmpty;
              frame++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(historyScroll, findsOneWidget);
          await _scrollToEnd(tester, NotTransactionsScreen);
          final lastRow = find.text('Synthetic history row 13');
          expect(lastRow, findsOneWidget);
          final historyTile = find.ancestor(
            of: lastRow,
            matching: find.byType(ListTile),
          );
          _expectAboveNavigation(tester, historyTile);
          expect(find.text('113.00 (currency unknown)'), findsOneWidget);
          await tester.tap(historyTile);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(lastRow, findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          // Dispose route subscribers and close the in-memory database before
          // flutter_test tears down the widget tree. Drift's stream-query store
          // schedules a Timer.run when the final watch subscription is cancelled;
          // closing the fixture in test teardown can leave that timer pending.
          await tester.pumpWidget(const SizedBox.shrink());
          await database.close();
          await tester.pump();
        }
      },
    );
  }

  for (final inset in [24.0, 48.0]) {
    final navigationMode = inset == 24 ? 'gesture' : 'three-button';
    testWidgets(
      'Trends final section clears the real $navigationMode navigation pill',
      (tester) async {
        await _pumpRoutes(
          tester,
          initialScreen: const InsightsScreen(),
          initialTab: 3,
          systemBottomInset: inset,
        );

        final finalSection = find.text('No merchant data for this period');
        await _scrollToEnd(tester, InsightsScreen);
        expect(finalSection, findsOneWidget);
        _expectAboveNavigation(tester, finalSection);
        expect(tester.getSize(find.byType(HomeFloatingNavPill)).height, 64);
        expect(tester.takeException(), isNull);
      },
    );
  }

  const detailRouteCases = <({
    String name,
    Size size,
    double inset,
    double textScale,
  })>[
    (
      name: 'emulator landscape at 1x text with gesture navigation',
      size: Size(964, 434),
      inset: 24,
      textScale: 1,
    ),
    (
      name: 'standard portrait',
      size: Size(402, 874),
      inset: 24,
      textScale: 1,
    ),
    (
      name: 'compact landscape at 1.5x text with gesture navigation',
      size: Size(568, 320),
      inset: 24,
      textScale: 1.5,
    ),
    (
      name: 'compact landscape at 2x text with three-button navigation',
      size: Size(568, 320),
      inset: 48,
      textScale: 2,
    ),
  ];
  for (final routeCase in detailRouteCases) {
    testWidgets(
      'Activity detail and correction sheet remain tappable in ${routeCase.name}',
      (tester) async {
        await _pumpRoutes(
          tester,
          initialScreen: const TransactionsScreen(),
          initialTab: 1,
          size: routeCase.size,
          systemBottomInset: routeCase.inset,
          textScale: routeCase.textScale,
          providerOverrides: [
            activityTransactionPageProvider.overrideWith(
              () => FakeActivityTransactionPageController(
                ActivityTransactionPage(
                  rows: [_detailRouteItem],
                  hasMore: false,
                ),
              ),
            ),
            transactionDetailProvider(_detailRouteItem.id).overrideWith(
              (ref) => Stream.value(_detailRouteDetail),
            ),
            categoryListProvider.overrideWith(
              (ref) => Stream.value(const <Category>[]),
            ),
            suggestedCategoriesProvider(_detailRouteItem.id)
                .overrideWith((ref) async => const <String>[]),
          ],
        );

        final transactionName = find.text(_detailRouteItem.displayName);
        final activityList = find
            .ancestor(of: transactionName, matching: find.byType(Scrollable))
            .first;
        final activityPosition =
            tester.state<ScrollableState>(activityList).position;
        final transactionRect = tester.getRect(transactionName);
        final navigationTop =
            tester.getRect(find.byType(HomeFloatingNavPill)).top;
        if (transactionRect.bottom > navigationTop) {
          activityPosition.jumpTo(
            (activityPosition.pixels +
                    transactionRect.bottom -
                    navigationTop +
                    8)
                .clamp(0.0, activityPosition.maxScrollExtent)
                .toDouble(),
          );
          await tester.pump();
        }
        final transactionTarget = find
            .ancestor(
              of: transactionName,
              matching: find.byType(GestureDetector),
            )
            .first;
        expect(tester.getSize(transactionTarget).height, greaterThanOrEqualTo(48));
        _expectAboveNavigation(tester, transactionName);
        await tester.tap(transactionName);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(TransactionDetailScreen), findsOneWidget);
        expect(find.text('Transaction Detail'), findsOneWidget);

        final detail = find.byType(TransactionDetailScreen);
        final detailScroll = find
            .descendant(of: detail, matching: find.byType(Scrollable))
            .first;
        final editParse = find.widgetWithText(
          OutlinedButton,
          'Edit Parse Details (Amount/Direction/Payee)',
        );
        await tester.scrollUntilVisible(
          editParse,
          80,
          scrollable: detailScroll,
        );
        await tester.ensureVisible(editParse);
        await tester.pump();

        expect(tester.getSize(editParse).height, greaterThanOrEqualTo(48));
        await tester.tap(editParse);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Correct Transaction Parse'), findsOneWidget);
        final creditChoice = find.widgetWithText(
          ChoiceChip,
          'Income (Credit)',
        );
        await tester.ensureVisible(creditChoice);
        await tester.tap(creditChoice);
        await tester.pump();
        expect(tester.widget<ChoiceChip>(creditChoice).selected, isTrue);
        final saveCorrection =
            find.widgetWithText(FilledButton, 'Save Correction');
        expect(saveCorrection, findsOneWidget);
        expect(
          tester.getSize(saveCorrection).height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Activity Load more control keeps a 48dp target at the emulator landscape viewport',
    (tester) async {
      await _pumpRoutes(
        tester,
        initialScreen: const TransactionsScreen(),
        initialTab: 1,
        size: const Size(964, 434),
        systemBottomInset: 24,
        textScale: 1,
        providerOverrides: [
          activityTransactionPageProvider.overrideWith(
            () => FakeActivityTransactionPageController(
              ActivityTransactionPage(
                rows: [_detailRouteItem],
                hasMore: true,
              ),
            ),
          ),
        ],
      );

      final loadMore =
          find.widgetWithText(OutlinedButton, 'Load more transactions');
      expect(loadMore, findsOneWidget);
      final semantics = tester.ensureSemantics();
      final semanticTarget = find.bySemanticsLabel('Load more transactions');
      try {
        expect(semanticTarget, findsOneWidget);
        await tester.ensureVisible(loadMore);
        await tester.pump();

        expect(tester.getSize(loadMore).height, greaterThanOrEqualTo(48));
        expect(tester.getRect(semanticTarget).height, greaterThanOrEqualTo(48));
        _expectAboveNavigation(tester, loadMore);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'compact landscape Trends final section clears navigation at 1.5x text',
    (tester) async {
      await _pumpRoutes(
        tester,
        initialScreen: const InsightsScreen(),
        initialTab: 3,
        size: const Size(568, 320),
        systemBottomInset: 24,
        textScale: 1.5,
      );
      final finalSection = find.text('No merchant data for this period');
      await _scrollToEnd(tester, InsightsScreen);
      expect(finalSection, findsOneWidget);
      _expectAboveNavigation(tester, finalSection);
      expect(tester.takeException(), isNull);
    },
  );
}
