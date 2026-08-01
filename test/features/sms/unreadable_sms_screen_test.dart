import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/capture/parser_version.dart';
import 'package:paisatrack/capture/sms_backfill.dart';
import 'package:paisatrack/data/repositories/raw_sms_repository.dart';
import 'package:paisatrack/features/sms/unreadable_sms_screen.dart';

class _FakePermissionGate implements SmsPermissionGate {
  @override
  Future<SmsPermissionStatus> status() async => SmsPermissionStatus.granted;

  @override
  Future<SmsPermissionStatus> request() async => SmsPermissionStatus.granted;

  @override
  Future<void> openAppSettings() async {}
}

class _FakeImportRunner implements SmsHistoryImportRunner {
  int calls = 0;
  bool? lastForce;

  @override
  Future<SmsImportResult> run({
    bool force = false,
    void Function(SmsImportProgress progress)? onProgress,
  }) async {
    calls++;
    lastForce = force;
    const result = SmsImportResult(processed: 1, failed: 0);
    onProgress?.call(result);
    return result;
  }
}

void main() {
  const summary = RetainedSmsFailureSummary(
    reasonCounts: {
      SmsFailureReason.unparsed: 3,
      SmsFailureReason.processingError: 2,
    },
  );

  testWidgets('shows content-free counts, reason buckets, and retention policy',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          retainedSmsFailureSummaryProvider.overrideWith(
            (ref) => Stream.value(summary),
          ),
        ],
        child: const MaterialApp(home: UnreadableSmsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text("Messages we couldn't read"), findsOneWidget);
    expect(find.text('5 messages could not be read'), findsOneWidget);
    expect(find.text('Could not match a transaction'), findsOneWidget);
    expect(find.text('Temporary processing issue'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('up to 30 days'), findsOneWidget);
    expect(find.textContaining('message text'), findsOneWidget);
    expect(find.textContaining('synthetic body'), findsNothing);
  });

  testWidgets('retry affordance opens the existing scan and starts it',
      (tester) async {
    final runner = _FakeImportRunner();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          retainedSmsFailureSummaryProvider.overrideWith(
            (ref) => Stream.value(summary),
          ),
          smsPermissionGateProvider.overrideWithValue(_FakePermissionGate()),
          smsHistoryImportRunnerProvider.overrideWith((ref) async => runner),
        ],
        child: const MaterialApp(home: UnreadableSmsScreen()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Retry by scanning the inbox'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Find transactions from SMS'), findsOneWidget);
    expect(runner.calls, 1);
    expect(runner.lastForce, isTrue);
    expect(find.text("You're up to date"), findsOneWidget);
  });
}
