/// Utility for converting between integer paise (SQL storage) and double rupees (UI display).
class MoneyUtils {
  const MoneyUtils._();

  /// Converts rupee amount to integer paise (e.g. 150.75 -> 15075).
  static int toPaise(double rupees) => (rupees * 100).round();

  /// Converts integer paise to double rupees (e.g. 15075 -> 150.75).
  static double toRupees(int paise) => paise / 100.0;
}
