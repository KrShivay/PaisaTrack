import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/features/settings/app_settings.dart';

void main() {
  test('onboarding completion uses the new persisted JSON key', () {
    const settings = AppSettings(onboardingCompleted: true);

    expect(settings.toJson()['onboarding_completed'], isTrue);
    expect(settings.toJson(), isNot(contains('continue_without_sms')));
    expect(AppSettings.fromJson(settings.toJson()).onboardingCompleted, isTrue);
  });

  test('legacy continue-without-SMS JSON remains readable', () {
    final settings = AppSettings.fromJson({'continue_without_sms': true});

    expect(settings.onboardingCompleted, isTrue);
    expect(
      AppSettings.fromJson({
        'onboarding_completed': false,
        'continue_without_sms': true,
      }).onboardingCompleted,
      isFalse,
    );
  });

  test('settings store persists onboarding completion', () async {
    final directory = await Directory.systemTemp.createTemp('app-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppSettingsStore(directory);

    await store.write(const AppSettings(onboardingCompleted: true));

    expect((await store.read()).onboardingCompleted, isTrue);
  });

  test('continue action writes onboarding completion through the controller',
      () async {
    final directory = await Directory.systemTemp.createTemp('app-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AppSettingsStore(directory);
    final container = ProviderContainer(
      overrides: [
        appSettingsStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(appSettingsControllerProvider.notifier)
        .setOnboardingCompleted(true);

    expect((await store.read()).onboardingCompleted, isTrue);
  });
}
