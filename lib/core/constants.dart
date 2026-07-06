/// Central feature flags and behavioral thresholds.
///
/// Defaults should preserve local-first, privacy-first behavior unless a task
/// and ADR explicitly opt into a broader surface.
class AppConstants {
  const AppConstants._();

  /// Enables on-device LLM parsing once that implementation exists.
  /// All LLM inference is local-only; no cloud path exists (ADR 0002).
  static const enableLocalLlm = false;

  /// Enables generated narrative insights (on-device model or deterministic
  /// engine only — ADR 0002) once privacy rules are implemented.
  static const enableNarrativeInsights = false;

  /// Confidence at or above this value can be accepted without interrupting.
  static const silentConfidenceThreshold = 0.9;

  /// Confidence at or above this value can ask the user for confirmation.
  static const askConfidenceThreshold = 0.6;

  /// Maximum number of active clarification prompts per day.
  static const askNowDailyBudget = 2;

  /// Number of days raw SMS bodies may remain before purge.
  static const rawSmsRetentionDays = 30;

  /// Months of inbox history read on first permission grant (T-023 backfill).
  static const smsBackfillMonths = 3;

  /// Historical messages processed per yield so backfill never blocks the UI.
  static const smsBackfillChunkSize = 25;

  /// Max minutes apart two SMS may arrive and still be treated as one
  /// paired bank+wallet/UPI notification for duplicate suppression (T-025).
  static const duplicatePairWindowMinutes = 10;
}
