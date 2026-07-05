/// Central feature flags and behavioral thresholds.
///
/// Defaults should preserve local-first, privacy-first behavior unless a task
/// and ADR explicitly opt into a broader surface.
class AppConstants {
  const AppConstants._();

  /// Enables on-device LLM parsing once that implementation exists.
  static const enableLocalLlm = false;

  /// Enables network fallback only after anonymization and explicit opt-in.
  static const enableCloudFallback = false;

  /// Enables generated narrative insights once privacy rules are implemented.
  static const enableNarrativeInsights = false;

  /// Confidence at or above this value can be accepted without interrupting.
  static const silentConfidenceThreshold = 0.9;

  /// Confidence at or above this value can ask the user for confirmation.
  static const askConfidenceThreshold = 0.6;

  /// Maximum number of active clarification prompts per day.
  static const askNowDailyBudget = 2;

  /// Number of days raw SMS bodies may remain before purge.
  static const rawSmsRetentionDays = 30;
}
