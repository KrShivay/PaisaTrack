/// Currency evidence carried from the source message. A null code is unknown;
/// a symbol can still preserve/query an ambiguous source marker such as `$`.
class SourceCurrency {
  const SourceCurrency({this.code, this.symbol});

  final String? code;
  final String? symbol;

  String get bucketKey => code == null
      ? (symbol == null ? 'unknown' : 'symbol:$symbol')
      : 'code:$code';

  bool sameBucket(SourceCurrency other) {
    if (code != null || other.code != null) {
      return code != null && code == other.code;
    }
    return symbol == other.symbol;
  }

  String get label =>
      code ??
      (symbol == null ? 'Currency unknown' : '$symbol (currency unknown)');

  static SourceCurrency? fromToken(String? token) {
    if (token == null || token.trim().isEmpty) return null;
    final value = token.trim().toUpperCase();
    if (value == 'INR' || value == 'RS' || value == 'RS.' || value == '₹') {
      return const SourceCurrency(code: 'INR', symbol: '₹');
    }
    if (value == 'USD' || value == 'US\$') {
      return const SourceCurrency(code: 'USD', symbol: '\$');
    }
    if (value == '\$') return const SourceCurrency(symbol: '\$');
    return null;
  }
}
