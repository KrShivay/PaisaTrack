class AppConstants {
  const AppConstants._();

  static const enableLocalLlm = false;
  static const enableCloudFallback = false;
  static const enableNarrativeInsights = false;

  static const silentConfidenceThreshold = 0.9;
  static const askConfidenceThreshold = 0.6;
  static const askNowDailyBudget = 2;
  static const rawSmsRetentionDays = 30;
}
