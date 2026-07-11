import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// On-device text embedder for merchant entity resolution (T-050, PLAN §7.3).
///
/// Backed by the pinned MediaPipe Universal Sentence Encoder (ADR 0007) via
/// a platform channel. The contract callers rely on:
///
/// * [embed] returns a fixed-dimension vector for a normalized merchant
///   string, or `null` whenever the model is unavailable or anything fails —
///   it NEVER throws, so ingest never blocks on the embedder.
/// * Inference is never networked; [downloadModel] is the app's only
///   permitted network use (ADR 0002) and fetches the integrity-checked
///   model binary itself.
abstract class Embedder {
  /// Embeds [text], or returns `null` when no verified model is available.
  Future<Float32List?> embed(String text);

  /// Whether the verified model file is present on device.
  Future<bool> isModelAvailable();

  /// Downloads and verifies the pinned model (ADR 0007). Returns `true`
  /// when the verified model is in place. Safe to call repeatedly.
  Future<bool> downloadModel();

  /// Deletes the downloaded model (Settings delete control, ADR 0007).
  Future<bool> deleteModel();
}

/// Production embedder over the `com.paisatrack/embedder` platform channel.
class PlatformEmbedder implements Embedder {
  const PlatformEmbedder({
    MethodChannel channel = const MethodChannel('com.paisatrack/embedder'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<Float32List?> embed(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod<Object?>('embed', {
        'text': normalized,
      });
      final vector = _asFloat32List(raw);
      if (vector == null || vector.isEmpty) return null;
      return vector;
    } on PlatformException {
      // Model missing/corrupt or native failure: fall back, never block.
      return null;
    } on MissingPluginException {
      // Host without the native side (e.g. widget tests): no-op.
      return null;
    }
  }

  @override
  Future<bool> isModelAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isModelAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> downloadModel() async {
    try {
      return await _channel.invokeMethod<bool>('downloadModel') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> deleteModel() async {
    try {
      return await _channel.invokeMethod<bool>('deleteModel') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// The channel codec surfaces the native DoubleArray as a [Float64List]
  /// (or a plain list on some paths); embeddings are stored as float32
  /// (schema: `merchants.embedding` BLOB, float32 little-endian).
  Float32List? _asFloat32List(Object? raw) {
    if (raw == null) return null;
    if (raw is Float32List) return raw;
    if (raw is Float64List) return Float32List.fromList(raw.toList());
    if (raw is List) {
      final doubles = <double>[];
      for (final value in raw) {
        if (value is! num) return null;
        doubles.add(value.toDouble());
      }
      return Float32List.fromList(doubles);
    }
    return null;
  }
}

/// No-op embedder for tests and hosts without a model: every call reports
/// the model as unavailable and [embed] returns `null`.
class NoopEmbedder implements Embedder {
  const NoopEmbedder();

  @override
  Future<Float32List?> embed(String text) async => null;

  @override
  Future<bool> isModelAvailable() async => false;

  @override
  Future<bool> downloadModel() async => false;

  @override
  Future<bool> deleteModel() async => true;
}

final embedderProvider = Provider<Embedder>((ref) {
  return const PlatformEmbedder();
});
