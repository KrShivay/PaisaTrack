import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/dashboard/dashboard_screen.dart';
import 'package:paisatrack/features/dashboard/dashboard_widgets.dart';
import 'package:paisatrack/features/transactions/transactions_providers.dart';

import '../../support/fake_sms_permission_gate.dart';
import '../../support/fake_captured_sms_source.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/capture/captured_sms_source.dart';

TransactionListItem item({
  required String id,
  required DateTime ts,
  required double amount,
  required TransactionDirection direction,
  String? categoryId,
  String? categoryName,
}) {
  return TransactionListItem(
    id: id,
    ts: ts,
    amount: amount,
    direction: direction,
    displayName: 'Merchant',
    categoryId: categoryId,
    categoryName: categoryName ?? 'Uncategorised',
    categoryIcon: 'food',
    includeInAnalytics: true,
  );
}

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester,
    List<TransactionListItem> list,
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
          transactionListProvider.overrideWith((ref) => Stream.value(list)),
          smsPermissionGateProvider.overrideWithValue(
            FakeSmsPermissionGate(
              initialStatus: SmsPermissionStatus.granted,
            ),
          ),
          capturedSmsSourceProvider.overrideWithValue(
            const FakeCapturedSmsSource(),
          ),
        ],
        child: const MaterialApp(home: DashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('renders Bloom hero ring and header', (tester) async {
    await pumpDashboard(tester, const []);

    expect(find.byType(BloomHeroRing), findsOneWidget);
    expect(find.text('Hey Shivay'), findsOneWidget);
  });

  testWidgets('renders metric switcher pills', (tester) async {
    await pumpDashboard(tester, const []);

    expect(find.byType(BloomMetricSwitcherPills), findsOneWidget);
    expect(find.text('Safe today'), findsOneWidget);
    expect(find.text('Net flow'), findsOneWidget);
    expect(find.text('Burn'), findsOneWidget);
    expect(find.text('Runway'), findsOneWidget);
  });
}
