import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/data/repositories/budget_repository.dart';
import 'package:paisatrack/data/repositories/card_source_audit_repository.dart';
import 'package:paisatrack/data/repositories/dashboard_repository.dart';
import 'package:paisatrack/data/repositories/payment_source_repository.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_bottom_inset.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/card_source_audit_screen.dart';
import 'package:paisatrack/features/settings/settings_screen.dart';

import '../../support/fake_sms_permission_gate.dart';
import '../../support/drift_widget_teardown.dart';

class _FakeAppSettingsController extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

class _ControlledAuditRepository extends CardSourceAuditRepository {
  _ControlledAuditRepository(super.database);

  var calls = 0;
  final firstCall = Completer<CardSourceAuditReport>();

  @override
  Future<CardSourceAuditReport> load({CardSourceAuditCursor? cursor}) {
    calls++;
    if (calls == 1) return firstCall.future;
    return Future.value(_emptyReport());
  }
}

class _PagingAuditRepository extends CardSourceAuditRepository {
  _PagingAuditRepository(super.database);

  final cursors = <CardSourceAuditCursor?>[];
  static const firstCursor = CardSourceAuditCursor(timestampMs: 200, id: 'b');
  static const secondCursor = CardSourceAuditCursor(timestampMs: 100, id: 'a');
  static const refreshedCursor =
      CardSourceAuditCursor(timestampMs: 50, id: 'fresh');
  static const thirdCursor = CardSourceAuditCursor(timestampMs: 25, id: 'last');

  @override
  Future<CardSourceAuditReport> load({CardSourceAuditCursor? cursor}) async {
    cursors.add(cursor);
    if (cursor == null) {
      return _pageReport('page-one', firstCursor);
    }
    if (cursor == firstCursor) {
      final visits = cursors.where((item) => item == firstCursor).length;
      return _pageReport(
        visits == 1 ? 'page-two' : 'page-two-refreshed',
        visits == 1 ? secondCursor : refreshedCursor,
      );
    }
    if (cursor == secondCursor) return _pageReport('page-three', thirdCursor);
    return _pageReport('page-four', null, truncated: false);
  }
}

class _PreloadedAuditRepository extends CardSourceAuditRepository {
  _PreloadedAuditRepository(super.database, this.report);

  final CardSourceAuditReport report;

