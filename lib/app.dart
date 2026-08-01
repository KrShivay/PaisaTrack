import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture/permissions/sms_permission.dart';
import 'capture/permissions/sms_permission_lifecycle.dart';
import 'capture/permissions/sms_permission_provider.dart';
import 'capture/sms_backfill.dart';
import 'capture/sms_ingestion.dart';
import 'core/crypto/database_cipher.dart';
import 'core/theme/app_theme.dart';
import 'data/db/database_provider.dart';
import 'features/home/home_shell.dart';
import 'features/notifications/ask_now_notifications.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/recovery/database_error_screen.dart';
import 'features/recovery/key_loss_screen.dart';
import 'features/settings/app_settings.dart';

/// Root widget for the PaisaTrack Flutter application.
///
/// App-wide providers, navigation, and theme configuration should be attached
/// here so tests can boot the same shell that production uses. The widget
/// assumes an enclosing `ProviderScope` (installed in `main`).
class PaisaTrackApp extends ConsumerWidget {
  const PaisaTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(smsCaptureBootstrapProvider);
    ref.watch(smsIncrementalCatchUpBootstrapProvider);
    // Activates the one-time historical inbox backfill (T-023) once the
    // permission-granted, database-ready preconditions hold.
    ref.watch(smsBackfillProvider);
    ref.watch(askNowNotificationControllerProvider);

    final dbAsync = ref.watch(appDatabaseProvider);
    final permission = ref.watch(smsPermissionControllerProvider);
    final continueWithoutSms = ref.watch(continueWithoutSmsProvider);
    final settings = ref.watch(appSettingsControllerProvider);

    final Widget homeWidget = switch (dbAsync) {
      AsyncData() => switch (permission) {
          AsyncData(:final value) when value == SmsPermissionStatus.granted =>
            const HomeShell(),
          AsyncLoading() => const _StartupScreen(),
          _ when continueWithoutSms => const HomeShell(),
          _ => const OnboardingScreen(),
        },
      AsyncError(:final error) when error is DatabaseKeyLostError =>
        const KeyLossScreen(),
      AsyncError(:final error) => DatabaseErrorScreen(error: error),
      _ => const _StartupScreen(),
    };

    return SmsPermissionLifecycleRefresher(
      child: MaterialApp(
        title: 'PaisaTrack',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode:
            settings.valueOrNull?.themeChoice.themeMode ?? ThemeMode.dark,
        home: homeWidget,
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your local data…'),
          ],
        ),
      ),
    );
  }
}
