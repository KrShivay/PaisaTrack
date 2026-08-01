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

  test('streaming sessions keep chunks bounded and expose picker lifecycle',
      () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'beginSaveDocument':
          return 'save-1';
        case 'writeDocumentChunk':
          return true;
        case 'finishDocument':
          return true;
        case 'beginOpenDocument':
          return 'open-1';
        case 'readDocumentChunk':
          return calls
                      .where((call) => call.method == 'readDocumentChunk')
                      .length ==
                  1
              ? Uint8List.fromList([7, 8])
              : null;
        default:
          return null;
      }
    });

    final saveSession = await gateway.beginSaveDocument(
      suggestedName: 'paisatrack_export.ptrack',
      mimeType: 'application/octet-stream',
    );
    expect(saveSession, 'save-1');
    expect(
      await gateway.writeDocumentChunk(
        sessionId: saveSession!,
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      isTrue,
    );
    expect(await gateway.finishDocument(sessionId: saveSession), isTrue);

    final openSession =
        await gateway.beginOpenDocument(mimeType: 'application/octet-stream');
    expect(openSession, 'open-1');
    expect(
      await gateway.readDocumentChunk(sessionId: openSession!),
      [7, 8],
    );
    expect(
      await gateway.readDocumentChunk(sessionId: openSession),
      isNull,
    );
    await gateway.closeDocument(sessionId: openSession);

    expect(
      calls.map((call) => call.method),
      containsAll(<String>[
        'beginSaveDocument',
        'writeDocumentChunk',
        'finishDocument',
        'beginOpenDocument',
        'readDocumentChunk',
        'closeDocument',
      ]),
    );
  });

  test('streaming gateway rejects chunks above the platform ceiling', () async {
    await expectLater(
      gateway.writeDocumentChunk(
        sessionId: 'save-1',
        bytes: Uint8List(maxDocumentChunkBytes + 1),
      ),
      throwsArgumentError,
    );
    await expectLater(
      gateway.readDocumentChunk(
        sessionId: 'open-1',
        maxBytes: maxDocumentChunkBytes + 1,
      ),
      throwsArgumentError,
    );
  });
}
