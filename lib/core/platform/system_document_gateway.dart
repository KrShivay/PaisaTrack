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

final systemDocumentGatewayProvider = Provider<SystemDocumentGateway>((ref) {
  return const SystemDocumentGateway();
});
