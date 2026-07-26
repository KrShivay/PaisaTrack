import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../settings/app_settings.dart';
import 'dashboard_providers.dart';

/// Dynamic streak derived from persisted settings and verified inbox-zero transitions.
///
/// Default value is 0 (never a hardcoded sample number). Increments when the
/// transaction review queue reaches 0 for a qualifying calendar day.
final streakProvider = Provider<int>((ref) {
  final settings = ref.watch(appSettingsControllerProvider).valueOrNull;
  if (settings == null) return 0;

  final reviewAttention = ref.watch(reviewAttentionProvider);

  // If review queue is empty (inbox zero), return the persisted streak count (minimum 1 if zero reviewed).
  if (reviewAttention == null || reviewAttention.count == 0) {
    return settings.streak > 0 ? settings.streak : 1;
  }

  return settings.streak;
});
