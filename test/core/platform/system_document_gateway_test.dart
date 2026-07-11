import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/platform/system_document_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/system_documents');
  const gateway = SystemDocumentGateway(channel: channel);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('saveDocument sends name, MIME type, and bytes over the channel',
      () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return true;
    });
    final bytes = Uint8List.fromList([1, 2, 3]);

    final saved = await gateway.saveDocument(
      suggestedName: 'paisatrack_export.ptrack',
      mimeType: 'application/octet-stream',
      bytes: bytes,
    );

    expect(saved, isTrue);
    expect(captured?.method, 'saveDocument');
    expect(captured?.arguments, {
      'suggestedName': 'paisatrack_export.ptrack',
      'mimeType': 'application/octet-stream',
      'bytes': bytes,
    });
  });

  test('dismissed save picker returns false', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final saved = await gateway.saveDocument(
      suggestedName: 'transactions_export.json',
      mimeType: 'application/json',
      bytes: Uint8List(0),
    );

    expect(saved, isFalse);
  });

  test('openDocument returns selected bytes and null when dismissed', () async {
    final selected = Uint8List.fromList([4, 5, 6]);
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return selected;
    });

    expect(
      await gateway.openDocument(mimeType: 'application/octet-stream'),
      selected,
    );
    expect(captured?.method, 'openDocument');
    expect(captured?.arguments, {'mimeType': 'application/octet-stream'});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    expect(
      await gateway.openDocument(mimeType: 'application/octet-stream'),
      isNull,
    );
  });
}
