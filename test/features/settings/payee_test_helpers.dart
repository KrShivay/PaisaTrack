import 'package:drift/native.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/payee_label_repository.dart';
import 'package:paisatrack/enrichment/merchant_clusterer.dart';

class FakePayeeLabelRepository extends PayeeLabelRepository {
  FakePayeeLabelRepository(
    super.database, {
    required this.items,
    this.suggestions = const [],
  });

  final List<PayeeIdentity> items;
  final List<MerchantClusterSuggestion> suggestions;

  @override
  Future<PayeeIdentityPage> loadPage(PayeeIdentityQuery query) async {
    final search = query.search.trim().toLowerCase();
    final filtered = items.where((item) {
      if (query.unlabeledOnly && item.userLabel?.trim().isNotEmpty == true) {
        return false;
      }
      if (search.isEmpty) return true;
      return item.displayName.toLowerCase().contains(search) ||
          item.userLabel?.toLowerCase().contains(search) == true ||
          item.aliases.any((alias) => alias.toLowerCase().contains(search));
    }).toList(growable: false);
    final after = query.after;
    final start = after == null
        ? 0
        : filtered.indexWhere(
              (item) =>
                  item.displayName == after.displayName &&
                  item.key == after.identityKey,
            ) +
            1;
    final visible = filtered.skip(start).take(query.limit + 1).toList();
    return PayeeIdentityPage(
      items: visible.take(query.limit).toList(growable: false),
      hasMore: visible.length > query.limit,
    );
  }

  @override
  Future<List<MerchantClusterSuggestion>> duplicateSuggestions() async =>
      suggestions;
}

AppDatabase newPayeeTestDatabase() => AppDatabase(NativeDatabase.memory());
