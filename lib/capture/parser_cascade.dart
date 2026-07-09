import '../core/result.dart';
import '../data/models/normalized_transaction_record.dart';
import '../data/models/raw_sms.dart';
import 'generic_transaction_parser.dart';
import 'template_engine/template_matcher.dart';

/// Coordinates SMS parsing strategies from highest precision to fallback.
///
/// Phase 0 only wires template matching. Later phases can add an on-device
/// LLM or manual fallbacks while preserving this single parse contract.
/// No cloud parsing path may be added (ADR 0002).
class ParserCascade {
  const ParserCascade({
    required TemplateMatcher templateMatcher,
    GenericTransactionParser genericTransactionParser =
        const GenericTransactionParser(),
  })  : _templateMatcher = templateMatcher,
        _genericTransactionParser = genericTransactionParser;

  final TemplateMatcher _templateMatcher;
  final GenericTransactionParser _genericTransactionParser;

  /// Attempts to convert one raw SMS into a normalized transaction record.
  ///
  /// Expected parser misses return [Err] instead of throwing so callers can
  /// persist the raw SMS and retry with later parsers or user feedback.
  Future<Result<NormalizedTransactionRecord, ParseFailure>> parse(
    RawSms sms,
  ) async {
    final templateResult = _templateMatcher.match(sms);
    if (templateResult != null) {
      return Ok(templateResult);
    }

    final genericResult = _genericTransactionParser.parse(sms);
    if (genericResult != null) {
      return Ok(genericResult);
    }

    return const Err(ParseFailure.unparsed);
  }
}

/// Expected parse outcomes that callers can recover from.
enum ParseFailure {
  /// No configured parser recognized the SMS body.
  unparsed,
}
