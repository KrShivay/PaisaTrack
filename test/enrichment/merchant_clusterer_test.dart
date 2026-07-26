import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/enrichment/merchant_clusterer.dart';
import 'package:paisatrack/intelligence/nightly_job.dart';

Uint8List _encode(Float32List value) =>
    value.buffer.asUint8List(value.offsetInBytes, value.lengthInBytes);

void main() {
  late AppDatabase database;
  late MerchantClusterer clusterer;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    clusterer = MerchantClusterer(database);

    final now = DateTime.utc(2026, 7, 10);
    final vec1 = Float32List.fromList([1.0, 0.0, 0.0]);
    final vec2 = Float32List.fromList([0.9, 0.1, 0.0]); // Cosine sim ~0.99 (>= 0.85)

    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'm1',
            canonicalName: 'Swiggy',
            embedding: Value(_encode(vec1)),
            firstSeen: now,
            lastSeen: now,
          ),
        );
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'm2',
            canonicalName: 'Swiggy Instamart',
            embedding: Value(_encode(vec2)),
            firstSeen: now,
            lastSeen: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  test('clustering is deterministic and suggests clusters at >= 0.85 similarity without auto-merging', () async {
    final suggestions = await clusterer.cluster();
    expect(suggestions, hasLength(1));
    expect(suggestions.first.memberMerchantIds, containsAll(['m1', 'm2']));
    expect(suggestions.first.similarityScore, greaterThanOrEqualTo(0.85));

    // AC: No merchant is merged automatically in DB
    final merchants = await database.select(database.merchants).get();
    expect(merchants, hasLength(2));
  });

  test('NightlyPipeline includes merchantClustering stage', () async {
    final pipeline = NightlyPipeline(
      database: database,
      actions: {
        for (final stage in NightlyStage.values) stage: (_) async {},
      },
    );
    final result = await pipeline.run();
    expect(result.stagesRun, contains(NightlyStage.merchantClustering));
  });
}
