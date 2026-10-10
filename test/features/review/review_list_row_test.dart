import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/review/review_list_row.dart';

const _longName = 'Synthetic Shop With A Rather Long Merchant Name';

TransactionReviewItem _item({
  String? vpa,
  TransactionDirection direction = TransactionDirection.debit,
  String? currencyCode,
  String? currencySymbol,
}) =>
    TransactionReviewItem(
      id: 'row1',
      ts: DateTime.utc(2026, 7, 11, 10),
      amount: 1234.5,
      direction: direction,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
      displayName: _longName,
      categoryName: 'Food & Dining',
      categoryId: 'food_cat',
      categoryIcon: 'food',
      status: 'needs_review',
      counterpartyVpa: vpa,
    );

void main() {
  Future<Map<String, int>> pump(
    WidgetTester tester, {
    required TransactionReviewItem item,
    Size size = const Size(402, 874),
    double textScale = 1,
    bool isDark = false,
    bool keepEnabled = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final calls = <String, int>{};
    void hit(String k) => calls[k] = (calls[k] ?? 0) + 1;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ReviewListRow(
              item: item,
              isDark: isDark,
              keepEnabled: keepEnabled,
              onOpen: () => hit('open'),
              onConfirm: () => hit('keep'),
              onRecategorize: () => hit('category'),
              onSkip: () => hit('skip'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return calls;
  }

  final tile = find.byKey(const ValueKey('review_tile_row1'));

  for (final config in [
    (size: const Size(320, 568), scale: 2.0, dark: false),
    (size: const Size(320, 568), scale: 2.0, dark: true),
    (size: const Size(402, 874), scale: 1.0, dark: false),
    (size: const Size(402, 874), scale: 1.0, dark: true),
  ]) {
    testWidgets(
        'row has no overflow and keeps QR inside tile at '
        '${config.size.width.toInt()}dp x${config.scale} dark=${config.dark}',
        (tester) async {
      await pump(
        tester,
        item: _item(
          vpa: 'synthetic.shop@upi',
          currencyCode: 'USD',
          currencySymbol: r'$',
        ),
        size: config.size,
        textScale: config.scale,
        isDark: config.dark,
      );
      expect(tester.takeException(), isNull);
      final qr = find.byTooltip('Show UPI QR');
      expect(qr, findsOneWidget);
      final rowRect = tester.getRect(tile);
      final qrRect = tester.getRect(qr);
      expect(qrRect.width, greaterThanOrEqualTo(48));
      expect(qrRect.height, greaterThanOrEqualTo(48));
      expect(rowRect.contains(qrRect.topLeft), isTrue);
      expect(rowRect.contains(qrRect.bottomRight), isTrue);
      // Inset from the rounded corner so the whole target stays hittable.
      expect(rowRect.right - qrRect.right, greaterThanOrEqualTo(8));
      expect(rowRect.bottom - qrRect.bottom, greaterThanOrEqualTo(6));
    });
  }

  testWidgets('tapping the body opens, quick actions fire, QR does not open',
      (tester) async {
    final calls = await pump(tester, item: _item(vpa: 'synthetic.shop@upi'));
    await tester.tap(find.text(_longName));
    expect(calls['open'], 1);
    await tester.tap(find.text('Keep'));
    await tester.tap(find.text('Category'));
    await tester.tap(find.text('Skip'));
    expect(calls, {'open': 1, 'keep': 1, 'category': 1, 'skip': 1});
    await tester.tap(find.byTooltip('Show UPI QR'));
    await tester.pumpAndSettle();
    expect(calls['open'], 1);
    expect(find.text('UPI QR code'), findsOneWidget);
  });

  testWidgets('Keep is disabled when blocked and no QR without a VPA',
      (tester) async {
    final calls = await pump(tester, item: _item(), keepEnabled: false);
    await tester.tap(find.text('Keep'), warnIfMissed: false);
    expect(calls['keep'], isNull);
    expect(find.byTooltip('Show UPI QR'), findsNothing);
  });

  testWidgets('compact text uses 48dp icon actions without overflow',
      (tester) async {
    final calls = await pump(
      tester,
      item: _item(vpa: 'synthetic.shop@upi'),
      size: const Size(320, 568),
      textScale: 2,
    );
    for (final label in ['Keep', 'Category', 'Skip']) {
      final rect = tester.getRect(find.byTooltip(label));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byTooltip('Skip'));
    expect(calls['skip'], 1);
    expect(tester.takeException(), isNull);
  });
}
