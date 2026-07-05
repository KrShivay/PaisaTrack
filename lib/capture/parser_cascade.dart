import '../core/result.dart';
import '../data/models/normalized_transaction_record.dart';
import '../data/models/raw_sms.dart';
import 'template_engine/template_matcher.dart';

class ParserCascade {
  const ParserCascade({
    required TemplateMatcher templateMatcher,
  }) : _templateMatcher = templateMatcher;

  final TemplateMatcher _templateMatcher;

  Future<Result<NormalizedTransactionRecord, ParseFailure>> parse(
    RawSms sms,
  ) async {
    final templateResult = _templateMatcher.match(sms);
    if (templateResult != null) {
      return Ok(templateResult);
    }

    return const Err(ParseFailure.unparsed);
  }
}

enum ParseFailure {
  unparsed,
}