  @override
  Future<CardSourceAuditReport> load({CardSourceAuditCursor? cursor}) async =>
      report;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousMultipleDatabaseWarning =
      driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        previousMultipleDatabaseWarning;
  });

  test('provider container loads through the default repository chain',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
    ProviderContainer? container;
    ProviderSubscription<AsyncValue<CardSourceAuditReport>>? subscription;
    try {
      await _insertAuditSource(
        database,
        id: 'provider-source',
        kind: 'card',
        mask: 'XX6789',
      );
      await _insertTransaction(
        database,
        id: 'provider-card-row',
        direction: 'debit',
        channel: 'card',
        timestamp: DateTime.utc(2026, 10, 4, 10),
        accountHint: '1234567890126789',
        paymentSourceId: 'provider-source',
      );
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
      );
      subscription = container.listen(
        cardSourceAuditReportProvider(null),
        (_, __) {},
      );
      final report =
          await container.read(cardSourceAuditReportProvider(null).future);
      expect(report.sources.single.maskedIdentifier, '••••6789');
      expect(
        report.candidates.map((candidate) => candidate.maskedIdentifier),
        contains('••••6789'),
      );
    } finally {
      subscription?.close();
      container?.dispose();
      await database.close();
    }
  });

  group('card source audit Settings route', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await database.customSelect('SELECT 1').get();
    });

    testWidgets(
      'opens from Settings without reconciling a reciprocal transfer pair',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final routeLoad = await tester.runAsync(() async {
          final before = await _seedAndSnapshot(database);
          final container = _settingsProviderContainer(database);
          final subscription = container.listen(
            cardSourceAuditReportProvider(null),
            (_, __) {},
          );
          await container.read(appDatabaseProvider.future);
          await container.read(cardSourceAuditRepositoryProvider.future);
          final report =
              await container.read(cardSourceAuditReportProvider(null).future);
          return (
            snapshot: before,
            container: container,
            subscription: subscription,
            report: report,
          );
        });
        final routeFixture = routeLoad!;
        final before = routeFixture.snapshot;
        expect(
          routeFixture.report.sources.map((source) => source.maskedIdentifier),
          contains('••••2002'),
        );

        final container = routeFixture.container;
        final auditSubscription = routeFixture.subscription;
        await _pumpSettings(tester, container);
        await pumpDriftFrames(tester);
        expect(
          container.read(cardSourceAuditReportProvider(null)).hasValue,
          isTrue,
        );
        await tester.scrollUntilVisible(find.text('Card source audit'), 180);
        await tester.ensureVisible(find.text('Card source audit'));
        await tester.pump();
        await tester.tap(find.text('Card source audit'));
        await pumpDriftFrames(tester);

        expect(find.byType(CardSourceAuditScreen), findsOneWidget);
        final auditScrollable = find
            .descendant(
              of: find.byType(CardSourceAuditScreen),
              matching: find.byType(ListView),
            )
            .first;
        await _scrollUntilBuiltAndVisible(
          tester,
          find.text('••••2002'),
          auditScrollable,
        );
        expect(
          find.text('Product: unverified · Ownership: unverified'),
          findsWidgets,
        );
        expect(find.text('Institution: Not recorded'), findsWidgets);
        expect(find.text('••••2002'), findsWidgets);
        expect(tester.takeException(), isNull);

        await _scrollUntilBuiltAndVisible(
          tester,
          find.text('Stored status: confirmed'),
          auditScrollable,
        );
        await _scrollUntilBuiltAndVisible(
          tester,
          find.text(
            'Stored flags: Deleted · Marked not a transaction · '
            'Duplicate-linked · Excluded from analytics',
          ),
          auditScrollable,
        );
        expect(
          find.text(
            'Stored flags: Deleted · Marked not a transaction · '
            'Duplicate-linked · Excluded from analytics',
          ),
          findsOneWidget,
        );
        await _scrollUntilBuiltAndVisible(
          tester,
          find.text(
            'No exclusion flags recorded; this is not an eligibility result.',
          ),
          auditScrollable,
        );
        expect(
          find.text(
            'No exclusion flags recorded; this is not an eligibility result.',
          ),
          findsOneWidget,
        );

        final after = await tester.runAsync(() => _stateSnapshot(database));
        expect(after, before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpDriftFrames(tester);
        auditSubscription.close();
        container.dispose();
        await pumpDriftFrames(tester);
        await tester.runAsync(() => database.close());
      },
    );
  });

  testWidgets('shows safe retry and empty state after recovery',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
    addTearDown(() => unmountAndCloseDatabase(tester, database));
    final repository = _ControlledAuditRepository(database);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardSourceAuditRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: const MaterialApp(home: CardSourceAuditScreen()),
      ),
    );
    expect(find.bySemanticsLabel('Loading card source audit'), findsOneWidget);

    repository.firstCall.completeError(StateError('PRIVATE-DB-DETAIL'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Could not load the card source audit. No data was changed.'),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE-DB-DETAIL'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('No stored payment sources are available yet.'),
      findsOneWidget,
    );
    expect(
      find.text('No transactions with a stored card channel were found.'),
      findsOneWidget,
    );
    expect(repository.calls, 2);
  });

  testWidgets('paging controls are 48dp and reuse the correct next cursor',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
    addTearDown(() => unmountAndCloseDatabase(tester, database));
    final repository = _PagingAuditRepository(database);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardSourceAuditRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: const MaterialApp(home: CardSourceAuditScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('More transactions'), 120);
    expect(
      tester
          .getSize(find.widgetWithText(FilledButton, 'More transactions'))
          .height,
      greaterThanOrEqualTo(48),
    );

    await tester.scrollUntilVisible(find.text('More transactions'), 120);
    await tester.tap(find.text('More transactions'));
    await pumpDriftFrames(tester);
    await tester.scrollUntilVisible(find.text('Previous'), 120);
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, 'Previous')).height,
      greaterThanOrEqualTo(48),
    );
    await tester.scrollUntilVisible(find.text('More transactions'), 120);
    await tester.tap(find.text('More transactions'));
    await pumpDriftFrames(tester);
    await tester.scrollUntilVisible(find.text('Previous'), 120);
    await tester.tap(find.text('Previous'));
    await pumpDriftFrames(tester);
    await tester.scrollUntilVisible(find.text('More transactions'), 120);
    await tester.tap(find.text('More transactions'));
    await pumpDriftFrames(tester);

    expect(repository.cursors, [
      null,
      _PagingAuditRepository.firstCursor,
      _PagingAuditRepository.secondCursor,
      _PagingAuditRepository.firstCursor,
      _PagingAuditRepository.refreshedCursor,
    ]);
    expect(find.text('More transactions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps long audit content scrollable at large text',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final database = AppDatabase(NativeDatabase.memory());
    await database.customSelect('SELECT 1').get();
    addTearDown(database.close);

    await _insertTransaction(
      database,
      id: 'long-card-row',
      amount: 1400,
      direction: 'debit',
      channel: 'card',
      accountHint: '1234567890129999',
      timestamp: DateTime.utc(2026, 10, 4, 10),
      currencyCode: 'INR',
      currencySymbol: '₹',
      lifecycleState: 'settled',
    );
    final report =
        await tester.runAsync(() => CardSourceAuditRepository(database).load());
    final loadedReport = report!;
    expect(
      loadedReport.candidates.map((candidate) => candidate.maskedIdentifier),
      contains('••••9999'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          cardSourceAuditRepositoryProvider.overrideWith(
            (ref) => _PreloadedAuditRepository(database, loadedReport),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: BloomBottomInset.forTabContent(
              MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewPadding: const EdgeInsets.only(bottom: 48),
              ),
            ),
            child: child!,
          ),
          home: const CardSourceAuditScreen(),
        ),
      ),
    );
    await pumpDriftFrames(tester);

    final auditList = find.byType(ListView).first;
    await _scrollUntilBuiltAndVisible(
      tester,
      find.text('Stored status: confirmed'),
      auditList,
    );
    expect(find.text('Identifier: ••••9999'), findsOneWidget);
    const finalNotice =
        'Candidate rows retain their stored flags and lifecycle. '
        'This audit does not decide financial eligibility.';
    await _scrollUntilBuiltAndVisible(
      tester,
      find.text(finalNotice),
      auditList,
    );
    await tester.drag(auditList, const Offset(0, -16));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(
      list.padding!.resolve(TextDirection.ltr).bottom,
      greaterThanOrEqualTo(
        kBottomNavHeight + kBottomNavBottomGap,
      ),
    );
    expect(
      tester.getRect(find.text(finalNotice)).bottom,
      lessThanOrEqualTo(568 - 48 - kBottomNavHeight - kBottomNavBottomGap),
    );
    expect(tester.takeException(), isNull);
  });
}

