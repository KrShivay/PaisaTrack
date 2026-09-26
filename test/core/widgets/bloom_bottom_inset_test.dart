import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_bottom_inset.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/category_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/settings/category_manager_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import '../../support/fake_activity_transaction_page_controller.dart';
import '../../support/fake_sms_permission_gate.dart';

const _navKey = ValueKey('geometry_test_navigation_pill');

Widget _underFloatingNavigation(Widget child) {
  return MaterialApp(
    builder: (context, routedChild) {
      final deviceMediaQuery = MediaQuery.of(context);
      return MediaQuery(
        data: BloomBottomInset.forTabContent(deviceMediaQuery),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (routedChild != null) routedChild,
            Positioned(
              left: 20,
              right: 20,
              bottom: deviceMediaQuery.padding.bottom + kBottomNavBottomGap,
              child: Container(
                key: _navKey,
                height: kBottomNavHeight,
                decoration: const BoxDecoration(color: Colors.black),
              ),
            ),
          ],
        ),
      );
    },
    home: child,
  );
}

void _setGestureNavigationMetrics(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewPadding();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tab inset includes gesture area, pill height, and pill gap', () {
    const mediaQuery = MediaQueryData(
      padding: EdgeInsets.only(bottom: 24),
      viewPadding: EdgeInsets.only(bottom: 24),
    );

    expect(BloomBottomInset.forTabContent(mediaQuery).padding.bottom, 108);
  });

  test('keyboard inset takes precedence while a text field is active', () {
    const mediaQuery = MediaQueryData(
      viewInsets: EdgeInsets.only(bottom: 300),
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.only(bottom: 24),
    );

    expect(BloomBottomInset.forTabContent(mediaQuery).padding.bottom, 0);
  });

  testWidgets('Scaffold FAB is positioned above the floating nav area',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const deviceMediaQuery = MediaQueryData(
      padding: EdgeInsets.only(bottom: 24),
      viewPadding: EdgeInsets.only(bottom: 24),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: BloomBottomInset.forTabContent(deviceMediaQuery),
          child: Scaffold(
            floatingActionButtonLocation:
                BloomBottomInset.floatingActionButtonLocation,
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    final fabRect = tester.getRect(find.byType(FloatingActionButton));
    const navTop = 800 - 24 - kBottomNavHeight - kBottomNavBottomGap;
    expect(fabRect.bottom, lessThanOrEqualTo(navTop));
  });

  testWidgets('FAB remains above the keyboard without reserving hidden nav',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const keyboardMediaQuery = MediaQueryData(
      viewInsets: EdgeInsets.only(bottom: 300),
      padding: EdgeInsets.zero,
      viewPadding: EdgeInsets.only(bottom: 24),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: BloomBottomInset.forTabContent(keyboardMediaQuery),
          child: Scaffold(
            floatingActionButtonLocation:
                BloomBottomInset.floatingActionButtonLocation,
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    );

    final fabRect = tester.getRect(find.byType(FloatingActionButton));
    expect(fabRect.bottom, lessThanOrEqualTo(800 - 300));
  });

  testWidgets('nested category screen lifts its FAB above the nav pill',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewPadding();
    });

    final database = AppDatabase(NativeDatabase.memory());
    const deviceMediaQuery = MediaQueryData(
      padding: EdgeInsets.only(bottom: 24),
      viewPadding: EdgeInsets.only(bottom: 24),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: BloomBottomInset.forTabContent(deviceMediaQuery),
            child: const CategoryManagerScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    final fabRect = tester.getRect(find.byTooltip('Add category'));
    const navTop = 800 - 24 - kBottomNavHeight - kBottomNavBottomGap;
    expect(fabRect.bottom, lessThanOrEqualTo(navTop));

    await database.close();
  });

  testWidgets(
      'last category row scrolls fully above the floating navigation pill',
      (tester) async {
    _setGestureNavigationMetrics(tester);
    final database = AppDatabase(NativeDatabase.memory());
    try {
      final categories = CategoryRepository(database);
      for (var index = 0; index < 24; index++) {
        await categories.addUserCategory(
          name: 'Inset fixture ${index.toString().padLeft(2, '0')}',
          clock: () => DateTime.utc(2026, 9, 26).add(
            Duration(microseconds: index),
          ),
        );
      }
      const finalCategory = 'ZZZ final inset fixture';
      await categories.addUserCategory(
        name: finalCategory,
        clock: () => DateTime.utc(2026, 9, 27),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWith((ref) async => database),
          ],
          child: _underFloatingNavigation(const CategoryManagerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final finalRow = find.text(finalCategory);
      final list = find.byType(ListView);
      expect(list, findsOneWidget);
      await tester.drag(list, const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(finalRow, findsOneWidget);
      final rowRect = tester.getRect(finalRow);
      final navRect = tester.getRect(find.byKey(_navKey));
      expect(rowRect.bottom, lessThanOrEqualTo(navRect.top));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await database.close();
    }
  });

  testWidgets(
      'last populated Activity transaction scrolls fully above navigation',
      (tester) async {
    _setGestureNavigationMetrics(tester);
    final now = DateTime.utc(2026, 9, 26, 12);
    final rows = [
      for (var index = 0; index < 30; index++)
        TransactionListItem(
          id: 'inset_activity_$index',
          ts: now.subtract(Duration(days: index)),
          amount: 100.0 + index,
          direction: TransactionDirection.debit,
          displayName:
              index == 29 ? 'Final Activity inset fixture' : 'Activity $index',
          categoryName: 'Food',
          categoryId: 'food',
          categoryIcon: 'food',
        ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
          activityTransactionPageProvider.overrideWith(
            () => FakeActivityTransactionPageController(
              ActivityTransactionPage(rows: rows, hasMore: false),
            ),
          ),
        ],
        child: _underFloatingNavigation(const TransactionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final finalTransaction = find.text('Final Activity inset fixture');
    final list = find.byType(ListView);
    expect(list, findsOneWidget);
    await tester.drag(list, const Offset(0, -6000));
    await tester.pumpAndSettle();

    expect(finalTransaction, findsOneWidget);
    final rowRect = tester.getRect(finalTransaction);
    final navRect = tester.getRect(find.byKey(_navKey));
    expect(rowRect.bottom, lessThanOrEqualTo(navRect.top));
  });

  testWidgets('populated Sort action row clears the floating navigation',
      (tester) async {
    _setGestureNavigationMetrics(tester);
    final item = TransactionReviewItem(
      id: 'sort_inset_fixture',
      ts: DateTime.utc(2026, 9, 26, 12),
      amount: 123.45,
      direction: TransactionDirection.debit,
      displayName: 'Sort inset fixture',
      categoryName: 'Food',
      categoryId: 'food',
      categoryIcon: 'food',
      status: 'needs_review',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reviewQueueProvider.overrideWith((ref) => Stream.value([item])),
          categoryListProvider.overrideWith((ref) => Stream.value([])),
          appSettingsControllerProvider.overrideWith(
            () => _FakeAppSettingsController(),
          ),
        ],
        child: _underFloatingNavigation(const WeeklyReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sort inset fixture'), findsOneWidget);
    final keepIcon = find.byIcon(Icons.check_rounded);
    expect(keepIcon, findsOneWidget);
    final actionRect = tester.getRect(keepIcon);
    final navRect = tester.getRect(find.byKey(_navKey));
    expect(actionRect.bottom, lessThanOrEqualTo(navRect.top));
  });
}

class _FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}
