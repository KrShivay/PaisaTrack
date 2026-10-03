import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/transactions/transactions_screen.dart';

import '../../support/drift_widget_teardown.dart';
import '../../support/fake_sms_permission_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('T-198 Activity titles VPA-only rows with a readable name',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    final ts = DateTime.utc(2026, 9, 30, 12);
    Future<void> insert(String id, {String? raw, String? vpa}) =>
        database.into(database.transactions).insert(
              TransactionsCompanion.insert(
                id: id,
                ts: ts.millisecondsSinceEpoch,
                amount: 250,
                direction: 'debit',
                channel: 'upi',
                merchantRaw: Value(raw),
                counterpartyVpa: Value(vpa),
                parseSource: 'template',
                confidenceJson: '{}',
                status: 'confirmed',
                createdAt: ts,
                updatedAt: ts,
              ),
            );
    await insert('zomato', vpa: 'payzomato@hdfcbank');
    await insert('gateway', raw: 'paytm.s22rtcb@pty', vpa: 'paytm.s22rtcb@pty');
    await insert('named', raw: 'SWIGGY', vpa: 'swiggy.stores@icici');

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
    await pumpDriftFrames(tester);

    expect(find.text('Zomato'), findsOneWidget);
    expect(find.text('paytm.s22rtcb@pty'), findsOneWidget);
    expect(find.text('SWIGGY'), findsOneWidget);
    expect(find.text('payzomato@hdfcbank'), findsNothing);
    // Display only: nothing was written back.
    final rows = await database.select(database.transactions).get();
    expect(rows.map((row) => row.merchantRaw), contains(isNull));

    await unmountAndCloseDatabase(tester, database);
  });

  testWidgets('T-198 a VPA payee filter still finds its readable rows',
      (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase(NativeDatabase.memory());
    final ts = DateTime.utc(2026, 9, 30, 12);
    for (final (id, vpa) in [
      ('zomato', 'payzomato@hdfcbank'),
      ('other', 'swiggy.stores@icici'),
    ]) {
      await database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: ts.millisecondsSinceEpoch,
              amount: 250,
              direction: 'debit',
              channel: 'upi',
              counterpartyVpa: Value(vpa),
              parseSource: 'template',
              confidenceJson: '{}',
              status: 'confirmed',
              createdAt: ts,
              updatedAt: ts,
            ),
          );
    }

    // A recurring series labelled with the raw VPA opens Activity like this.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => database),
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
          ),
        ],
        child: const MaterialApp(
          home: TransactionsScreen(initialMerchant: 'payzomato@hdfcbank'),
        ),
      ),
    );
    await pumpDriftFrames(tester);

    expect(find.text('Zomato'), findsOneWidget);
    expect(find.text('Swiggy'), findsNothing);

    await tester.enterText(find.byType(TextField), 'payzomato');
    await pumpDriftFrames(tester);
    expect(find.text('Zomato'), findsOneWidget);

    await unmountAndCloseDatabase(tester, database);
  });
}
