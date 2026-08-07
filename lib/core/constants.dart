/// Central feature flags and behavioral thresholds.
///
/// Defaults should preserve local-first, privacy-first behavior unless a task
/// and ADR explicitly opt into a broader surface.
class AppConstants {
  const AppConstants._();

  /// Persisted defaults for the developer-tunable feature flag table.
  ///
  /// Keep these values in sync with the typed accessors below. The database
  /// stores strings so the table remains simple and forward-compatible.
  static const featureFlagDefaults = <String, Object>{
    'enable_local_llm': enableLocalLlm,
    'enable_narrative_insights': enableNarrativeInsights,
    'silent_confidence_threshold': silentConfidenceThreshold,
    'ask_confidence_threshold': askConfidenceThreshold,
    'ask_now_daily_budget': askNowDailyBudget,
    'ask_amount_threshold': askAmountThreshold,
    'ask_merchant_txn_count': askMerchantTxnCount,
    'raw_sms_retention_days': rawSmsRetentionDays,
    'sms_history_import_page_size': smsHistoryImportPageSize,
    'duplicate_pair_window_minutes': duplicatePairWindowMinutes,
    'merchant_auto_link_threshold': merchantAutoLinkThreshold,
    'merchant_cluster_suggestion_threshold': merchantClusterSuggestionThreshold,
    'llm_category_suggestion_cap': llmCategorySuggestionCap,
    'refund_auto_link_threshold': refundAutoLinkThreshold,
    'auth_settle_link_threshold': authSettleLinkThreshold,
    'expected_debit_fulfilment_threshold': expectedDebitFulfilmentThreshold,
    'anomaly_alert_sigma': anomalyAlertSigma,
    'anomaly_alert_min_periods': anomalyAlertMinPeriods,
    'anomaly_alert_floor_amount': anomalyAlertFloorAmount,
  };

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

  /// Cosine similarity threshold for automatic merchant entity auto-linking (§10).
  static const merchantAutoLinkThreshold = 0.92;

  /// Cosine similarity threshold for merchant cluster suggestions (§10).
  static const merchantClusterSuggestionThreshold = 0.85;

  /// Maximum category confidence threshold cap for LLM suggestions (§10).
  ///
  /// Represents the upper bound confidence score (0.0 to 1.0) LLM category
  /// suggestions can contribute; values above this cap fall through to seed maps.
  static const llmCategorySuggestionCap = 0.70;

  /// Confidence threshold for refund auto-linking (§10).
  static const refundAutoLinkThreshold = 0.90;

  /// Similarity/confidence threshold for linking authorization to settlement (§10).
  static const authSettleLinkThreshold = 0.85;

  /// Threshold for expected-to-debit event fulfilment (§10).
  static const expectedDebitFulfilmentThreshold = 0.85;

  /// Standard deviation multiplier for anomaly detection (§10).
  static const anomalyAlertSigma = 2.5;

  /// Minimum historical periods required before raising anomaly alerts (§10).
  static const anomalyAlertMinPeriods = 8;

  /// Absolute amount floor (in currency units) required to trigger anomaly alert (§10).
  static const anomalyAlertFloorAmount = 500.0;

  // ── Categorizer confidence constants (T-155a) ──

  /// Seed-map category confidence (categorizer ladder step 3).
  static const seedConfidence = 0.8;

  /// Fallback ('other') confidence when no ladder step matches.
  static const categorizerFallbackConfidence = 0.3;

  // ── Correlation confidence constants (T-155a) ──

  /// UTR/Ref exact-match correlation confidence.
  static const refMatchConfidence = 0.99;

  /// Auth→settlement correlation confidence.
  static const authSettleMatchConfidence = 0.95;

  /// Reversal amount-match correlation confidence.
  static const reversalMatchConfidence = 0.90;

  /// Echo (duplicate) time+amount match confidence.
  static const echoMatchConfidence = 0.98;

  /// Transfer-leg (owned sources) match confidence.
  static const transferLegMatchConfidence = 0.92;

  /// Full refund counterparty match confidence.
  static const refundFullMatchConfidence = 0.95;

  /// Partial refund counterparty match confidence.
  static const refundPartialMatchConfidence = 0.91;

  // ── Template trust confidence constants (T-155a) ──

  /// Promoted public-template parse confidence (ADR 0005).
  static const promotedTemplateConfidence = 0.97;

  /// Default (unpromoted) public-template parse confidence.
  static const defaultTemplateConfidence = 0.85;

  // ── Parser parse-confidence constants (T-155a) ──

  /// LLM field-locator parse confidence.
  static const llmParseConfidence = 0.75;

  /// Generic parser confidence when amount is unambiguous and merchant is present.
  static const genericHighParseConfidence = 0.6;

  /// Generic parser confidence when amount is ambiguous or merchant is absent.
  static const genericLowParseConfidence = 0.5;
}
