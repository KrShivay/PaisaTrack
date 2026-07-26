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
  });
}
