import 'package:drift/drift.dart' show Value;
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

  group('Bloom TransactionDetailScreen', () {
    final now = DateTime.utc(2026, 7, 6, 9);
    final testDetail = TransactionDetail(
      txn: Transaction(
        id: 'txn_101',
        ts: now.millisecondsSinceEpoch,
        amount: 449,
        direction: 'debit',
        channel: 'upi',
        categoryId: 'food_dining',
        merchantRaw: 'amazon',
        parseSource: 'template',
        confidenceJson: '{}',
        status: 'confirmed',
        isDeleted: false,
        isAnalyticsExcluded: false,
        lifecycleState: 'settled',
        createdAt: now,
        updatedAt: now,
      ),
      merchantName: 'amazon',
      categoryName: 'Food & Dining',
      parseConfidence: 0.98,
      confidenceTrail: TransactionConfidenceTrail.fromJson('{}'),
      isLowTrustParse: false,
    );

    testWidgets('renders transaction detail with category tile and hero amount',
        (tester) async {
      await pumpDetail(tester, testDetail);

      expect(find.text('Transaction Detail'), findsOneWidget);
      expect(find.text('amazon'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget);
      expect(find.byType(BloomCategoryTile), findsOneWidget);
      expect(find.byType(BloomAmount), findsOneWidget);
    });

    testWidgets('discloses technical details & raw SMS provenance when tapped',
        (tester) async {
      await pumpDetail(tester, testDetail);

      final techHeader = find.text('Technical details & SMS provenance');
      expect(techHeader, findsOneWidget);

      await tester.ensureVisible(techHeader);
      await tester.tap(techHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('Channel: upi'), findsOneWidget);
      expect(find.textContaining('CONFIDENCE: 98%'), findsOneWidget);
    });

    testWidgets('T-148a: category row is a >=48dp control with correct semantics',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpDetail(tester, testDetail);

      final inkWellFinder = find.ancestor(
        of: find.text('CATEGORY'),
        matching: find.byType(InkWell),
      );
      expect(inkWellFinder, findsOneWidget);

      final Size size = tester.getSize(inkWellFinder);
      expect(size.height, greaterThanOrEqualTo(48.0));
      handle.dispose();
    });

    testWidgets('T-148b: renders selected category chip in category hue and More... chip',
        (tester) async {
      await pumpDetail(tester, testDetail);

      expect(find.text('CATEGORY'), findsOneWidget);
      expect(find.text('Food & Dining'), findsOneWidget); // Selected chip
      expect(find.text('More…'), findsOneWidget);
    });

    testWidgets('T-147a: renders retained source message as a first-class section',
        (tester) async {
      final retainedDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(smsId: const Value('sms_001')),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: testDetail.parseConfidence,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: 'Paid Rs 449 to Swiggy on A/c XX1234',
      );

      await pumpDetail(tester, retainedDetail);

      expect(find.text('WHERE THIS CAME FROM'), findsOneWidget);
      expect(find.text('Paid Rs 449 to Swiggy on A/c XX1234'), findsOneWidget);
    });

    testWidgets('T-147a: renders retention degradation copy for purged SMS row',
        (tester) async {
      final purgedDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(smsId: const Value('sms_002')),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: testDetail.parseConfidence,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: null,
      );

      await pumpDetail(tester, purgedDetail);

      expect(find.text('WHERE THIS CAME FROM'), findsOneWidget);
      expect(
        find.text('Original message no longer stored — kept for 30 days'),
        findsOneWidget,
      );
    });

    testWidgets('T-147a: omits WHERE THIS CAME FROM section for manual entry rows',
        (tester) async {
      final manualDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(smsId: const Value(null)),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: testDetail.parseConfidence,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: null,
      );

      await pumpDetail(tester, manualDetail);

      expect(find.text('WHERE THIS CAME FROM'), findsNothing);
    });

    testWidgets('T-147b: renders Parsed locally badge and parser name for template source',
        (tester) async {
      final templateDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(
          id: 'txn_tmpl_147b',
          smsId: const Value('sms_001'),
          parseSource: 'template',
        ),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: 0.99,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: 'Paid Rs 449 to Swiggy on A/c XX1234',
      );

      await pumpDetail(tester, templateDetail);

      expect(find.text('Parsed locally'), findsOneWidget);
      expect(find.text('Template match · 99%'), findsOneWidget);
    });

    testWidgets('T-147b: renders Parsed locally badge and parser name for generic source',
        (tester) async {
      final genericDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(
          id: 'txn_gen_147b',
          smsId: const Value('sms_002'),
          parseSource: 'generic',
        ),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: 0.85,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: 'Rs 100 paid to Cafe',
      );

      await pumpDetail(tester, genericDetail);

      expect(find.text('Parsed locally'), findsOneWidget);
      expect(find.text('Pattern match · 85%'), findsOneWidget);
    });

    testWidgets('T-147b: renders Parsed locally badge and parser name for LLM source',
        (tester) async {
      final llmDetail = TransactionDetail(
        txn: testDetail.txn.copyWith(
          id: 'txn_llm_147b',
          smsId: const Value('sms_003'),
          parseSource: 'llm',
        ),
        merchantName: testDetail.merchantName,
        categoryName: testDetail.categoryName,
        parseConfidence: 0.92,
        confidenceTrail: testDetail.confidenceTrail,
        isLowTrustParse: testDetail.isLowTrustParse,
        rawSmsBody: 'Debited Rs 500 at Uber',
      );

      await pumpDetail(tester, llmDetail);

      expect(find.text('Parsed locally'), findsOneWidget);
      expect(find.text('AI model · 92%'), findsOneWidget);
    });
  });
}
