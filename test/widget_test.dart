import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/app.dart';
import 'package:paisatrack/capture/captured_sms_source.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';

import 'support/fake_sms_permission_gate.dart';
import 'support/fake_captured_sms_source.dart';

void main() {
  testWidgets('renders startup progress before permission lookup completes',
      (tester) async {
    final gate = _DelayedSmsPermissionGate();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [smsPermissionGateProvider.overrideWithValue(gate)],
        child: const PaisaTrackApp(),
      ),
    );

    expect(find.text('Loading your local data…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete(SmsPermissionStatus.denied);
    await tester.pumpAndSettle();
    expect(find.text('Read bank SMS on this device'), findsOneWidget);
  });

  testWidgets('renders the app shell', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
  });

  testWidgets('boots with an in-memory app database override', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
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
}
