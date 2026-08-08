import '../../../data/db/database.dart' show Category, Transaction;

/// Returns up to 3 chips: [currentCat] first, then filled from [suggestedIds],
/// then from [allCategories] — never duplicates, never 'uncategorized'.
List<Category> chipCategories(
  Category currentCat,
  List<Category> allCategories,
  List<String> suggestedIds,
) {
  final chips = <Category>[currentCat];
  for (final sid in suggestedIds) {
    if (chips.length >= 3) break;
    if (sid != currentCat.id && sid != 'uncategorized') {
      final cat = allCategories.where((c) => c.id == sid).firstOrNull;
      if (cat != null) chips.add(cat);
    }
  }
  if (chips.length < 3) {
    for (final c in allCategories) {
      if (chips.length >= 3) break;
      if (c.id != currentCat.id &&
          c.id != 'uncategorized' &&
          !chips.any((sc) => sc.id == c.id)) {
        chips.add(c);
      }
    }
  }
  return chips;
}

/// Returns the user-facing reason this transaction is excluded from analytics,
/// or null if it is included.
String? exclusionReasonFor(Transaction txn) {
  if (txn.ownedTransferId != null) {
    return 'Self-transfer — excluded from totals to prevent double-counting.';
  }
  final raw = txn.merchantRaw?.toUpperCase();
  if (raw != null &&
      (raw.contains('CREDIT CARD') || raw.contains('CARD BILL'))) {
    return 'Credit card bill payment — excluded from totals'
        ' (card purchases are counted individually).';
  }
  if (raw != null && (raw.contains('ATM') || raw.contains('WITHDRAWAL'))) {
    return 'Cash withdrawal — moved to untracked cash'
        ' (excluded from category spending).';
  }
  if (txn.isAnalyticsExcluded) {
    return 'Excluded from analytics per settings.';
  }
  return null;
}

/// Formats [date] as "Jan 5, 2024 · 3:42 pm".
String formatDetailDate(DateTime date) {
  final local = date.toLocal();
  final h =
      local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
  final m = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour >= 12 ? 'pm' : 'am';
  return '${_shortMonth(local.month)} ${local.day}, ${local.year} · $h:$m $ampm';
}

String _shortMonth(int month) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ][month - 1];

/// Returns the combined parser label + optional confidence percentage,
/// e.g. "Template match · 91%".
String parserSourceLabel(String? parseSource, double? parseConfidence) {
  final label = switch (parseSource) {
    'template' => 'Template match',
    'generic' => 'Pattern match',
    'llm' => 'AI model',
    'manual' => 'Manual entry',
    final src? => src,
    null => 'Parsed',
  };
  if (parseConfidence == null) return label;
  final pct = '${(parseConfidence * 100).toStringAsFixed(0)}%';
  return '$label · $pct';
}
