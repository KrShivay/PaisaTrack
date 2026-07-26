import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sms_permission.dart';

/// Supplies the SMS permission gate. Tests override this with a fake gate.
final smsPermissionGateProvider = Provider<SmsPermissionGate>((ref) {
  return const PlatformSmsPermissionGate();
});

/// Set when the user chooses to continue into the app without granting SMS
/// access. It lets onboarding hand off to the main shell (where manual entry,
/// Settings, and a persistent permission banner live) instead of trapping a
/// user who declined. Granting permission later makes this irrelevant, and the
/// value resets on a cold start so first-run onboarding still shows.
final continueWithoutSmsProvider = StateProvider<bool>((ref) => false);

/// Exposes the current SMS permission status and a way to request it.
///
/// `build` reads the status without prompting so onboarding can render the
/// correct state on first frame; [request] triggers the system prompt and
/// publishes the resulting status.
final smsPermissionControllerProvider =
    AsyncNotifierProvider<SmsPermissionController, SmsPermissionStatus>(
  SmsPermissionController.new,
);

class SmsPermissionController extends AsyncNotifier<SmsPermissionStatus> {
  @override
  Future<SmsPermissionStatus> build() {
    return ref.watch(smsPermissionGateProvider).status();
  }

  /// Requests the SMS permissions and updates state with the outcome.
  Future<void> request() async {
    final gate = ref.read(smsPermissionGateProvider);
    state = const AsyncLoading<SmsPermissionStatus>().copyWithPrevious(state);
    state = await AsyncValue.guard(gate.request);
  }

  /// Opens the Android app settings so the user can grant permanently-denied
  /// permissions, then waits for the outcome on app resume.
  Future<void> openSettings() async {
    final gate = ref.read(smsPermissionGateProvider);
    await gate.openAppSettings();
  }

  /// Re-reads the current permission status (e.g. after returning from
  /// system settings) and publishes the result.
  Future<void> recheckStatus() async {
    final gate = ref.read(smsPermissionGateProvider);
    state = await AsyncValue.guard(gate.status);
  }
}
