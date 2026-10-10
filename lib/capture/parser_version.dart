/// Version of the parser/classifier/template contract used for raw SMS attempts.
///
/// Increment when parser or template behavior changes. This is intentionally
/// separate from the history-scan version: a scan can be complete while a
/// retained raw SMS becomes retryable after a parser upgrade.
const int smsParserVersion = 3;

/// Content-free reasons persisted for a failed raw SMS attempt.
abstract final class SmsFailureReason {
  static const unparsed = 'unparsed';
  static const processingError = 'processing_error';
}

/// Returns whether retained raw SMS evidence is terminal for the current
/// parser contract. Existing transactions and user dispositions are checked
/// before this policy by the shared identity-claim validator.
bool isRawSmsAttemptTerminal({
  required bool processed,
  required int? parserVersion,
  required String? failureReason,
  required int currentParserVersion,
}) {
  if (parserVersion == null) return processed;
  if (parserVersion < currentParserVersion) return false;
  if (failureReason == SmsFailureReason.processingError &&
      parserVersion == currentParserVersion) {
    return false;
  }
  return processed || parserVersion >= currentParserVersion;
}
