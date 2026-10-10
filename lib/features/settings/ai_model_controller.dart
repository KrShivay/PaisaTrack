import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../intelligence/llm/llm_model_status.dart';
import '../../intelligence/llm/llm_runtime.dart';
import '../../intelligence/models/embedder.dart';

/// Approximate size of the pinned merchant-matching embedder (ADR 0007).
const embedderModelSizeBytes = 6120274;

/// User-facing phase of the on-device language model.
enum AiModelPhase {
  loading,
  notDownloaded,
  downloading,
  verifying,
  installed,
  unsupported,
}

class AiModelState {
  const AiModelState({
    this.status,
    this.downloadInFlight = false,
    this.error,
    this.embedderInstalled,
    this.embedderBusy = false,
    this.embedderError,
  });

  /// Latest native status; `null` until the first read completes.
  final LlmModelStatus? status;

  /// True while this controller is awaiting a native download call.
  final bool downloadInFlight;

  /// Friendly message for the last failed or cancelled language-model action.
  final String? error;

  /// Whether the embedder model is on device; `null` until first read.
  final bool? embedderInstalled;
  final bool embedderBusy;
  final String? embedderError;

  AiModelPhase get phase {
    final status = this.status;
    if (status == null) return AiModelPhase.loading;
    if (status.installed) return AiModelPhase.installed;
    if (downloadInFlight ||
        status.downloadState == LlmDownloadState.downloading) {
      return AiModelPhase.downloading;
    }
    if (status.downloadState == LlmDownloadState.verifying) {
      return AiModelPhase.verifying;
    }
    if (!status.downloadSupported) return AiModelPhase.unsupported;
    return AiModelPhase.notDownloaded;
  }

  /// Download progress in `0..1`, or `null` when the size is unknown.
  double? get progress {
    final status = this.status;
    if (status == null || status.sizeBytes <= 0) return null;
    return (status.downloadedBytes / status.sizeBytes).clamp(0.0, 1.0);
  }

  AiModelState copyWith({
    LlmModelStatus? status,
    bool? downloadInFlight,
    Object? error = _keep,
    bool? embedderInstalled,
    bool? embedderBusy,
    Object? embedderError = _keep,
  }) {
    return AiModelState(
      status: status ?? this.status,
      downloadInFlight: downloadInFlight ?? this.downloadInFlight,
      error: identical(error, _keep) ? this.error : error as String?,
      embedderInstalled: embedderInstalled ?? this.embedderInstalled,
      embedderBusy: embedderBusy ?? this.embedderBusy,
      embedderError: identical(embedderError, _keep)
          ? this.embedderError
          : embedderError as String?,
    );
  }
}

const Object _keep = Object();

/// Friendly copy for a [LlmSupportReason] that blocks the model.
String aiSupportReasonCopy(LlmSupportReason reason) => switch (reason) {
      LlmSupportReason.lowRamDevice =>
        'This device is marked as low-memory, so the on-device AI model cannot run on it.',
      LlmSupportReason.insufficientTotalMemory =>
        "This device doesn't have enough memory (RAM) to run the on-device AI model.",
      LlmSupportReason.insufficientAvailableMemory =>
        'Not enough free memory right now. Close other apps and try again.',
      LlmSupportReason.insufficientStorage =>
        'Not enough free storage. Free up some space and try again.',
      LlmSupportReason.backendUnavailable =>
        "This device can't run the on-device AI engine.",
      LlmSupportReason.modelAbsent => 'The AI model is not downloaded yet.',
      LlmSupportReason.initializationFailed =>
        "The AI model couldn't start on this device.",
      LlmSupportReason.supported ||
      LlmSupportReason.unknown =>
        "The on-device AI model isn't available on this device.",
    };

/// Maps a failed download [code] (native operation code) to friendly copy.
String aiDownloadErrorCopy(String code) {
  switch (code) {
    case 'download_cancelled':
      return 'Download cancelled. Starting again resumes where it stopped.';
    case 'download_failure':
    case 'failure':
    case 'timeout':
      return "Download didn't finish. Check your connection and try again; "
          'it resumes where it stopped.';
    case 'busy':
    case 'in_progress':
      return 'A model operation is already running. Try again in a moment.';
    case 'unavailable':
      return "The on-device AI isn't available in this build.";
  }
  final reason = LlmSupportReason.parse(code);
  return reason == LlmSupportReason.unknown
      ? "Download didn't finish. Please try again."
      : aiSupportReasonCopy(reason);
}

