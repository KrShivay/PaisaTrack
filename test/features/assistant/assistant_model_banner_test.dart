import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/assistant/assistant_screen.dart';
import 'package:paisatrack/intelligence/llm/llm_model_status.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

import 'package:paisatrack/capture/permissions/sms_permission.dart';
import 'package:paisatrack/capture/permissions/sms_permission_provider.dart';
import 'package:paisatrack/features/settings/app_settings.dart';

import '../../support/fake_llm_runtime.dart';
import '../../support/fake_sms_permission_gate.dart';

class _Settings extends AppSettingsController {
  @override
  Future<AppSettings> build() async => const AppSettings();
}

Future<void> pumpAssistant(WidgetTester tester, FakeLlmRuntime runtime) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        llmRuntimeProvider.overrideWithValue(runtime),
        embedderProvider.overrideWithValue(FakeEmbedder()),
        appSettingsControllerProvider.overrideWith(_Settings.new),
        smsPermissionGateProvider.overrideWithValue(
          FakeSmsPermissionGate(initialStatus: SmsPermissionStatus.granted),
        ),
      ],
      child: const MaterialApp(home: AssistantScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('offers Download AI model when the model is missing',
      (tester) async {
    await pumpAssistant(tester, FakeLlmRuntime(fakeStatus()));

    expect(
      find.byKey(const ValueKey('assistant_model_banner')),
      findsOneWidget,
    );
    expect(find.text('Download AI model'), findsOneWidget);
    expect(find.textContaining('keyword search'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('assistant_download_model')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Lands on Settings with the On-device AI section.
    expect(find.text('Settings'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('ON-DEVICE AI'), 200);
    expect(find.text('ON-DEVICE AI'), findsOneWidget);
  });

  testWidgets('no banner when installed or unsupported', (tester) async {
    await pumpAssistant(
      tester,
      FakeLlmRuntime(
        fakeStatus(installed: true, state: LlmDownloadState.installed),
      ),
    );
    expect(find.byKey(const ValueKey('assistant_model_banner')), findsNothing);
  });

  testWidgets('no download action on unsupported devices', (tester) async {
    await pumpAssistant(
      tester,
      FakeLlmRuntime(
        fakeStatus(
          downloadSupported: false,
          reason: LlmSupportReason.lowRamDevice,
        ),
      ),
    );
    expect(find.text('Download AI model'), findsNothing);
  });
}
