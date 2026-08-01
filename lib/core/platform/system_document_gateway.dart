import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens Android's Storage Access Framework without requesting storage access.
///
/// Bytes cross the platform channel only after the user chooses a document.
/// A dismissed picker returns `false`/`null` and never creates a partial file.
class SystemDocumentGateway {
  const SystemDocumentGateway({
    MethodChannel channel = const MethodChannel('com.paisatrack/documents'),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// Opens a bounded writer session for a user-selected document.
  ///
  /// A null result means the picker was dismissed. Chunks must be no larger
  /// than [maxDocumentChunkBytes].
  Future<String?> beginSaveDocument({
    required String suggestedName,
    required String mimeType,
  }) async {
    return _channel.invokeMethod<String>('beginSaveDocument', {
      'suggestedName': suggestedName,
      'mimeType': mimeType,
    });
  }

  Future<bool> writeDocumentChunk({
    required String sessionId,
    required Uint8List bytes,
  }) async {
    if (bytes.length > maxDocumentChunkBytes) {
      throw ArgumentError.value(bytes.length, 'bytes');
    }
    return await _channel.invokeMethod<bool>('writeDocumentChunk', {
          'sessionId': sessionId,
          'bytes': bytes,
        }) ??
        false;
  }

  Future<bool> finishDocument({required String sessionId}) async {
    return await _channel.invokeMethod<bool>('finishDocument', {
          'sessionId': sessionId,
        }) ??
        false;
  }

  Future<void> cancelDocument({required String sessionId}) {
    return _channel.invokeMethod<void>('cancelDocument', {
      'sessionId': sessionId,
    });
  }

  /// Opens a bounded reader session for a user-selected document.
  Future<String?> beginOpenDocument({required String mimeType}) {
    return _channel.invokeMethod<String>('beginOpenDocument', {
      'mimeType': mimeType,
    });
  }

  /// Returns null at EOF. The platform enforces the same chunk ceiling.
  Future<Uint8List?> readDocumentChunk({
    required String sessionId,
    int maxBytes = maxDocumentChunkBytes,
  }) async {
    if (maxBytes <= 0 || maxBytes > maxDocumentChunkBytes) {
      throw ArgumentError.value(maxBytes, 'maxBytes');
    }
    return _channel.invokeMethod<Uint8List>('readDocumentChunk', {
      'sessionId': sessionId,
      'maxBytes': maxBytes,
    });
  }

  Future<void> closeDocument({required String sessionId}) {
    return _channel.invokeMethod<void>('closeDocument', {
      'sessionId': sessionId,
    });
  }

  /// Saves [bytes] to a user-selected destination.
  ///
  /// Returns `false` when the system picker is dismissed.
  Future<bool> saveDocument({
    required String suggestedName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final saved = await _channel.invokeMethod<bool>('saveDocument', {
      'suggestedName': suggestedName,
      'mimeType': mimeType,
      'bytes': bytes,
    });
    return saved ?? false;
  }

  /// Reads a user-selected document, or returns `null` when dismissed.
  Future<Uint8List?> openDocument({required String mimeType}) {
    return _channel.invokeMethod<Uint8List>('openDocument', {
      'mimeType': mimeType,
    });
  }
}

const maxDocumentChunkBytes = 64 * 1024;

final systemDocumentGatewayProvider = Provider<SystemDocumentGateway>((ref) {
  return const SystemDocumentGateway();
});
