import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/settings/ai_model_controller.dart';
import 'package:paisatrack/features/settings/ai_model_section.dart';
import 'package:paisatrack/intelligence/llm/llm_model_status.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

import '../../support/fake_llm_runtime.dart';

Future<void> pumpSection(
  WidgetTester tester,
  FakeLlmRuntime runtime, {
  FakeEmbedder? embedder,
}) async {
  tester.view.physicalSize = const Size(402, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        llmRuntimeProvider.overrideWithValue(runtime),
        embedderProvider.overrideWithValue(embedder ?? FakeEmbedder()),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AiModelSectionBody(isDark: false),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('download flow: confirm, progress, installed', (tester) async {
    final runtime = FakeLlmRuntime(fakeStatus());
    await pumpSection(tester, runtime);

    expect(find.text('Qwen3 0.6B'), findsOneWidget);
    expect(find.textContaining('2.4 GB · Not downloaded'), findsOneWidget);
    expect(find.text(aiModelPrivacyNote), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai_model_download')));
    await tester.pumpAndSettle();
    // Confirmation names the size, the source and recommends Wi-Fi.
    expect(
      find.textContaining('2.4 GB once from Hugging Face'),
      findsOneWidget,
    );
    expect(find.textContaining('Wi-Fi'), findsOneWidget);
    expect(runtime.downloadCalls, 0);

    await tester.tap(find.byKey(const ValueKey('ai_model_confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(runtime.downloadCalls, 1);
    expect(find.byKey(const ValueKey('ai_model_progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_model_cancel')), findsOneWidget);

    // Native progress is picked up by the 500 ms poll.
    runtime.status = fakeStatus(
      state: LlmDownloadState.downloading,
      downloaded: fakeModelSize ~/ 2,
    );
    await tester.pump(AiModelController.pollInterval);
    await tester.pump();
    expect(find.textContaining('Downloading 50%'), findsOneWidget);
    expect(find.textContaining('1.2 GB of 2.4 GB'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('ai_model_progress')),
    );
    expect(bar.value, closeTo(0.5, 0.001));

    runtime.finish(
      const LlmOperationResult.ok(),
      fakeStatus(installed: true, state: LlmDownloadState.installed),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Installed'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_model_delete')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_model_progress')), findsNothing);
  });

  testWidgets('verifying phase shows no cancel', (tester) async {
    final runtime = FakeLlmRuntime(
      fakeStatus(state: LlmDownloadState.verifying, downloaded: fakeModelSize),
    );
    await pumpSection(tester, runtime);

    expect(find.textContaining('Verifying'), findsWidgets);
    expect(find.byKey(const ValueKey('ai_model_cancel')), findsNothing);
  });

  testWidgets('double start joins the running download; cancel resets',
      (tester) async {
    final runtime = FakeLlmRuntime(fakeStatus());
    await pumpSection(tester, runtime);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AiModelSectionBody)),
    );
    final controller = container.read(aiModelControllerProvider.notifier);

    final first = controller.startDownload();
    final second = controller.startDownload();
    await tester.pump();
    expect(identical(first, second), isTrue);
    expect(runtime.downloadCalls, 1);

    await tester.tap(find.byKey(const ValueKey('ai_model_cancel')));
    await tester.pump();
    await tester.pump();
    expect(runtime.cancelCalls, 1);
    expect(find.byKey(const ValueKey('ai_model_download')), findsOneWidget);
    expect(find.textContaining('Download cancelled'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai_model_progress')), findsNothing);
  });

  testWidgets('download failure shows friendly storage copy', (tester) async {
    final runtime = FakeLlmRuntime(fakeStatus());
    await pumpSection(tester, runtime);

    await tester.tap(find.byKey(const ValueKey('ai_model_download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_model_confirm')));
    await tester.pump();
    runtime.finish(
      const LlmOperationResult(success: false, code: 'insufficient_storage'),
      fakeStatus(),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text(aiSupportReasonCopy(LlmSupportReason.insufficientStorage)),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ai_model_download')), findsOneWidget);
  });

  testWidgets('delete asks for confirmation then removes the model',
      (tester) async {
    final runtime = FakeLlmRuntime(
      fakeStatus(installed: true, state: LlmDownloadState.installed),
    );
    await pumpSection(tester, runtime);

    await tester.tap(find.byKey(const ValueKey('ai_model_delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete AI model?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(runtime.deleteCalls, 0);

    await tester.tap(find.byKey(const ValueKey('ai_model_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_model_confirm')));
    await tester.pumpAndSettle();
    expect(runtime.deleteCalls, 1);
    expect(find.byKey(const ValueKey('ai_model_download')), findsOneWidget);
  });

  group('unsupported devices', () {
    const cases = {
      LlmSupportReason.lowRamDevice: 'low-memory',
      LlmSupportReason.insufficientTotalMemory: 'enough memory',
      LlmSupportReason.insufficientStorage: 'free storage',
      LlmSupportReason.backendUnavailable: "can't run",
    };
    for (final entry in cases.entries) {
      testWidgets('${entry.key.name} explains why', (tester) async {
        final runtime = FakeLlmRuntime(
          fakeStatus(downloadSupported: false, reason: entry.key),
        );
        await pumpSection(tester, runtime);

        expect(
          find.textContaining('Not supported on this device'),
          findsOneWidget,
        );
        expect(find.textContaining(entry.value), findsOneWidget);
        expect(find.byKey(const ValueKey('ai_model_download')), findsNothing);
      });
    }
  });

  testWidgets('embedder row downloads and deletes after confirmation',
      (tester) async {
    final embedder = FakeEmbedder();
    await pumpSection(
      tester,
      FakeLlmRuntime(fakeStatus()),
      embedder: embedder,
    );

    expect(find.text('Merchant matching model'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('embedder_download')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_model_confirm')));
    await tester.pumpAndSettle();
    expect(embedder.downloads, 1);
    expect(find.byKey(const ValueKey('embedder_delete')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('embedder_delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai_model_confirm')));
    await tester.pumpAndSettle();
    expect(embedder.installed, isFalse);
    expect(find.byKey(const ValueKey('embedder_download')), findsOneWidget);
  });

  test('operation codes map to friendly copy', () {
    expect(aiDownloadErrorCopy('low_ram_device'), contains('low-memory'));
    expect(aiDownloadErrorCopy('download_failure'), contains('connection'));
    expect(aiDownloadErrorCopy('timeout'), contains('connection'));
    expect(aiDownloadErrorCopy('???'), contains('try again'));
    expect(formatModelSize(2400000000), '2.4 GB');
    expect(formatModelSize(6120274), '6.1 MB');
  });
}
