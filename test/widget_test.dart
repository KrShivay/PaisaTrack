import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/app.dart';
import 'package:paisatrack/capture/captured_sms_source.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/core/undo/undo_controller.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/home/home_shell.dart';
import 'package:paisatrack/features/insights/insights_screen.dart';
import 'package:paisatrack/features/review/weekly_review_screen.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';

import 'support/fake_sms_permission_gate.dart';
import 'support/fake_captured_sms_source.dart';

void main() {
  test('persisted completion routes denied permission to Home', () {
    expect(
      appStartupDestination(
        permission: const AsyncData<SmsPermissionStatus>(
          SmsPermissionStatus.denied,
        ),
        settings: const AsyncData<AppSettings>(
          AppSettings(onboardingCompleted: true),
        ),
      ),
      AppStartupDestination.home,
    );
  });

  test('permission refresh with previous value keeps completed onboarding home',
      () {
    final permission =
        const AsyncLoading<SmsPermissionStatus>().copyWithPrevious(
      const AsyncData<SmsPermissionStatus>(SmsPermissionStatus.denied),
    );

    expect(
      appStartupDestination(
        permission: permission,
        settings: const AsyncData<AppSettings>(
          AppSettings(onboardingCompleted: true),
        ),
      ),
      AppStartupDestination.home,
    );
  });

  test('settings loading routes to startup screen', () {
    expect(
      appStartupDestination(
        permission: const AsyncData<SmsPermissionStatus>(
          SmsPermissionStatus.denied,
        ),
        settings: const AsyncLoading<AppSettings>(),
      ),
      AppStartupDestination.loading,
    );
  });

  test('load errors fall through to onboarding instead of spinning', () {
    expect(
      appStartupDestination(
        permission: AsyncError<SmsPermissionStatus>(
          StateError('channel'),
          StackTrace.empty,
        ),
        settings: AsyncError<AppSettings>(
          StateError('settings'),
          StackTrace.empty,
        ),
      ),
      AppStartupDestination.onboarding,
    );
  });

  testWidgets('renders startup progress before permission lookup completes',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final gate = _DelayedSmsPermissionGate();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          appSettingsControllerProvider.overrideWith(
            () => _StaticSettingsController(const AppSettings()),
          ),
          smsPermissionGateProvider.overrideWithValue(gate),
        ],
        child: const PaisaTrackApp(),
      ),
    );

    expect(find.text('Loading your local data…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete(SmsPermissionStatus.denied);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('SMS'), findsWidgets);

    await database.close();
  });

  testWidgets('renders the app shell', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          appSettingsControllerProvider.overrideWith(
            () => _StaticSettingsController(const AppSettings()),
          ),
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
          capturedSmsSourceProvider
              .overrideWithValue(const FakeCapturedSmsSource()),
        ],
        child: const PaisaTrackApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Home'), findsWidgets);
    expect(find.byType(TransactionsScreen), findsNothing);
    expect(find.byType(WeeklyReviewScreen), findsNothing);
    expect(find.byType(InsightsScreen), findsNothing);

    await tester.tap(find.text('Activity').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TransactionsScreen), findsOneWidget);
    expect(find.byType(WeeklyReviewScreen), findsNothing);
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('Trends'), findsOneWidget);

    await database.close();
  });

  testWidgets('PaisaTrackApp shows a tappable undo above a root route',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          appSettingsControllerProvider.overrideWith(
            () => _StaticSettingsController(const AppSettings()),
          ),
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
          capturedSmsSourceProvider
              .overrideWithValue(const FakeCapturedSmsSource()),
        ],
        child: const PaisaTrackApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final homeContext = tester.element(find.byType(HomeShell));
    Navigator.of(homeContext, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Root detail route')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    var didUndo = false;
    final routeContext = tester.element(find.text('Root detail route'));
    ProviderScope.containerOf(routeContext)
        .read(undoControllerProvider.notifier)
        .pushUndo(
          UndoToken(
            id: 'app-root-route-action',
            message: 'Root route action',
            undoAction: () async => didUndo = true,
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Root route action'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(didUndo, isTrue);

    await database.close();
  });

  testWidgets('permission request preserves the existing HomeShell state',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final gate = _DelayedRequestSmsPermissionGate();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          appSettingsControllerProvider.overrideWith(
            () => _StaticSettingsController(
              const AppSettings(onboardingCompleted: true),
            ),
          ),
          smsPermissionGateProvider.overrideWithValue(gate),
          capturedSmsSourceProvider
              .overrideWithValue(const FakeCapturedSmsSource()),
        ],
        child: const PaisaTrackApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final homeState = tester.state(find.byType(HomeShell));
    await tester.tap(find.text('Activity').last);
    await tester.pump(const Duration(milliseconds: 300));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
      listen: false,
    );
    final pendingRequest =
        container.read(smsPermissionControllerProvider.notifier).request();
    await tester.pump();

    expect(find.text('Loading your local data…'), findsNothing);
    expect(tester.state(find.byType(HomeShell)), same(homeState));

    gate.completeRequest(SmsPermissionStatus.denied);
    await pendingRequest;
    await tester.pump();
    expect(tester.state(find.byType(HomeShell)), same(homeState));

    await database.close();
  });

  testWidgets('boots with an in-memory app database override', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
          appSettingsControllerProvider.overrideWith(
            () => _StaticSettingsController(const AppSettings()),
          ),
          capturedSmsSourceProvider
              .overrideWithValue(const FakeCapturedSmsSource()),
          appDatabaseProvider.overrideWith((ref) async => database),
        ],
        child: const PaisaTrackApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Home'), findsWidgets);

    final container = ProviderScope.containerOf(
      tester.element(find.text('Home').first),
      listen: false,
    );
    expect(await container.read(appDatabaseProvider.future), same(database));

    // flutter_test disposes the widget tree (and drift's watch() stream)
    // before any tearDown/addTearDown callback runs, so close() must happen
    // here, before the test body returns, or drift's markAsClosed() schedules
    // a debounce Timer.run that outlives the test — see the comment in
    // drift's StreamQueryStore.markAsClosed.
    await database.close();
  });
}

class _DelayedSmsPermissionGate implements SmsPermissionGate {
  final Completer<SmsPermissionStatus> _status = Completer();

  void complete(SmsPermissionStatus value) => _status.complete(value);

  @override
  Future<SmsPermissionStatus> status() => _status.future;

  @override
  Future<SmsPermissionStatus> request() async => SmsPermissionStatus.denied;

  @override
  Future<void> openAppSettings() async {}
}

class _StaticSettingsController extends AppSettingsController {
  _StaticSettingsController(this._settings);

  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _DelayedRequestSmsPermissionGate implements SmsPermissionGate {
  final _requestResult = Completer<SmsPermissionStatus>();

  void completeRequest(SmsPermissionStatus status) =>
      _requestResult.complete(status);

  @override
  Future<SmsPermissionStatus> status() async => SmsPermissionStatus.denied;

  @override
  Future<SmsPermissionStatus> request() => _requestResult.future;

  @override
  Future<void> openAppSettings() async {}
}
