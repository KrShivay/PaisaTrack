import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';

const llmJsonSchemaPlaceholder = '{{JSON_SCHEMA}}';
const llmJsonValidationOnlyPlaceholder = '{{VALIDATE_JSON_ONLY}}';

enum LlmUnavailableReason {
  featureDisabled,
  modelAbsent,
  unsupportedDevice,
  failure
}

sealed class LlmResult<T> {
  const LlmResult();
}

class LlmSuccess<T> extends LlmResult<T> {
  const LlmSuccess(this.value);
  final T value;
}

class LlmUnavailable<T> extends LlmResult<T> {
  const LlmUnavailable(this.reason);
  final LlmUnavailableReason reason;
}

abstract class LlmRuntime {
  const LlmRuntime();

  Future<LlmResult<String>> complete(String prompt);

  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  );

  Future<bool> isModelAvailable();
  Future<bool> isDeviceSupported();
  Future<bool> downloadModel();
  Future<bool> deleteModel();

  Future<bool> downloadModelWithRetry({
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
    Duration maxDelay = const Duration(seconds: 30),
  }) async {
    final random = Random();
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      if (await downloadModel()) return true;
      if (attempt == maxRetries - 1) break;
      if (delay > Duration.zero) {
        final backoff = delay * (1 << attempt);
        final capped = backoff > maxDelay ? maxDelay : backoff;
        await Future<void>.delayed(
          Duration(milliseconds: random.nextInt(capped.inMilliseconds + 1)),
        );
      }
    }
    return false;
  }
}

class PlatformLlmRuntime extends LlmRuntime {
  const PlatformLlmRuntime({
    MethodChannel channel = const MethodChannel('com.paisatrack/llm'),
    this.enabled = AppConstants.enableLocalLlm,
  }) : _channel = channel;

  final MethodChannel _channel;
  final bool enabled;

  @override
  Future<LlmResult<String>> complete(String prompt) async {
    if (!enabled) {
      return const LlmUnavailable(LlmUnavailableReason.featureDisabled);
    }
    if (prompt.trim().isEmpty) {
      return const LlmUnavailable(LlmUnavailableReason.failure);
    }
    try {
      final response = await _channel.invokeMethod<String>('complete', {
        'prompt': prompt,
      });
      if (response == null) {
        return const LlmUnavailable(LlmUnavailableReason.modelAbsent);
      }
      return LlmSuccess(response);
    } on PlatformException catch (error) {
      return LlmUnavailable(_reasonFor(error.code));
    } on MissingPluginException {
      return const LlmUnavailable(LlmUnavailableReason.unsupportedDevice);
    }
  }

  @override
  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  ) async {
    final schemaText = jsonEncode(schema);
    String buildRequest(String instruction) {
      final schemaInstruction = '$instruction\n$schemaText';
      if (prompt.contains(llmJsonSchemaPlaceholder)) {
        return prompt.replaceFirst(
          llmJsonSchemaPlaceholder,
          schemaInstruction,
        );
      }
      if (prompt.contains(llmJsonValidationOnlyPlaceholder)) {
        return prompt.replaceFirst(
          llmJsonValidationOnlyPlaceholder,
          instruction.replaceFirst('this schema', 'the field contract above'),
        );
      }
      return '$prompt\n$schemaInstruction';
    }

    final request = buildRequest('Return only JSON matching this schema:');
    final result = await complete(request);
    if (result is LlmUnavailable<String>) {
      return LlmUnavailable(result.reason);
    }
    final text = (result as LlmSuccess<String>).value;
    final decoded = _validatedObject(text, schema);
    if (decoded != null) return LlmSuccess(decoded);
    return const LlmUnavailable(LlmUnavailableReason.failure);
  }

  @override
  Future<bool> isModelAvailable() => _boolCall('isModelAvailable');

  @override
  Future<bool> isDeviceSupported() => _boolCall('isDeviceSupported');

  @override
  Future<bool> downloadModel() => _boolCall('downloadModel');

  @override
  Future<bool> deleteModel() => _boolCall('deleteModel');

  Future<bool> _boolCall(String method) async {
    try {
      final res = await _channel.invokeMethod<Object?>(method);
      if (res is bool) return res;
      return false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  LlmUnavailableReason _reasonFor(String code) {
    return switch (code.toUpperCase()) {
      'FEATURE_DISABLED' => LlmUnavailableReason.featureDisabled,
      'MODEL_ABSENT' => LlmUnavailableReason.modelAbsent,
      'UNSUPPORTED_DEVICE' => LlmUnavailableReason.unsupportedDevice,
      _ => LlmUnavailableReason.failure,
    };
  }

  Map<String, Object?>? _validatedObject(
    String text,
    Map<String, Object?> schema,
  ) {
    final trimmed = text.trim();
    final matches =
        RegExp(r'\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}').allMatches(trimmed);
    for (final match in matches.toList().reversed) {
      try {
        final decoded = jsonDecode(match.group(0)!);
        if (decoded is Map<String, Object?> &&
            _validateAgainstSchema(decoded, schema)) {
          return decoded;
        }
      } on FormatException {
        continue;
      }
    }

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      try {
        final decoded = jsonDecode(trimmed.substring(start, end + 1));
        if (decoded is Map<String, Object?> &&
            _validateAgainstSchema(decoded, schema)) {
          return decoded;
        }
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  bool _validateAgainstSchema(
    Map<String, Object?> payload,
    Map<String, Object?> schema,
  ) {
    final properties = schema['properties'];
    final required = schema['required'];
    final additionalProperties = schema['additionalProperties'];

    if (additionalProperties == false && properties is Map<String, Object?>) {
      for (final key in payload.keys) {
        if (!properties.containsKey(key)) return false;
      }
    }

    if (required is List) {
      for (final key in required) {
        if (key is String && !payload.containsKey(key)) return false;
      }
    }

    if (properties is Map<String, Object?>) {
      for (final entry in properties.entries) {
        if (!payload.containsKey(entry.key)) continue;
        final value = payload[entry.key];
        final propertySchema = entry.value;
        if (propertySchema is Map<String, Object?>) {
          final expectedType = propertySchema['type'];
          if (expectedType is String &&
              !_matchesType(value, expectedType.toLowerCase())) {
            return false;
          }
          final enumValues = propertySchema['enum'];
          if (enumValues is List && !enumValues.contains(value)) {
            return false;
          }
        }
      }
    }

    return true;
  }

  bool _matchesType(Object? value, String expectedType) {
    return switch (expectedType) {
      'string' => value is String,
      'integer' => value is int,
      'number' => value is num,
      'boolean' => value is bool,
      'null' => value == null,
      _ => true,
    };
  }
}

class NoopLlmRuntime extends LlmRuntime {
  const NoopLlmRuntime([
    this.reason = LlmUnavailableReason.unsupportedDevice,
  ]);

  final LlmUnavailableReason reason;

  @override
  Future<LlmResult<String>> complete(String prompt) async =>
      LlmUnavailable(reason);

  @override
  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  ) async =>
      LlmUnavailable(reason);

  @override
  Future<bool> isModelAvailable() async => false;

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<bool> downloadModel() async => false;

  @override
  Future<bool> deleteModel() async => true;
}

final llmRuntimeProvider = Provider<LlmRuntime>((ref) {
  return const PlatformLlmRuntime();
});
