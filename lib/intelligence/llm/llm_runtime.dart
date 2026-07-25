import 'dart:convert';

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

final class LlmSuccess<T> extends LlmResult<T> {
  const LlmSuccess(this.value);

  final T value;
}

final class LlmUnavailable<T> extends LlmResult<T> {
  const LlmUnavailable(this.reason);

  final LlmUnavailableReason reason;
}

abstract class LlmRuntime {
  Future<LlmResult<String>> complete(String prompt);

  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  );

  Future<bool> isModelAvailable();
  Future<bool> isDeviceSupported();
  Future<bool> downloadModel();
  Future<bool> downloadModelWithRetry({
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async {
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      final ok = await downloadModel();
      if (ok) return true;
      if (attempt < maxRetries - 1 && delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }
    return false;
  }
  Future<bool> deleteModel();
}

class PlatformLlmRuntime implements LlmRuntime {
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
  Future<bool> downloadModelWithRetry({
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async {
    for (var attempt = 0; attempt < maxRetries; attempt++) {
      final ok = await downloadModel();
      if (ok) return true;
      if (attempt < maxRetries - 1 && delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }
    return false;
  }

  @override
  Future<bool> deleteModel() => _boolCall('deleteModel');

  Future<bool> _boolCall(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  LlmUnavailableReason _reasonFor(String code) => switch (code) {
        'model_absent' => LlmUnavailableReason.modelAbsent,
        'unsupported_device' => LlmUnavailableReason.unsupportedDevice,
        _ => LlmUnavailableReason.failure,
      };

  Map<String, Object?>? _validatedObject(
    String response,
    Map<String, Object?> schema,
  ) {
    for (final candidate in _extractJsonObjects(response)) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is Map<String, Object?> &&
            _matchesSchema(decoded, schema)) {
          return decoded;
        }
      } on FormatException {
        // Keep scanning: small models sometimes emit a malformed example or
        // echo the schema before producing the usable values object.
      }
    }
    return null;
  }

  /// Small on-device models rarely emit pure JSON: they wrap it in markdown
  /// code fences, add prose, or echo the schema. Scan balanced `{...}` blocks
  /// so a later schema-valid values object is not rejected with its wrapper.
  Iterable<String> _extractJsonObjects(String response) sync* {
    var searchFrom = 0;
    while (searchFrom < response.length) {
      final start = response.indexOf('{', searchFrom);
      if (start == -1) return;
      var depth = 0;
      var inString = false;
      var escaped = false;
      var end = -1;
      for (var i = start; i < response.length; i++) {
        final char = response[i];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == r'\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }
        if (char == '"') {
          inString = true;
        } else if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
      if (end >= 0) {
        yield response.substring(start, end + 1);
        searchFrom = end + 1;
      } else {
        // An unbalanced prefix must not hide a later valid object.
        searchFrom = start + 1;
      }
    }
  }

  bool _matchesSchema(Object? value, Map<String, Object?> schema) {
    final enumValues = schema['enum'];
    if (enumValues != null &&
        (enumValues is! List || !enumValues.contains(value))) {
      return false;
    }
    final type = schema['type'];
    if (type == 'object') {
      if (value is! Map<String, Object?>) return false;
      final properties = schema['properties'];
      // A schema that omits `properties` is deliberately open-shaped (e.g.
      // assistantIntentSchema's time_range/compare_to, whose internal shape
      // is checked later by IntentValidator) — accept any object for it.
      if (properties == null) return true;
      if (properties is! Map) return false;
      final required =
          (schema['required'] as List?)?.whereType<String>().toSet() ?? {};
      if (!value.keys.toSet().containsAll(required)) return false;
      if (schema['additionalProperties'] == false &&
          value.keys.any((key) => !properties.containsKey(key))) {
        return false;
      }
      for (final entry in value.entries) {
        final child = properties[entry.key];
        if (child is Map &&
            !_matchesSchema(entry.value, Map<String, Object?>.from(child))) {
          return false;
        }
      }
      return true;
    }
    if (type == 'array') {
      if (value is! List) return false;
      final items = schema['items'];
      return items is! Map ||
          value.every(
            (item) => _matchesSchema(
              item,
              Map<String, Object?>.from(items),
            ),
          );
    }
    return switch (type) {
      'string' => value is String,
      'integer' => value is int,
      'number' => value is num,
      'boolean' => value is bool,
      'null' => value == null,
      _ => true,
    };
  }
}

class NoopLlmRuntime implements LlmRuntime {
  const NoopLlmRuntime({
    this.reason = LlmUnavailableReason.modelAbsent,
  });

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
  Future<bool> downloadModelWithRetry({
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 1),
  }) async =>
      false;

  @override
  Future<bool> deleteModel() async => true;
}

final llmRuntimeProvider = Provider<LlmRuntime>((ref) {
  return const PlatformLlmRuntime();
});
