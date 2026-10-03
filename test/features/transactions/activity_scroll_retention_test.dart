import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';

import '../../support/fake_sms_permission_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppDatabase> seed(int count) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.into(database.categories).insert(
          CategoriesCompanion.insert(
            id: 'food',
            name: 'Food',
            icon: 'restaurant',
            isSpending: true,
            sortOrder: 1,
            isUserCreated: false,
          ),
        );
    final base = DateTime.utc(2026, 9, 30, 12);
    for (var i = 0; i < count; i++) {
      final ts = base.subtract(Duration(hours: 7 * i));
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: 'txn_${i.toString().padLeft(3, '0')}',
              ts: ts.millisecondsSinceEpoch,
              amount: 100 + i.toDouble(),
              direction: 'debit',
              channel: 'upi',
              merchantRaw: Value('Payee $i'),
              parseSource: 'template',
              confidenceJson: '{}',
              status: 'confirmed',
              createdAt: ts,
              updatedAt: ts,
            ),
          );
    }
    return database;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<ProviderContainer> pumpActivity(
    WidgetTester tester,
    AppDatabase database, {
    Size size = const Size(402, 874),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
        ],
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(
      tester.element(find.byType(TransactionsScreen)),
    );
  }

  // Unmount subscribers and close the in-memory database inside the test so
  // Drift's stream-store Timer.run is not left pending for teardown.
  Future<void> teardown(WidgetTester tester, AppDatabase database) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    final closing = database.close();
    await settle(tester);
    await closing;
  }

  ScrollPosition activityPosition(WidgetTester tester) {
    final scrollables = tester.stateList<ScrollableState>(
      find.byType(Scrollable),
    );
    return scrollables
        .map((state) => state.position)
        .where((position) => position.axis == Axis.vertical)
        .reduce((a, b) => a.maxScrollExtent >= b.maxScrollExtent ? a : b);
  }

  final activityList = find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .last;

  /// Loads the second page, then brings an older row into view.
  Future<Finder> openOlderRow(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final loadMore = find.text('Load more transactions');
    await tester.scrollUntilVisible(loadMore, 400, scrollable: activityList);
    await tester.drag(activityList, const Offset(0, -200));
    await settle(tester);
    await tester.tap(loadMore);
    await settle(tester);
    expect(
      container.read(activityTransactionPageProvider).value!.rows,
      hasLength(150),
    );
    final anchor = find.text('Payee 120');
    await tester.scrollUntilVisible(anchor, 400, scrollable: activityList);
    await tester.ensureVisible(anchor);
    await settle(tester);
    return anchor;
  }

  void expectAnchorKept(
    WidgetTester tester,
    ProviderContainer container,
    Finder anchor, {
    required double offset,
    required double top,
  }) {
    expect(
      container.read(activityTransactionPageProvider).value!.rows,
      hasLength(150),
    );
    expect(activityPosition(tester).pixels, offset);
    expect(anchor, findsOneWidget);
    expect(tester.getTopLeft(anchor).dy, top);
  }

  for (final layout in [
    ('portrait', const Size(402, 874)),
    ('short-height', const Size(964, 434)),
  ]) {
    testWidgets('${layout.$1}: an edit keeps loaded pages and the anchor row',
        (tester) async {
      final database = await seed(150);
      final container = await pumpActivity(tester, database, size: layout.$2);
      final anchor = await openOlderRow(tester, container);
      final offset = activityPosition(tester).pixels;
      final top = tester.getTopLeft(anchor).dy;

      // Category changes open a picker whose search field autofocuses, so a
      // keyboard inset reaches Activity while the edit happens.
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await settle(tester);
      await TransactionRepository(database).updateWithFeedback(
        txnId: 'txn_120',
        categoryId: const Value('food'),
        context: 'test_edit',
      );
      await settle(tester);
      tester.view.viewInsets = FakeViewPadding.zero;
      await settle(tester);

      expectAnchorKept(tester, container, anchor, offset: offset, top: top);
      await teardown(tester, database);
    });

    testWidgets('${layout.$1}: swipe confirm and undo keep the anchor row',
        (tester) async {
      final database = await seed(150);
      await (database.update(database.transactions)
            ..where((row) => row.id.equals('txn_120')))
          .write(const TransactionsCompanion(status: Value('needs_review')));
      final container = await pumpActivity(tester, database, size: layout.$2);
      final anchor = await openOlderRow(tester, container);
      final offset = activityPosition(tester).pixels;
      final top = tester.getTopLeft(anchor).dy;

      await tester.drag(anchor, Offset(layout.$2.width * 0.8, 0));
      await settle(tester);
      expectAnchorKept(tester, container, anchor, offset: offset, top: top);
      final confirmed = await (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_120')))
          .getSingle();
      expect(confirmed.status, 'confirmed');

      await container.read(undoControllerProvider.notifier).undo();
      await settle(tester);
      expectAnchorKept(tester, container, anchor, offset: offset, top: top);
      final undone = await (database.select(database.transactions)
            ..where((row) => row.id.equals('txn_120')))
          .getSingle();
      expect(undone.status, 'needs_review');
      await teardown(tester, database);
    });
  }
}
