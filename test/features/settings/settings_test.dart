import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:paisatrack/core/crypto/database_cipher.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/db/database_provider.dart';
import 'package:paisatrack/features/settings/app_data_reset_service.dart';
import 'package:paisatrack/features/settings/app_settings.dart';
import 'package:paisatrack/features/settings/settings_screen.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';

class _FakePassphraseProvider implements DatabasePassphraseProvider {
  var cleared = false;

  @override
  Future<DatabasePassphrase> getPassphrase() async {
    return const DatabasePassphrase('test-passphrase');
  }

  @override
  Future<void> clearStoredPassphrase() async {
    cleared = true;
  }
}

class _FakeLlmRuntime extends NoopLlmRuntime {
  var downloaded = false;
  var deleted = false;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> isModelAvailable() async => downloaded && !deleted;

  @override
  Future<bool> downloadModel() async {
    downloaded = true;
    return true;
  }

  @override
  Future<bool> deleteModel() async {
    deleted = true;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings store round-trips theme and ask budget', () async {
    final directory = await Directory.systemTemp.createTemp('settings_test_');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppSettingsStore(directory);

    await store.write(
      const AppSettings(
        themeChoice: AppThemeChoice.system,
        askDailyBudget: 4,
      ),
    );

    final settings = await store.read();

    expect(settings.themeChoice, AppThemeChoice.system);
    expect(settings.askDailyBudget, 4);
  });

  testWidgets('settings screen changes theme and ask budget', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // testWidgets runs under FakeAsync: real file IO futures never complete
    // there (this test originally hung the whole suite on its first await).
    // Create the temp dir synchronously and push the store's real disk reads
    // through tester.runAsync, which runs the real event loop.
    final directory = Directory.systemTemp.createTempSync('settings_ui_');
    final llmRuntime = _FakeLlmRuntime();
    addTearDown(() => directory.deleteSync(recursive: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsDirectoryProvider.overrideWith((ref) async => directory),
          llmRuntimeProvider.overrideWithValue(llmRuntime),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
      listen: false,
    );

    // The store's real file IO starts inside the fake zone, so its `.then`
    // continuations queue as fake-zone microtasks. Awaiting the provider
    // future inside a single runAsync deadlocks (the fake queue only flushes
    // after runAsync returns). Instead, alternate: a runAsync slice lets the
    // real event loop deliver dart:io completions, then pump() runs the
    // fake-zone microtasks they queued. Bounded so regressions fail, not hang.
    Future<void> pumpRealIo({bool Function()? done}) async {
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
        if (done != null && done()) return;
      }
    }

    // Let the controller's initial settings read finish.
    await pumpRealIo(
      done: () => container.read(appSettingsControllerProvider) is AsyncData,
    );
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Light'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 100));

    // The controller updates state before persisting; flush the pending
    // real-IO writes so they don't leak past the end of the test.
    await pumpRealIo();
    final settings = container.read(appSettingsControllerProvider).value!;

    expect(settings.themeChoice, AppThemeChoice.light);
    expect(settings.askDailyBudget, greaterThan(2));
    await tester.scrollUntilVisible(find.text('Download'), 300);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(llmRuntime.downloaded, isTrue);
    expect(find.byTooltip('Delete AI model'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Developer options'), 300);
    expect(find.text('Developer options'), findsOneWidget);
    await tester.tap(find.text('Developer options'));
    await tester.pumpAndSettle();
    expect(find.text('Local LLM parsing'), findsOneWidget);
    expect(find.text('Model metrics'), findsOneWidget);
    expect(find.text('Delete everything'), findsOneWidget);
  });

  test(
      'delete everything clears db files, key, settings, and reseeds categories',
      () async {
    final databaseDirectory =
        await Directory.systemTemp.createTemp('reset_db_test_');
    final settingsDirectory =
        await Directory.systemTemp.createTemp('reset_settings_test_');
    addTearDown(() => databaseDirectory.delete(recursive: true));
    addTearDown(() => settingsDirectory.delete(recursive: true));

    for (final suffix in const ['', '-wal', '-shm']) {
      await File(p.join(databaseDirectory.path, '$appDatabaseFileName$suffix'))
          .writeAsString('data');
    }
    await AppSettingsStore(settingsDirectory).write(
      const AppSettings(
        themeChoice: AppThemeChoice.light,
        askDailyBudget: 5,
      ),
    );

    final passphraseProvider = _FakePassphraseProvider();
    final opened = <AppDatabase>[];
    final container = ProviderContainer(
      overrides: [
        databaseDirectoryProvider
            .overrideWith((ref) async => databaseDirectory),
        settingsDirectoryProvider
            .overrideWith((ref) async => settingsDirectory),
        databasePassphraseProvider.overrideWithValue(passphraseProvider),
        appDatabaseProvider.overrideWith((ref) async {
          final database = AppDatabase(NativeDatabase.memory());
          opened.add(database);
          return database;
        }),
      ],
    );
    addTearDown(container.dispose);

    final result =
        await container.read(appDataResetServiceProvider).deleteEverything();

    expect(result.deletedFiles, 3);
    expect(result.categoryCount, greaterThan(0));
    expect(passphraseProvider.cleared, isTrue);
    expect(
      await AppSettingsStore(settingsDirectory).read(),
      isA<AppSettings>()
          .having((s) => s.themeChoice, 'themeChoice', AppThemeChoice.dark)
          .having((s) => s.askDailyBudget, 'askDailyBudget', 2),
    );
    for (final suffix in const ['', '-wal', '-shm']) {
      expect(
        File(p.join(databaseDirectory.path, '$appDatabaseFileName$suffix'))
            .existsSync(),
        isFalse,
      );
    }

    for (final database in opened) {
      try {
        await database.close();
      } on StateError {
        // Some entries are intentionally closed by the reset service.
      }
    }
  });
}