ProviderContainer _settingsProviderContainer(
  AppDatabase database,
) =>
    ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((ref) async => database),
        monthlyBudgetProvider.overrideWith((ref) async => null),
        appSettingsControllerProvider
            .overrideWith(() => _FakeAppSettingsController()),
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
      ],
    );

Future<void> _pumpSettings(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _scrollUntilBuiltAndVisible(
  WidgetTester tester,
  Finder target,
  Finder scrollable,
) async {
  for (var attempt = 0; target.evaluate().isEmpty && attempt < 20; attempt++) {
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pump();
  }
  expect(target, findsWidgets);
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

Future<void> _insertTransaction(
  AppDatabase database, {
  required String id,
  required String direction,
  required String channel,
  required DateTime timestamp,
  String? accountHint,
  String? paymentSourceId,
  String? merchantRaw,
  double amount = 150,
  String? currencyCode,
  String? currencySymbol,
  String lifecycleState = 'settled',
  bool isDeleted = false,
  bool isNotTransaction = false,
  bool isDuplicate = false,
  bool isAnalyticsExcluded = false,
}) async {
  await database.into(database.transactions).insert(
        TransactionsCompanion.insert(
          id: id,
          ts: timestamp.millisecondsSinceEpoch,
          amount: amount,
          direction: direction,
          channel: channel,
          accountHint: Value(accountHint),
          paymentSourceId: Value(paymentSourceId),
          merchantRaw: Value(merchantRaw),
          currencyCode: Value(currencyCode),
          currencySymbol: Value(currencySymbol),
          lifecycleState: Value(lifecycleState),
          isDeleted: Value(isDeleted),
          isNotTransaction: Value(isNotTransaction),
          duplicateOfTxnId: Value(isDuplicate ? 'bank-debit' : null),
          isAnalyticsExcluded: Value(isAnalyticsExcluded),
          parseSource: 'template',
          confidenceJson: '{}',
          status: 'confirmed',
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
}

Future<void> _seedReconciliationPair(
  AppDatabase database, {
  String? merchantRaw,
}) async {
  await _insertAuditSource(
    database,
    id: 'bank-source',
    kind: 'bank',
    mask: 'XX1001',
  );
  await _insertAuditSource(
    database,
    id: 'card-source',
    kind: 'card',
    mask: 'XX2002',
  );
  await _insertTransaction(
    database,
    id: 'bank-debit',
    amount: 150,
    direction: 'debit',
    channel: 'bank',
    paymentSourceId: 'bank-source',
    accountHint: '1234567890121001',
    merchantRaw: merchantRaw,
    timestamp: DateTime.utc(2026, 10, 4, 10),
    currencyCode: 'INR',
    currencySymbol: '₹',
  );
  await _insertTransaction(
    database,
    id: 'card-credit',
    amount: 150,
    direction: 'credit',
    channel: 'card',
    paymentSourceId: 'card-source',
    accountHint: '1234567890122002',
    timestamp: DateTime.utc(2026, 10, 4, 10, 4),
    currencyCode: 'INR',
    currencySymbol: '₹',
  );
}

Future<String> _seedAndSnapshot(AppDatabase database) async {
  final now = DateTime.utc(2026, 10, 4, 10);
  await _seedReconciliationPair(database, merchantRaw: 'Synthetic Grocery');
  await _insertAuditSource(
    database,
    id: 'inactive-source',
    kind: 'bank',
    mask: '9876543210004040',
    owned: false,
    active: false,
  );
  await _insertTransaction(
    database,
    id: 'flagged-review',
    amount: 777,
    direction: 'debit',
    channel: 'card',
    accountHint: '1234567890123003',
    paymentSourceId: 'card-source',
    timestamp: now.add(const Duration(minutes: 5)),
    isDeleted: true,
    isNotTransaction: true,
    isDuplicate: true,
    isAnalyticsExcluded: true,
  );
  await database.into(database.feedback).insert(
        FeedbackCompanion.insert(
          id: 'feedback-1',
          txnId: 'bank-debit',
          field: 'category',
          context: 'explicit-user-correction',
          createdAt: now.add(const Duration(minutes: 5)),
        ),
      );
  await database.into(database.transactionLinks).insert(
        TransactionLinksCompanion.insert(
          id: 'user-review-link',
          fromTxnId: 'flagged-review',
          toTxnId: 'bank-debit',
          linkType: 'echo',
          basis: 'synthetic-user-review',
          createdBy: const Value('user'),
          createdAt:
              now.add(const Duration(minutes: 6)).millisecondsSinceEpoch ~/
                  1000,
        ),
      );
  final before = await _stateSnapshot(database);

  final control = AppDatabase(NativeDatabase.memory());
  await control.customSelect('SELECT 1').get();
  await _seedReconciliationPair(control);
  final controlSources = await control.select(control.paymentSources).get();
  expect(controlSources, hasLength(2));
  expect(
    controlSources.every((source) => source.isOwned && source.isActive),
    isTrue,
  );
  expect(
    await PaymentSourceRepository(control).reconcileOwnedTransfers(),
    1,
  );
  expect(
    (await control.select(control.transactionLinks).get())
        .map((link) => link.linkType),
    contains('transfer_leg'),
  );
  await control.close();
  return before;
}

Future<void> _insertAuditSource(
  AppDatabase database, {
  required String id,
  required String kind,
  required String mask,
  bool owned = true,
  bool active = true,
}) async {
  final now = DateTime.utc(2026, 10, 4, 10);
  await database.into(database.paymentSources).insert(
        PaymentSourcesCompanion.insert(
          id: id,
          kind: kind,
          maskedIdentifier: mask,
          isOwned: Value(owned),
          isActive: Value(active),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<String> _stateSnapshot(AppDatabase database) async {
  final sources = await database
      .customSelect('SELECT * FROM payment_sources ORDER BY id')
      .get();
  final transactions = await database
      .customSelect('SELECT * FROM transactions ORDER BY id')
      .get();
  final links = await database
      .customSelect('SELECT * FROM transaction_links ORDER BY id')
      .get();
  final feedback =
      await database.customSelect('SELECT * FROM feedback ORDER BY id').get();
  final dashboard = await DashboardRepository(database).load(
    DashboardQueryWindow(
      start: DateTime.utc(2026, 10),
      end: DateTime.utc(2026, 11),
      previousStart: DateTime.utc(2026, 9),
      previousEnd: DateTime.utc(2026, 10),
      trendStart: DateTime.utc(2026, 6),
      trendEnd: DateTime.utc(2026, 11),
    ),
  );
  return jsonEncode([
    sources.map((row) => row.data).toList(),
    transactions.map((row) => row.data).toList(),
    links.map((row) => row.data).toList(),
    feedback.map((row) => row.data).toList(),
    [
      dashboard.debitTotal,
      dashboard.creditTotal,
      dashboard.previousSpend,
      dashboard.excludedDebitTotal,
      dashboard.excludedDebitCount,
      dashboard.categories
          .map((row) => [row.categoryId, row.name, row.icon, row.total])
          .toList(),
      dashboard.merchants
          .map((row) => [row.name, row.count, row.total])
          .toList(),
      dashboard.trendByMonth.entries
          .map((entry) => [entry.key, entry.value])
          .toList(),
      dashboard.currencyTotals
          .map(
            (row) => [
              row.currencyCode,
              row.currencySymbol,
              row.debitTotal,
              row.creditTotal,
            ],
          )
          .toList(),
    ],
  ]);
}

CardSourceAuditReport _emptyReport() => const CardSourceAuditReport(
      sources: [],
      sourcesTruncated: false,
      conflicts: [],
      conflictsTruncated: false,
      candidates: [],
      nextCursor: null,
      candidatesTruncated: false,
    );

CardSourceAuditReport _pageReport(
  String id,
  CardSourceAuditCursor? nextCursor, {
  bool truncated = true,
}) =>
    CardSourceAuditReport(
      sources: const [],
      sourcesTruncated: false,
      conflicts: const [],
      conflictsTruncated: false,
      candidates: [
        CardSourceAuditCandidate(
          id: id,
          timestampMs: 1000,
          amount: 1,
          direction: 'debit',
          currencyCode: null,
          currencySymbol: null,
          lifecycleState: 'settled',
          status: 'confirmed',
          sourceKind: 'Not available',
          maskedIdentifier: 'Not available',
          nickname: 'Not recorded',
          institution: 'Not recorded',
          sourceAvailable: false,
          isDeleted: false,
          isNotTransaction: false,
          isDuplicate: false,
          isAnalyticsExcluded: false,
          ownedTransferId: null,
        ),
      ],
      nextCursor: nextCursor,
      candidatesTruncated: truncated,
    );
