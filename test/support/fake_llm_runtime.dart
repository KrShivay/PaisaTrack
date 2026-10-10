import 'dart:async';
import 'dart:typed_data';

import 'package:paisatrack/intelligence/llm/llm_model_status.dart';
import 'package:paisatrack/intelligence/llm/llm_runtime.dart';
import 'package:paisatrack/intelligence/models/embedder.dart';

const fakeModelSize = 2400000000;

LlmModelStatus fakeStatus({
  bool installed = false,
  bool downloadSupported = true,
  LlmSupportReason reason = LlmSupportReason.supported,
  LlmDownloadState state = LlmDownloadState.idle,
  int downloaded = 0,
}) {
  return LlmModelStatus(
    modelId: 'qwen3',
    displayName: 'Qwen3 0.6B',
    sizeBytes: fakeModelSize,
    runtime: 'LiteRT-LM',
    quantization: 'int8',
    contextTokens: 4096,
    installed: installed,
    supported: downloadSupported,
    downloadSupported: downloadSupported,
    supportReason: reason,
    backend: 'cpu',
    downloadState: state,
    downloadedBytes: downloaded,
  );
}

/// Runtime whose download completes only when the test says so.
class FakeLlmRuntime extends LlmRuntime {
  FakeLlmRuntime(this.status);

  LlmModelStatus status;
  Completer<LlmOperationResult>? pending;
  int downloadCalls = 0;
  int cancelCalls = 0;
  int deleteCalls = 0;

  @override
  Future<LlmModelStatus> modelStatus() async => status;

  @override
  Future<LlmOperationResult> downloadModelResult() {
    downloadCalls++;
    status = fakeStatus(state: LlmDownloadState.downloading);
    return (pending = Completer<LlmOperationResult>()).future;
  }

  void finish(LlmOperationResult result, LlmModelStatus after) {
    status = after;
    pending!.complete(result);
  }

  @override
  Future<bool> cancelModelDownload() async {
    cancelCalls++;
    finish(
      const LlmOperationResult(success: false, code: 'download_cancelled'),
      fakeStatus(state: LlmDownloadState.cancelled),
    );
    return true;
  }

  @override
  Future<bool> deleteModel() async {
    deleteCalls++;
    status = fakeStatus();
    return true;
  }

  @override
  Future<bool> downloadModel() async => false;
  @override
  Future<bool> isModelAvailable() async => status.installed;
  @override
  Future<bool> isDeviceSupported() async => status.supported;
  @override
  Future<LlmResult<String>> complete(String prompt) async =>
      const LlmUnavailable(LlmUnavailableReason.modelAbsent);
  @override
  Future<LlmResult<Map<String, Object?>>> extractJson(
    String prompt,
    Map<String, Object?> schema,
  ) async =>
      const LlmUnavailable(LlmUnavailableReason.modelAbsent);
}

class FakeEmbedder implements Embedder {
  bool installed = false;
  int downloads = 0;

  @override
  Future<Float32List?> embed(String text) async => null;
  @override
  Future<bool> isModelAvailable() async => installed;
  @override
  Future<bool> downloadModel() async {
    downloads++;
    installed = true;
    return true;
  }

  @override
  Future<bool> deleteModel() async {
    installed = false;
    return true;
  }
}
