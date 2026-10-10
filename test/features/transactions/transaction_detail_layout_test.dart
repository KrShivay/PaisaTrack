import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/transaction_confidence_trail.dart';
import 'package:paisatrack/data/repositories/recurring_override_repository.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/data/repositories/transaction_sms_repository.dart';
import 'package:paisatrack/features/transactions/currency_repair_providers.dart';
import 'package:paisatrack/features/transactions/detail/transaction_source_sms_section.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

class _FakeRecurringRepository implements RecurringOverrideRepository {
  final calls = <(String, RecurringOverride)>[];

  @override
  Future<void> setOverride(
    String transactionId,
    RecurringOverride value,
  ) async {
    calls.add((transactionId, value));
  }

  @override
  Future<RecurringOverride> overrideFor(String transactionId) async =>
      RecurringOverride.automatic;

  @override
  Stream<RecurringOverride> watchOverride(String transactionId) =>
      Stream.value(RecurringOverride.automatic);

  @override
  Future<bool> isDetectedRecurring(String transactionId) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 7, 6, 9);
  final baseTxn = Transaction(
    id: 'txn_1',
    ts: now.millisecondsSinceEpoch,
    amount: 449,
    direction: 'debit',
    channel: 'upi',
    merchantRaw: 'amazon',
    parseSource: 'template',
    smsId: 'sms_1',
    confidenceJson: '{}',
    status: 'confirmed',
    isDeleted: false,
    isNotTransaction: false,
    isAnalyticsExcluded: false,
    lifecycleState: 'settled',
    createdAt: now,
    updatedAt: now,
  );

  TransactionDetail detailOf(Transaction txn, {String? body}) =>
      TransactionDetail(
        txn: txn,
        merchantName: 'Amazon',
        categoryName: 'Shopping',
        parseConfidence: 0.87,
        confidenceTrail: TransactionConfidenceTrail.fromJson('{}'),
        isLowTrustParse: false,
        rawSmsBody: body,
      );

  Future<void> pump(
    WidgetTester tester,
    TransactionDetail detail, {
    List<TransactionSmsMessage> messages = const [],
    RecurringOverrideRepository? recurring,
    RecurringOverride override = RecurringOverride.automatic,
    bool detectedRecurring = false,
    Size size = const Size(402, 874),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDetailProvider(detail.txn.id)
              .overrideWith((ref) => Stream.value(detail)),
          suggestedCategoriesProvider(detail.txn.id)
              .overrideWith((ref) async => const <String>[]),
          sourceCurrencyRepairPreviewProvider(detail.txn.id)
              .overrideWith((ref) async => null),
          transactionSmsMessagesProvider(detail.txn.id)
              .overrideWith((ref) async => messages),
          transactionRecurringOverrideProvider(detail.txn.id)
              .overrideWith((ref) => Stream.value(override)),
          transactionDetectedRecurringProvider(detail.txn.id)
              .overrideWith((ref) async => detectedRecurring),
          if (recurring != null)
            recurringOverrideRepositoryProvider
                .overrideWith((ref) async => recurring),
        ],
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp(
            home: BloomUndoToastHost(
              child: TransactionDetailScreen(txnId: detail.txn.id),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('orders Edit parse details, Source SMS, Transaction details',
      (tester) async {
    await pump(tester, detailOf(baseTxn, body: 'Paid Rs 449 to amazon'));

    final edit = find.textContaining('Edit Parse Details');
    final source = find.text('SOURCE SMS');
    final details = find.text('TRANSACTION DETAILS');
    expect(edit, findsOneWidget);
    expect(source, findsOneWidget);
    expect(details, findsOneWidget);
    double top(Finder f) => tester.getTopLeft(f).dy;
    expect(top(edit), lessThan(top(source)));
    expect(top(source), lessThan(top(details)));
    expect(find.text('Paid Rs 449 to amazon'), findsOneWidget);
    expect(find.textContaining('retention'), findsNothing);
  });

  testWidgets('shows a neutral state when the linked message is missing',
      (tester) async {
    await pump(tester, detailOf(baseTxn));

    expect(find.text('SOURCE SMS'), findsOneWidget);
    expect(find.text('Source message not available'), findsOneWidget);
    expect(find.textContaining('Restore SMS sources'), findsOneWidget);
  });

  testWidgets('hides the source section for rows with no SMS link',
      (tester) async {
    await pump(
      tester,
      detailOf(baseTxn.copyWith(smsId: const Value(null))),
    );
    expect(find.text('SOURCE SMS'), findsNothing);
  });

  testWidgets('copy rows exist only for values that are present',
      (tester) async {
    await pump(tester, detailOf(baseTxn));
    expect(find.byTooltip('Copy Amount'), findsOneWidget);
    expect(find.byTooltip('Copy Date and time'), findsOneWidget);
    expect(find.byTooltip('Copy UPI ID / VPA'), findsNothing);
    expect(find.byTooltip('Copy Reference / RRN'), findsNothing);
    expect(find.byTooltip('Copy Account or card'), findsNothing);
    expect(find.byTooltip('Copy Channel'), findsNothing);
    expect(find.byTooltip('Copy Direction'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await pump(
      tester,
      detailOf(
        baseTxn.copyWith(
          counterpartyVpa: const Value('shop@bank'),
          refId: const Value('624512345678'),
          accountHint: const Value('XX1234'),
        ),
      ),
    );
    expect(find.byTooltip('Copy UPI ID / VPA'), findsOneWidget);
    expect(find.byTooltip('Copy Reference / RRN'), findsOneWidget);
    expect(find.byTooltip('Copy Account or card'), findsOneWidget);
  });

  testWidgets('renders every linked SMS with role labels', (tester) async {
    await pump(
      tester,
      detailOf(baseTxn, body: 'fallback body'),
      messages: [
        TransactionSmsMessage(
          smsId: 'sms_1',
          sender: 'HDFCBK',
          body: 'Primary debit alert',
          receivedAt: now,
          role: TransactionSmsRole.primary,
        ),
        TransactionSmsMessage(
          smsId: 'sms_2',
          sender: 'HDFCBK',
          body: 'Same debit again',
          receivedAt: now,
          role: TransactionSmsRole.duplicate,
        ),
        TransactionSmsMessage(
          smsId: 'sms_3',
          sender: 'AXISMF',
          body: 'Dividend credited',
          receivedAt: now,
          role: TransactionSmsRole.supporting,
          kind: 'dividend',
        ),
        TransactionSmsMessage(
          smsId: 'sms_4',
          sender: 'BANK',
          body: 'Some other note',
          receivedAt: now,
          role: TransactionSmsRole.supporting,
        ),
      ],
    );

    expect(find.text('Primary debit alert'), findsOneWidget);
    expect(find.text('fallback body'), findsNothing);
    expect(find.text('Duplicate alert'), findsOneWidget);
    expect(find.text('Dividend advice'), findsOneWidget);
    expect(find.text('Related message'), findsOneWidget);
    expect(find.text('Copy message'), findsNWidgets(4));
    final primaryTop = tester.getTopLeft(find.text('Primary debit alert')).dy;
    final dupTop = tester.getTopLeft(find.text('Same debit again')).dy;
    expect(primaryTop, lessThan(dupTop));
  });

  test('smsRoleLabel maps kinds and roles', () {
    expect(
      smsRoleLabel(TransactionSmsRole.supporting, 'rd_instalment'),
      'RD instalment',
    );
    expect(
      smsRoleLabel(TransactionSmsRole.supporting, 'emi_notice'),
      'EMI notice',
    );
    expect(
      smsRoleLabel(TransactionSmsRole.supporting, 'collect_request'),
      'UPI payment request',
    );
    expect(
      smsRoleLabel(TransactionSmsRole.duplicate, null),
      'Duplicate alert',
    );
  });

  testWidgets('technical details are collapsed by default and expand',
      (tester) async {
    await pump(tester, detailOf(baseTxn, body: 'Paid Rs 449'));

    expect(find.text('Technical details'), findsOneWidget);
    expect(find.text('Transaction ID'), findsNothing);
    expect(find.text('Confidence'), findsNothing);

    final toggle = find.byKey(const ValueKey('technical_details_toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();

    expect(find.text('PARSING'), findsOneWidget);
    expect(find.text('IDENTITY'), findsOneWidget);
    expect(find.text('LIFECYCLE'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('txn_1'), findsOneWidget);
    expect(find.textContaining('Confidence JSON'), findsNothing);
  });

  testWidgets('recurring control calls setOverride and confirms',
      (tester) async {
    final repo = _FakeRecurringRepository();
    await pump(
      tester,
      detailOf(baseTxn),
      recurring: repo,
      detectedRecurring: true,
    );

    expect(find.text('Recurring payment'), findsOneWidget);
    expect(find.text('Detected as recurring'), findsOneWidget);

    final control = find.byKey(const ValueKey('recurring_override_control'));
    await tester.ensureVisible(control);
    await tester.tap(find.text('One-time'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.calls, [('txn_1', RecurringOverride.notRecurring)]);
    expect(find.text('Marked as one-time payment'), findsOneWidget);
  });

  testWidgets('fits 320x568 at 2x text without overflow', (tester) async {
    await pump(
      tester,
      detailOf(
        baseTxn.copyWith(
          counterpartyVpa: const Value('someone.long@okhdfcbank'),
          refId: const Value('624512345678'),
        ),
        body: 'Rs 449 debited from A/c XX1234 to VPA someone.long@okhdfcbank',
      ),
      messages: [
        TransactionSmsMessage(
          smsId: 'sms_9',
          sender: 'AXISMF',
          body: 'Dividend credited to your folio',
          receivedAt: now,
          role: TransactionSmsRole.supporting,
          kind: 'dividend',
        ),
      ],
      size: const Size(320, 568),
      textScale: 2,
    );
    final toggle = find.byKey(const ValueKey('technical_details_toggle'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    await tester.ensureVisible(find.text('One-time'));
    expect(tester.takeException(), isNull);
  });
}
