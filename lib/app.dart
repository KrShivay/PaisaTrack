import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture/permissions/sms_permission.dart';
import 'capture/permissions/sms_permission_lifecycle.dart';
import 'capture/permissions/sms_permission_provider.dart';
import 'capture/sms_backfill.dart';
import 'capture/sms_ingestion.dart';
import 'core/crypto/database_cipher.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/bloom/bloom_undo_toast.dart';
import 'data/db/database_provider.dart';
import 'features/home/home_shell.dart';
import 'features/notifications/ask_now_notifications.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/recovery/database_error_screen.dart';
import 'features/recovery/key_loss_screen.dart';
import 'features/settings/app_settings.dart';
import 'intelligence/derived_reads_service.dart';

enum AppStartupDestination { loading, home, onboarding }

final BloomUndoToastRouteObserver _undoToastRouteObserver =
    BloomUndoToastRouteObserver();

AppStartupDestination appStartupDestination({
  required AsyncValue<SmsPermissionStatus> permission,
  required AsyncValue<AppSettings> settings,
}) {
  // Only a first load with no value yet waits; a refresh keeps the current
  // route mounted, and a load error falls through rather than spinning.
  bool firstLoad(AsyncValue<Object?> value) =>
      value.isLoading && !value.hasValue && !value.hasError;
  if (firstLoad(permission) || firstLoad(settings)) {
    return AppStartupDestination.loading;
  }
  if (permission.valueOrNull == SmsPermissionStatus.granted ||
      settings.valueOrNull?.onboardingCompleted == true) {
    return AppStartupDestination.home;
  }
  return AppStartupDestination.onboarding;
}

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
    ref.watch(derivedReadsServiceProvider);

    final dbAsync = ref.watch(appDatabaseProvider);
    final permission = ref.watch(smsPermissionControllerProvider);
    final settings = ref.watch(appSettingsControllerProvider);

    final Widget homeWidget = switch (dbAsync) {
      AsyncData() => switch (
            appStartupDestination(permission: permission, settings: settings)) {
          AppStartupDestination.loading => const _StartupScreen(),
          AppStartupDestination.home => const HomeShell(),
          AppStartupDestination.onboarding => const OnboardingScreen(),
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
        navigatorObservers: [_undoToastRouteObserver],
        builder: (context, child) => buildBloomUndoToastAppBuilder(
          context,
          child,
          routeObserver: _undoToastRouteObserver,
          homeNavigationVisible: homeWidget is HomeShell,
        ),
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
