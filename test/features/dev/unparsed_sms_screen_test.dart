import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/raw_sms_repository.dart';
import 'package:paisatrack/capture/template_engine/template_trust_ledger.dart';
import 'package:paisatrack/features/dev/unparsed_sms_providers.dart';
import 'package:paisatrack/features/dev/unparsed_sms_screen.dart';
import 'package:paisatrack/features/dev/transaction_export.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    List<UnparsedSms> messages, {
    List<TemplateTrustEntry> trustAlerts = const [],
    Future<bool> Function()? exportTransactions,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unparsedSmsListProvider.overrideWith(
            (ref) => Stream.value(messages),
          ),
          templateTrustAlertsProvider.overrideWith(
            (ref) => Stream.value(trustAlerts),
          ),
          if (exportTransactions != null)
            transactionJsonExportProvider.overrideWith(
              (ref) => exportTransactions(),
            ),
        ],
        child: const MaterialApp(home: UnparsedSmsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows an empty state with no unparsed sms', (tester) async {
    await pumpScreen(tester, const []);

    expect(find.text('No unparsed messages'), findsOneWidget);
  });

  testWidgets('lists unprocessed raw sms rows', (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);

    await pumpScreen(tester, [
      UnparsedSms(
        id: 'sms_unparsed',
        sender: 'AX-UNKNOWN',
        body: 'Some unrecognized bank message format',
        receivedAt: now,
      ),
    ]);

    expect(find.text('AX-UNKNOWN'), findsOneWidget);
    expect(
      find.textContaining('Some unrecognized bank message format'),
      findsOneWidget,
    );
    // No direction keyword in the body → recomputed per-stage reason (T-070).
    expect(
      find.textContaining(
        'Template: no match · Generic parser: no debit/credit direction',
      ),
      findsOneWidget,
    );
  });

  testWidgets('recomputes a distinct generic reason per row (T-070)',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);

    await pumpScreen(tester, [
      UnparsedSms(
        id: 'reject_otp',
        sender: 'AX-OTP',
        body: 'Rs. 500 will be debited from A/c XX1234 tomorrow',
        receivedAt: now,
      ),
      UnparsedSms(
        id: 'reject_no_context',
        sender: 'AX-CTX',
        body: 'Rs. 250 debited towards groceries',
        receivedAt: now,
      ),
    ]);

    expect(
      find.textContaining('Generic parser: non-transaction phrase'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Generic parser: no account/UPI/channel signal'),
      findsOneWidget,
    );
  });

  testWidgets('flags demoted public template ids for developers',
      (tester) async {
    await pumpScreen(
      tester,
      const [],
      trustAlerts: const [
        TemplateTrustEntry(
          templateId: 'kotak_upi_v1',
          confirmedParses: 20,
          amountCorrections: 1,
          directionCorrections: 0,
        ),
      ],
    );

    expect(find.text('Template trust alert'), findsOneWidget);
    expect(find.textContaining('kotak_upi_v1'), findsOneWidget);
  });

  testWidgets('warns before plaintext export and handles picker cancellation',
      (tester) async {
    var exportCalls = 0;
    await pumpScreen(
      tester,
      const [],
      exportTransactions: () async {
        exportCalls++;
        return false;
      },
    );

    await tester.tap(find.byTooltip('Export transactions JSON (debug)'));
    await tester.pumpAndSettle();
    expect(find.text('Export plaintext transaction data?'), findsOneWidget);
    expect(exportCalls, 0);

    await tester.tap(find.text('Choose destination'));
    await tester.pumpAndSettle();
    expect(exportCalls, 1);
    expect(find.text('Export cancelled'), findsOneWidget);
  });

  test('repository lists unprocessed raw sms and excludes processed ones',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final now = DateTime.utc(2026, 7, 6, 9);

    await database.into(database.rawSms).insertOnConflictUpdate(
          RawSmsCompanion.insert(
            id: 'sms_unparsed',
            sender: 'AX-UNKNOWN',
            body: 'Some unrecognized bank message format',
            receivedAt: now,
            purgeAfter: now.add(const Duration(days: 30)),
          ),
        );
    await database.into(database.rawSms).insertOnConflictUpdate(
          RawSmsCompanion.insert(
            id: 'sms_parsed',
            sender: 'AX-SBIINB',
            body: 'Your a/c is debited',
            receivedAt: now,
            purgeAfter: now.add(const Duration(days: 30)),
            processed: const Value(true),
          ),
        );

    final rows = await RawSmsRepository(database).watchUnparsed().first;

    expect(rows.map((row) => row.id), ['sms_unparsed']);
    expect(rows.single.sender, 'AX-UNKNOWN');
  });
}
