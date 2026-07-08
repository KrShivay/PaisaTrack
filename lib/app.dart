import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture/permissions/sms_permission.dart';
import 'capture/permissions/sms_permission_provider.dart';
import 'capture/sms_backfill.dart';
import 'capture/sms_ingestion.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/onboarding_screen.dart';
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
    // Activates the one-time historical inbox backfill (T-023) once the
    // permission-granted, database-ready preconditions hold.
    ref.watch(smsBackfillProvider);

    final permission = ref.watch(smsPermissionControllerProvider);
    // Denied/unknown/error states stay on onboarding, which explains the
    // degraded (manual-only) state; only a granted permission unlocks the
    // dashboard/transactions/dev shell.
    final isGranted = permission.valueOrNull == SmsPermissionStatus.granted;
    final settings = ref.watch(appSettingsControllerProvider);

    return MaterialApp(
      title: 'PaisaTrack',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.valueOrNull?.themeChoice.themeMode ?? ThemeMode.dark,
      home: isGranted ? const HomeShell() : const OnboardingScreen(),
    );
  }
}
