import 'dart:math';
import 'dart:typed_data';

import '../data/db/database.dart';

/// Agglomerative cluster suggestion of similar merchant entities (T-137a).
class MerchantClusterSuggestion {
  const MerchantClusterSuggestion({
    required this.clusterId,
    required this.canonicalName,
    required this.memberMerchantIds,
    required this.similarityScore,
  });

  final String clusterId;
  final String canonicalName;
  final List<String> memberMerchantIds;
  final double similarityScore;
}

/// Computes agglomerative merchant clusters at >= 0.85 similarity.
/// Suggestions are stored or returned without auto-merging (AC: no merchant merged without user confirmation).
class MerchantClusterer {
  MerchantClusterer(this._db);

  final AppDatabase _db;
  static const clusterThreshold = 0.85;

  /// Runs agglomerative clustering over stored merchants with embeddings.
  Future<List<MerchantClusterSuggestion>> cluster() async {
    final merchants = await _db.select(_db.merchants).get();
    final withEmbeddings = merchants.where((m) => m.embedding != null).toList();

    if (withEmbeddings.length < 2) return const [];

    final suggestions = <MerchantClusterSuggestion>[];
    final visited = <String>{};

    for (var i = 0; i < withEmbeddings.length; i++) {
      final m1 = withEmbeddings[i];
      if (visited.contains(m1.id)) continue;

      final vec1 = Float32List.view(m1.embedding!.buffer);
      final clusterMembers = <String>[m1.id];
      var maxSim = 0.0;

      for (var j = i + 1; j < withEmbeddings.length; j++) {
        final m2 = withEmbeddings[j];
        if (visited.contains(m2.id)) continue;

        final vec2 = Float32List.view(m2.embedding!.buffer);
        final sim = _cosineSimilarity(vec1, vec2);
        if (sim >= clusterThreshold) {
          clusterMembers.add(m2.id);
          visited.add(m2.id);
          if (sim > maxSim) maxSim = sim;
        }
      }

      if (clusterMembers.length > 1) {
        visited.add(m1.id);
        suggestions.add(
          MerchantClusterSuggestion(
            clusterId: 'cluster_${m1.id}',
            canonicalName: m1.canonicalName,
            memberMerchantIds: clusterMembers,
            similarityScore: maxSim,
          ),
        );
      }
    }

    return suggestions;
  }

  static double _cosineSimilarity(Float32List a, Float32List b) {
    if (a.length != b.length || a.isEmpty) return 0.0;
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
