/// Central feature flags and behavioral thresholds.
///
/// Defaults should preserve local-first, privacy-first behavior unless a task
/// and ADR explicitly opt into a broader surface.
class AppConstants {
  const AppConstants._();

  /// Enables on-device LLM parsing once that implementation exists.
  /// All LLM inference is local-only; no cloud path exists (ADR 0002).
  static const enableLocalLlm = true;

  /// Enables generated narrative insights (on-device model or deterministic
  /// engine only — ADR 0002) once privacy rules are implemented.
  static const enableNarrativeInsights = true;

  /// Confidence at or above this value can be accepted without interrupting.
  static const silentConfidenceThreshold = 0.9;

  /// Confidence at or above this value can ask the user for confirmation.
  static const askConfidenceThreshold = 0.6;

  /// Maximum number of active clarification prompts per day.
  static const askNowDailyBudget = 2;

  /// Amount at or above which a mid-confidence transaction is worth asking
  /// about (PLAN §7.5).
  static const askAmountThreshold = 500.0;

  /// Prior transactions with the same merchant at or above which asking is
  /// worthwhile (the merchant is familiar enough to teach a rule, PLAN §7.5).
  static const askMerchantTxnCount = 3;

  /// Number of days raw SMS bodies may remain before purge.
  static const rawSmsRetentionDays = 30;

  /// Raw inbox rows requested per page during full-history SMS import.
  ///
  /// Paging bounds platform-channel payloads and yields between pages while
  /// still scanning the entire inbox; it is not a history or message cap.
  static const smsHistoryImportPageSize = 200;

  /// Max minutes apart two SMS may arrive and still be treated as one
  /// paired bank+wallet/UPI notification for duplicate suppression (T-025).
  static const duplicatePairWindowMinutes = 10;
}
