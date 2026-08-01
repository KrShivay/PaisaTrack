import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/raw_sms_repository.dart';
import 'package:paisatrack/capture/sms_filter_diagnostics.dart';
import 'package:paisatrack/capture/template_engine/template_trust_ledger.dart';
import 'package:paisatrack/features/dev/unparsed_sms_providers.dart';
import 'package:paisatrack/features/dev/unparsed_sms_screen.dart';
import 'package:paisatrack/features/dev/sms_fixture_donation.dart';
import 'package:paisatrack/features/dev/transaction_export.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    List<UnparsedSms> messages, {
    List<TemplateTrustEntry> trustAlerts = const [],
    SmsFilterCounters nativeCounters = const SmsFilterCounters.zero(),
    Future<bool> Function()? exportTransactions,
    SmsFixtureCopier? copyFixture,
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
          smsFilterCountersProvider.overrideWith(
            (ref) async => nativeCounters,
          ),
          if (exportTransactions != null)
            transactionJsonExportProvider.overrideWith(
              (ref) => exportTransactions(),
            ),
          if (copyFixture != null)
            smsFixtureCopierProvider.overrideWithValue(copyFixture),
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

  testWidgets('shows content-free native capture counters', (tester) async {
    await pumpScreen(
      tester,
      const [],
      nativeCounters: const SmsFilterCounters(
        liveFilterRejected: 2,
        batchFilterRejected: 3,
        liveUnknownSender: 4,
        batchUnknownSender: 5,
      ),
    );

    expect(find.text('Native capture counters'), findsOneWidget);
    expect(
      find.textContaining('Live: 4 unknown sender · 2 filtered'),
      findsOneWidget,
    );
    expect(
      find.textContaining('History scan: 5 unknown sender · 3 filtered'),
      findsOneWidget,
    );
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
        body: 'Your OTP is 482910 for Rs. 500 debited from A/c XX1234',
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

  testWidgets('previews exact sanitized device fixture before copying',
      (tester) async {
    String? copied;
    final sms = UnparsedSms(
      id: 'sms_donate',
      sender: 'AX-BANK',
      body: 'Dear Priya Sharma, Rs. 1,250 debited from A/c XX123456. '
          'Avl Bal Rs. 9,876.50 Ref No 123456789.',
      receivedAt: DateTime.utc(2026, 7, 11),
    );
    await pumpScreen(
      tester,
      [sms],
      copyFixture: (value) async => copied = value,
    );

    await tester.tap(find.byTooltip('Share sanitized SMS'));
    await tester.pumpAndSettle();

    final expected = const SmsFixtureDonation().fixture(sms);
    expect(find.text('Review sanitized SMS'), findsOneWidget);
    expect(find.text(expected), findsOneWidget);
    expect(expected, contains('<NAME>'));
    expect(expected, contains('<ACCOUNT>'));
    expect(expected, contains('<BALANCE>'));
    expect(expected, contains('Rs. 1,250'));
    expect(expected, contains('"provenance": "device"'));
    expect(copied, null);

    await tester.tap(find.text('Approve and copy'));
    await tester.pumpAndSettle();
    expect(copied, expected);
    expect(find.text('Sanitized fixture copied'), findsOneWidget);
  });

  testWidgets('cancel leaves sanitized fixture on device', (tester) async {
    var copyCalls = 0;
    await pumpScreen(
      tester,
      [
        UnparsedSms(
          id: 'sms_cancel',
          sender: 'AX-BANK',
          body: 'A/c 123456 debited Rs. 100',
          receivedAt: DateTime.utc(2026, 7, 11),
        ),
      ],
      copyFixture: (_) async => copyCalls++,
    );

    await tester.tap(find.byTooltip('Share sanitized SMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(copyCalls, 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('displays unparsed reason breakdown summary card',
      (tester) async {
    final now = DateTime.utc(2026, 7, 6, 9);
    await pumpScreen(tester, [
      UnparsedSms(
        id: 'sms_otp',
        sender: 'AX-OTP',
        body: 'Your OTP for login is 123456',
        receivedAt: now,
      ),
      UnparsedSms(
        id: 'sms_bank',
        sender: 'AX-HDFCBK',
        body: 'Rs. 450 debited for dinner',
        receivedAt: now,
      ),
    ]);

    expect(find.textContaining('Rejection reasons:'), findsOneWidget);
    expect(find.textContaining('OTP / Authentication: 1'), findsOneWidget);
    expect(find.textContaining('Unmatched financial SMS: 1'), findsOneWidget);
  });

  test(
      'categorizeUnparsedSms classifies balance and login footer messages correctly',
      () {
    expect(
      categorizeUnparsedSms('Avail Bal in A/C XX1234 is INR 5,230.00'),
      UnparsedReason.balanceInfo,
    );
    expect(
      categorizeUnparsedSms(
        'Rs.500 debited from A/C x1234. Login to NetBanking.',
      ),
      UnparsedReason.unmatchedFinancial,
    );
    expect(
      categorizeUnparsedSms('Your OTP for login is 123456'),
      UnparsedReason.otpAuth,
    );
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
