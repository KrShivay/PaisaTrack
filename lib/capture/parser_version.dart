/// Version of the parser/template contract used for raw SMS attempts.
///
/// Increment when parser or template behavior changes. This is intentionally
/// separate from the history-scan version: a scan can be complete while a
/// retained raw SMS becomes retryable after a parser upgrade.
const int smsParserVersion = 1;

/// Content-free reasons persisted for a failed raw SMS attempt.
abstract final class SmsFailureReason {
  static const unparsed = 'unparsed';
  static const processingError = 'processing_error';
}
