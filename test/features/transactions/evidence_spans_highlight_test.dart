import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/models/transaction_confidence_trail.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transaction_detail_screen.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDetail(
    WidgetTester tester,
    TransactionDetail detail,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDetailProvider(detail.txn.id)
              .overrideWith((ref) => Stream.value(detail)),
        ],
        child: MaterialApp(
          home: BloomUndoToastHost(
            child: TransactionDetailScreen(txnId: detail.txn.id),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  group('Technical SMS Evidence Spans Highlight', () {
    final now = DateTime.utc(2026, 7, 10);
    const smsBody = 'Rs.450.00 debited from A/C XX1234 on 10-Jul-26 at Swiggy';

    testWidgets('Template-parsed transaction highlights evidence spans in technical details section', (tester) async {
      final detail = TransactionDetail(
        txn: Transaction(
          id: 'txn_ev_001',
          smsId: 'sms_001',
          ts: now.millisecondsSinceEpoch,
          amount: 450.0,
          direction: 'debit',
          channel: 'upi',
          categoryId: 'food_dining',
          merchantRaw: 'Swiggy',
          parseSource: 'template',
          confidenceJson: '{"parser":{"c":0.98}}',
          evidenceJson: '[{"field":"amount","start":3,"end":9,"verbatim":"450.00","extractor":"template"},{"field":"direction","start":10,"end":17,"verbatim":"debited","extractor":"template"}]',
          status: 'confirmed',
          isDeleted: false,
          isAnalyticsExcluded: false,
          lifecycleState: 'settled',
          createdAt: now,
          updatedAt: now,
        ),
        merchantName: 'Swiggy',
        categoryName: 'Food & Dining',
        parseConfidence: 0.98,
        confidenceTrail: TransactionConfidenceTrail.fromJson('{"parser":{"c":0.98}}'),
        isLowTrustParse: false,
        rawSmsBody: smsBody,
      );

      await pumpDetail(tester, detail);

      final expander = find.text('Technical details & SMS provenance');
      expect(expander, findsOneWidget);
      await tester.ensureVisible(expander);
      await tester.tap(expander);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('FIELD EVIDENCE SPANS'), findsOneWidget);
      expect(find.textContaining('amount: "450.00" (template, 98%)'), findsOneWidget);
      expect(find.textContaining('direction: "debited" (template, 98%)'), findsOneWidget);
    });

    testWidgets('Row with purged raw_sms degrades to retention text without error', (tester) async {
      final detail = TransactionDetail(
        txn: Transaction(
          id: 'txn_purged',
          smsId: 'sms_purged',
          ts: now.millisecondsSinceEpoch,
          amount: 1200.0,
          direction: 'debit',
          channel: 'card',
          categoryId: 'shopping',
          parseSource: 'template',
          confidenceJson: '{"parser":{"c":0.90}}',
          evidenceJson: '[{"field":"amount","start":0,"end":4,"verbatim":"1200","extractor":"template"}]',
          status: 'confirmed',
          isDeleted: false,
          isAnalyticsExcluded: false,
          lifecycleState: 'settled',
          createdAt: now,
          updatedAt: now,
        ),
        merchantName: 'Amazon',
        categoryName: 'Shopping',
        parseConfidence: 0.90,
        confidenceTrail: TransactionConfidenceTrail.fromJson('{"parser":{"c":0.90}}'),
        isLowTrustParse: false,
        rawSmsBody: null, // Purged
      );

      await pumpDetail(tester, detail);

      final expander = find.text('Technical details & SMS provenance');
      await tester.ensureVisible(expander);
      await tester.tap(expander);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Source message purged per retention policy'), findsOneWidget);
    });

    testWidgets('Pre-T-131 row with null evidence shows body without highlights', (tester) async {
      const legacyBody = 'INR 800 paid to Uber via UPI';
      final detail = TransactionDetail(
        txn: Transaction(
          id: 'txn_legacy',
          smsId: 'sms_legacy',
          ts: now.millisecondsSinceEpoch,
          amount: 800.0,
          direction: 'debit',
          channel: 'upi',
          categoryId: 'travel',
          parseSource: 'generic',
          confidenceJson: '{}',
          evidenceJson: null,
          status: 'confirmed',
          isDeleted: false,
          isAnalyticsExcluded: false,
          lifecycleState: 'settled',
          createdAt: now,
          updatedAt: now,
        ),
        merchantName: 'Uber',
        categoryName: 'Travel',
        parseConfidence: 0.85,
        confidenceTrail: TransactionConfidenceTrail.fromJson('{}'),
        isLowTrustParse: false,
        rawSmsBody: legacyBody,
      );

      await pumpDetail(tester, detail);

      final expander = find.text('Technical details & SMS provenance');
      await tester.ensureVisible(expander);
      await tester.tap(expander);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('FIELD EVIDENCE SPANS'), findsOneWidget);
      expect(find.text(legacyBody), findsWidgets);
    });
  });
}
