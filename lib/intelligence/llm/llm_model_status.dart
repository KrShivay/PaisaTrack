enum LlmSupportReason {
  supported,
  lowRamDevice,
  insufficientTotalMemory,
  insufficientAvailableMemory,
  insufficientStorage,
  backendUnavailable,
  modelAbsent,
  initializationFailed,
  unknown;

  static LlmSupportReason parse(Object? value) => switch (value) {
        'supported' => supported,
        'low_ram_device' => lowRamDevice,
        'insufficient_total_memory' => insufficientTotalMemory,
        'insufficient_available_memory' => insufficientAvailableMemory,
        'insufficient_storage' => insufficientStorage,
        'backend_unavailable' => backendUnavailable,
        'model_absent' => modelAbsent,
        'initialization_failure' ||
        'initialization_failed' =>
          initializationFailed,
        _ => unknown,
      };
}

enum LlmDownloadState {
  idle,
  downloading,
  verifying,
  installed,
  cancelled,
  failed,
  unknown;

  static LlmDownloadState parse(Object? value) =>
      values.where((state) => state.name == value).firstOrNull ?? unknown;
}

class LlmModelStatus {
  const LlmModelStatus({
    required this.modelId,
    required this.displayName,
    required this.sizeBytes,
    required this.runtime,
    required this.quantization,
    required this.contextTokens,
    required this.installed,
    required this.supported,
    required this.downloadSupported,
    required this.supportReason,
    required this.backend,
    required this.downloadState,
    required this.downloadedBytes,
  });

  factory LlmModelStatus.fromMap(Map<Object?, Object?> map) {
    int integer(Object? value) => value is int ? value : 0;
    return LlmModelStatus(
      modelId: map['modelId'] is String ? map['modelId']! as String : 'unknown',
      displayName: map['displayName'] is String
          ? map['displayName']! as String
          : 'AI model',
      sizeBytes: integer(map['sizeBytes']),
      runtime: map['runtime'] is String ? map['runtime']! as String : 'Unknown',
      quantization: map['quantization'] is String
          ? map['quantization']! as String
          : 'Unknown',
      contextTokens: integer(map['contextTokens']),
      installed: map['installed'] == true,
      supported: map['supported'] == true,
      downloadSupported: map['downloadSupported'] == true,
      supportReason: LlmSupportReason.parse(map['supportReason']),
      backend: map['backend'] is String ? map['backend']! as String : 'Unknown',
      downloadState: LlmDownloadState.parse(map['downloadState']),
      downloadedBytes: integer(map['downloadedBytes']),
    );
  }

  static const unavailable = LlmModelStatus(
    modelId: 'unknown',
    displayName: 'AI model',
    sizeBytes: 0,
    runtime: 'Unknown',
    quantization: 'Unknown',
    contextTokens: 0,
    installed: false,
    supported: false,
    downloadSupported: false,
    supportReason: LlmSupportReason.unknown,
    backend: 'Unknown',
    downloadState: LlmDownloadState.unknown,
    downloadedBytes: 0,
  );

  final String modelId;
  final String displayName;
  final int sizeBytes;
  final String runtime;
  final String quantization;
  final int contextTokens;
  final bool installed;
  final bool supported;
  final bool downloadSupported;
  final LlmSupportReason supportReason;
  final String backend;
  final LlmDownloadState downloadState;
  final int downloadedBytes;
}

class LlmOperationResult {
  const LlmOperationResult({required this.success, required this.code});

  const LlmOperationResult.ok() : this(success: true, code: 'ok');

  final bool success;
  final String code;
}
