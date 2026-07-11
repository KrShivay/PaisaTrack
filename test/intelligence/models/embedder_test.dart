import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/embedder');
  const embedder = PlatformEmbedder(channel: channel);

  void mockHandler(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('embed', () {
    test('sends the trimmed text and converts Float64List to Float32List',
        () async {
      MethodCall? captured;
      mockHandler((call) async {
        captured = call;
        return Float64List.fromList([0.25, -0.5, 1.0]);
      });

      final vector = await embedder.embed('  HDFC BANK NEFT  ');

      expect(captured?.method, 'embed');
      expect(captured?.arguments, {'text': 'HDFC BANK NEFT'});
      expect(vector, isA<Float32List>());
      expect(vector, orderedEquals([0.25, -0.5, 1.0]));
    });

    test('accepts a plain numeric list payload', () async {
      mockHandler((call) async => <Object?>[0.125, 2, -3.5]);

      final vector = await embedder.embed('SWIGGY');

      expect(vector, orderedEquals([0.125, 2.0, -3.5]));
    });

    test('returns null when the model is unavailable (native null)', () async {
      mockHandler((call) async => null);

      expect(await embedder.embed('ZOMATO'), isNull);
    });

    test('returns null for empty and whitespace-only text without a channel '
        'call', () async {
      var called = false;
      mockHandler((call) async {
        called = true;
        return Float64List.fromList([1.0]);
      });

      expect(await embedder.embed(''), isNull);
      expect(await embedder.embed('   '), isNull);
      expect(called, isFalse);
    });

    test('returns null instead of throwing on PlatformException', () async {
      mockHandler((call) async {
        throw PlatformException(code: 'embedder_failure');
      });

      expect(await embedder.embed('AMAZON PAY'), isNull);
    });

    test('returns null instead of throwing when no native side exists '
        '(MissingPluginException)', () async {
      // No mock handler and no real platform: invokeMethod throws
      // MissingPluginException on the test host.
      const detached = PlatformEmbedder(
        channel: MethodChannel('test/embedder_unregistered'),
      );

      expect(await detached.embed('IRCTC'), isNull);
    });

    test('returns null for an empty vector payload', () async {
      mockHandler((call) async => Float64List(0));

      expect(await embedder.embed('UBER'), isNull);
    });

    test('returns null for a malformed (non-numeric) payload', () async {
      mockHandler((call) async => <Object?>['not-a-number']);

      expect(await embedder.embed('OLA'), isNull);
    });
  });

  group('model lifecycle', () {
    test('isModelAvailable reflects the native answer and defaults to false',
        () async {
      mockHandler((call) async => true);
      expect(await embedder.isModelAvailable(), isTrue);

      mockHandler((call) async => null);
      expect(await embedder.isModelAvailable(), isFalse);

      mockHandler((call) async {
        throw PlatformException(code: 'embedder_failure');
      });
      expect(await embedder.isModelAvailable(), isFalse);
    });

    test('downloadModel surfaces success and swallows failures', () async {
      MethodCall? captured;
      mockHandler((call) async {
        captured = call;
        return true;
      });
      expect(await embedder.downloadModel(), isTrue);
      expect(captured?.method, 'downloadModel');

      mockHandler((call) async {
        throw PlatformException(code: 'embedder_failure');
      });
      expect(await embedder.downloadModel(), isFalse);
    });

    test('deleteModel surfaces the native answer', () async {
      MethodCall? captured;
      mockHandler((call) async {
        captured = call;
        return true;
      });
      expect(await embedder.deleteModel(), isTrue);
      expect(captured?.method, 'deleteModel');
    });
  });

  group('NoopEmbedder', () {
    test('never yields vectors and reports the model unavailable', () async {
      const noop = NoopEmbedder();

      expect(await noop.embed('HDFC BANK'), isNull);
      expect(await noop.isModelAvailable(), isFalse);
      expect(await noop.downloadModel(), isFalse);
      expect(await noop.deleteModel(), isTrue);
    });
  });
}
