import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import 'llm_model_status.dart';
import 'llm_request.dart';

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

  Future<LlmResult<String>> completeRequest(LlmRequest request) =>
      complete(request.userMessage);

  Future<LlmResult<Map<String, Object?>>> extractJsonRequest(
    LlmRequest request,
    Map<String, Object?> schema,
  ) =>
      extractJson(
        '${request.systemInstruction}\n${request.userMessage}',
        schema,
      );

  Future<bool> isModelAvailable();
  Future<bool> isDeviceSupported();
  Future<bool> downloadModel();
  Future<bool> deleteModel();

  Future<LlmModelStatus> modelStatus() async {
    final results = await Future.wait([
      isModelAvailable(),
      isDeviceSupported(),
    ]);
    return LlmModelStatus(
      modelId: 'unknown',
      displayName: 'AI model',
      sizeBytes: 0,
      runtime: 'Unknown',
      quantization: 'Unknown',
      contextTokens: 0,
      installed: results[0],
      supported: results[1],
      downloadSupported: results[1],
      supportReason:
          results[1] ? LlmSupportReason.supported : LlmSupportReason.unknown,
      backend: 'Unknown',
      downloadState:
          results[0] ? LlmDownloadState.installed : LlmDownloadState.idle,
      downloadedBytes: 0,
    );
  }

  Future<LlmOperationResult> downloadModelResult() async {
    final success = await downloadModel();
    return LlmOperationResult(
      success: success,
      code: success ? 'ok' : 'failure',
    );
  }

  Future<bool> cancelModelDownload() async => false;

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
  Future<LlmResult<String>> complete(String prompt) => completeRequest(
        LlmRequest(
          systemInstruction: "Follow the user's instruction.",
          userMessage: prompt,
          task: LlmTask.narrative,
        ),
      );

  @override
  Future<LlmResult<String>> completeRequest(LlmRequest request) async {
    if (!enabled) {
      return const LlmUnavailable(LlmUnavailableReason.featureDisabled);
    }
    if (!request.isValid) {
      return const LlmUnavailable(LlmUnavailableReason.failure);
    }
    try {
      final response = await _channel.invokeMethod<String>('complete', {
        'systemInstruction': request.systemInstruction.trim(),
        'userMessage': request.userMessage.trim(),
        'task': request.task.wireValue,
      }).timeout(const Duration(minutes: 2));
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
  ) =>
      extractJsonRequest(
        LlmRequest(
          systemInstruction:
              'Extract the requested data and return only schema-valid JSON.',
          userMessage: prompt,
          task: LlmTask.jsonExtraction,
        ),
        schema,
      );

  @override
  Future<LlmResult<Map<String, Object?>>> extractJsonRequest(
    LlmRequest request,
    Map<String, Object?> schema,
  ) async {
    if (!request.isValid) {
      return const LlmUnavailable(LlmUnavailableReason.failure);
    }
    final schemaText = jsonEncode(schema);
    final result = await completeRequest(
      LlmRequest(
        systemInstruction:
            '${request.systemInstruction.trim()}\nReturn only JSON matching this schema:\n$schemaText',
        userMessage: request.userMessage,
        task: request.task,
      ),
    );
    if (result is LlmUnavailable<String>) {
      return LlmUnavailable(result.reason);
    }
    final text = _withoutThinking((result as LlmSuccess<String>).value);
    if (text == null) {
      return const LlmUnavailable(LlmUnavailableReason.failure);
    }
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

  @override
  Future<LlmModelStatus> modelStatus() async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'modelStatus',
      );
      return result == null
          ? LlmModelStatus.unavailable
          : LlmModelStatus.fromMap(result);
    } on PlatformException {
      return LlmModelStatus.unavailable;
    }
  }

  @override
  Future<LlmOperationResult> downloadModelResult() =>
      _operationCall('downloadModel');

  @override
  Future<bool> cancelModelDownload() => _boolCall('cancelModelDownload');

  Future<LlmOperationResult> _operationCall(String method) async {
    try {
      final result = await _channel
          .invokeMethod<Object?>(method)
          .timeout(const Duration(minutes: 15));
      final success = result == true;
      return LlmOperationResult(
        success: success,
        code: success ? 'ok' : 'failure',
      );
    } on PlatformException catch (error) {
      return LlmOperationResult(success: false, code: error.code);
    }
  }

  Future<bool> _boolCall(String method) async {
    try {
      final res = await _channel.invokeMethod<Object?>(method);
      return res == true;
    } on PlatformException {
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

  String? _withoutThinking(String value) {
    var text = value.trim();
    final emptyThinking = RegExp(
      r'^<think>\s*</think>\s*',
      caseSensitive: false,
    );
    text = text.replaceFirst(emptyThinking, '');
    if (RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false)
            .hasMatch(text) ||
        text.toLowerCase().contains('<think>') ||
        text.toLowerCase().contains('</think>')) {
      return null;
    }
    return text;
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
