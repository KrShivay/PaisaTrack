import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/capture/sms_backfill.dart';
import 'package:paisatrack/features/sms/sms_lookup_sheet.dart';

class _FakeSmsHistoryImportRunner implements SmsHistoryImportRunner {
  @override
  Future<SmsImportResult> run({
    bool force = false,
    void Function(SmsImportProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const SmsImportProgress(
        processed: 1240,
        failed: 0,
        transactionsFound: 38,
        alreadyKnown: 27,
        totalMessages: 1240,
      ),
    );
    return const SmsImportResult(
      processed: 1240,
      failed: 0,
      transactionsFound: 38,
      alreadyKnown: 27,
      totalMessages: 1240,
    );
  }
}

class _FakeSmsPermissionGate implements SmsPermissionGate {
  _FakeSmsPermissionGate(this.statusValue);

  final SmsPermissionStatus statusValue;

  @override
  Future<SmsPermissionStatus> status() async => statusValue;

  @override
  Future<SmsPermissionStatus> request() async => statusValue;

  @override
  Future<void> openAppSettings() async {}
}

void main() {
  testWidgets('SmsLookupSheet renders header and ready state when permitted',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            _FakeSmsPermissionGate(SmsPermissionStatus.granted),
          ),
          smsHistoryImportRunnerProvider
              .overrideWith((ref) async => _FakeSmsHistoryImportRunner()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SmsLookupSheet(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify title and privacy reassurance
    expect(find.text('Find transactions from SMS'), findsOneWidget);
    expect(
      find.text('Scanned on this phone. Personal messages stay private.'),
      findsOneWidget,
    );

    // Verify Ready state buttons
    expect(find.text('Scan now'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('SmsLookupSheet renders permission needed state when denied',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            _FakeSmsPermissionGate(SmsPermissionStatus.denied),
          ),
          smsHistoryImportRunnerProvider
              .overrideWith((ref) async => _FakeSmsHistoryImportRunner()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SmsLookupSheet(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SMS access is off'), findsOneWidget);
    expect(find.text('Allow SMS access'), findsOneWidget);
  });

  testWidgets(
      'SmsLookupSheet renders permanently denied state with settings action',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          smsPermissionGateProvider.overrideWithValue(
            _FakeSmsPermissionGate(SmsPermissionStatus.permanentlyDenied),
          ),
          smsHistoryImportRunnerProvider
              .overrideWith((ref) async => _FakeSmsHistoryImportRunner()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SmsLookupSheet(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SMS permission permanently denied'), findsOneWidget);
    expect(find.text('Open Android settings'), findsOneWidget);
  });
}
