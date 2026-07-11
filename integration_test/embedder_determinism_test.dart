import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

/// T-050 deterministic-output test (ADR 0007). Runs on a real device against
/// the pinned Universal Sentence Encoder model:
///
///   flutter test integration_test/embedder_determinism_test.dart -d <device>
///
/// The first run downloads the model (~6 MB, WiFi recommended) and verifies
/// it against the ADR 0007 size/MD5 pin before any inference. The printed
/// dimension must be recorded in ADR 0007 (expected 100) before T-051
/// stores embeddings.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const embedder = PlatformEmbedder();
  const fixedInputs = [
    'HDFC BANK NEFT SALARY',
    'SWIGGY BANGALORE',
    'IRCTC CF NEW DELHI',
  ];

  test('pinned model embeds fixed inputs deterministically', () async {
    final available =
        await embedder.isModelAvailable() || await embedder.downloadModel();
    if (!available) {
      markTestSkipped(
        'Pinned embedder model unavailable (no network?) — determinism not '
        'exercised. Rerun with connectivity.',
      );
      return;
    }

    int? dimension;
    for (final input in fixedInputs) {
      final first = await embedder.embed(input);
      final second = await embedder.embed(input);

      expect(first, isNotNull, reason: 'embed($input) returned null');
      expect(second, isNotNull);
      // Bit-exact equality: same bytes in, same model, same device.
      expect(
        second,
        orderedEquals(first!),
        reason: 'embed($input) was not deterministic',
      );

      dimension ??= first.length;
      expect(
        first.length,
        dimension,
        reason: 'dimension varied across inputs',
      );
    }

    // Distinct inputs must not collapse to one vector.
    final a = await embedder.embed(fixedInputs[0]);
    final b = await embedder.embed(fixedInputs[1]);
    expect(a, isNot(orderedEquals(b!)));

    // ignore: avoid_print
    print('EMBEDDER OUTPUT DIMENSION: $dimension '
        '(record in docs/decisions/0007-on-device-embedding-model.md)');
    expect(dimension, greaterThan(0));
  });
}