/// Human readable decimal size, e.g. `2.4 GB` or `5.8 MB`.
String formatModelSize(int bytes) {
  if (bytes >= 1000000000) {
    return '${(bytes / 1000000000).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
  if (bytes >= 1000) return '${(bytes / 1000).round()} KB';
  return '$bytes B';
}

/// Drives the Settings "On-device AI" section: status, download with polled
/// progress, cancel and delete for the LLM and the embedder model.
class AiModelController extends Notifier<AiModelState> {
  static const pollInterval = Duration(milliseconds: 500);

  Timer? _poller;
  Future<void>? _download;
  Future<void>? _embedderDownload;
  bool _polling = false;
  bool _disposed = false;

  LlmRuntime get _runtime => ref.read(llmRuntimeProvider);
  Embedder get _embedder => ref.read(embedderProvider);

  @override
  AiModelState build() {
    ref.onDispose(() {
      _disposed = true;
      _poller?.cancel();
      _poller = null;
    });
    Future<void>.microtask(refresh);
    return const AiModelState();
  }

  void _set(AiModelState next) {
    if (!_disposed) state = next;
  }

  /// Re-reads native status for both models.
  Future<void> refresh() async {
    final status = await _runtime.modelStatus();
    final embedder = await _embedderInstalled();
    _set(state.copyWith(status: status, embedderInstalled: embedder));
  }

  Future<bool> _embedderInstalled() async {
    try {
      return await _embedder.isModelAvailable();
    } on Object {
      return false;
    }
  }

  /// Starts the download. Calling again while one runs joins it.
  Future<void> startDownload() => _download ??= _runDownload();

  Future<void> _runDownload() async {
    _set(state.copyWith(downloadInFlight: true, error: null));
    _poller = Timer.periodic(pollInterval, (_) => _pollOnce());
    try {
      final result = await _runtime.downloadModelResult();
      _stopPolling();
      await refresh();
      _set(
        state.copyWith(
          error: result.success ? null : aiDownloadErrorCopy(result.code),
        ),
      );
    } finally {
      _stopPolling();
      _download = null;
      _set(state.copyWith(downloadInFlight: false));
    }
  }

  void _stopPolling() {
    _poller?.cancel();
    _poller = null;
  }

  Future<void> _pollOnce() async {
    if (_polling) return;
    _polling = true;
    try {
      final status = await _runtime.modelStatus();
      if (_poller != null) _set(state.copyWith(status: status));
    } finally {
      _polling = false;
    }
  }

  Future<void> cancelDownload() async {
    if (_download == null) return;
    await _runtime.cancelModelDownload();
  }

  Future<void> deleteModel() async {
    if (_download != null) return;
    final ok = await _runtime.deleteModel();
    await refresh();
    _set(
      state.copyWith(
        error: ok ? null : "Couldn't delete the model. Please try again.",
      ),
    );
  }

  Future<void> downloadEmbedder() => _embedderDownload ??= _runEmbedder();

  Future<void> _runEmbedder() async {
    _set(state.copyWith(embedderBusy: true, embedderError: null));
    try {
      var ok = false;
      try {
        ok = await _embedder.downloadModel();
      } on Object {
        ok = false;
      }
      final installed = await _embedderInstalled();
      _set(
        state.copyWith(
          embedderInstalled: installed,
          embedderError: ok
              ? null
              : "Download didn't finish. Check your connection and try again.",
        ),
      );
    } finally {
      _embedderDownload = null;
      _set(state.copyWith(embedderBusy: false));
    }
  }

  Future<void> deleteEmbedder() async {
    if (_embedderDownload != null) return;
    _set(state.copyWith(embedderBusy: true, embedderError: null));
    try {
      final ok = await _embedder.deleteModel();
      final installed = await _embedderInstalled();
      _set(
        state.copyWith(
          embedderInstalled: installed,
          embedderError: ok ? null : "Couldn't delete the model.",
        ),
      );
    } finally {
      _set(state.copyWith(embedderBusy: false));
    }
  }
}

final aiModelControllerProvider =
    NotifierProvider<AiModelController, AiModelState>(AiModelController.new);
