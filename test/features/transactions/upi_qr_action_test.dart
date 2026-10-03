import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:paisatrack/features/transactions/detail/upi_qr_action.dart';

Future<void> _exportQr(
  WidgetTester tester,
  Finder qr,
  String filename,
) async {
  final boundaryFinder = find
      .ancestor(
        of: qr,
        matching: find.byType(RepaintBoundary),
      )
      .first;
  final boundary = tester.renderObject<RenderRepaintBoundary>(boundaryFinder);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull);
      final directory = Directory('.dart_tool/qa');
      await directory.create(recursive: true);
      await File('${directory.path}/$filename')
          .writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  group('buildStaticUpiQrPayload', () {
    test('encodes exactly the VPA, bounded payee name, and INR', () {
      final payload = buildStaticUpiQrPayload(
        counterpartyVpa: '  shop.name_1@bank-handle  ',
        transactionTitle: 'Tea & Books + बचत',
      );

      final uri = Uri.parse(payload!);
      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      expect(uri.queryParameters, {
        'pa': 'shop.name_1@bank-handle',
        'pn': 'Tea & Books + बचत',
        'cu': 'INR',
      });
      expect(uri.queryParameters.keys, unorderedEquals(['pa', 'pn', 'cu']));
      expect(uri.queryParameters, isNot(contains('am')));
      expect(uri.queryParameters, isNot(contains('tr')));
      expect(uri.queryParameters.values.join(' '), isNot(contains('txn_')));
      expect(uri.toString(), contains('%26'));
      expect(uri.toString(), contains('%2B'));
    });

    test('uses the exact VPA as payee fallback and strips controls', () {
      final fallback = Uri.parse(
        buildStaticUpiQrPayload(
          counterpartyVpa: 'payee@handle',
          transactionTitle: '\u0001\u007f',
        )!,
      );
      expect(fallback.queryParameters['pn'], 'payee@handle');

      final generic = Uri.parse(
        buildStaticUpiQrPayload(
          counterpartyVpa: 'payee@handle',
          transactionTitle: 'Transaction',
        )!,
      );
      expect(generic.queryParameters['pn'], 'payee@handle');

      final bounded = Uri.parse(
        buildStaticUpiQrPayload(
          counterpartyVpa: 'payee@handle',
          transactionTitle: List.filled(500, '🧾').join(),
        )!,
      );
      expect(bounded.queryParameters['pn']!.runes.length, 120);
    });

    test('rejects missing, malformed, injected, and oversized VPAs', () {
      final invalid = <String?>[
        null,
        '',
        '@handle',
        'payee@',
        'payee@handle&am=1',
        'payee@handle?x=1',
        'payee@handle/path',
        'pay ee@handle',
        'payee\n@handle',
        '${List.filled(257, 'a').join()}@handle',
        'payee@${List.filled(65, 'h').join()}',
      ];
      for (final vpa in invalid) {
        expect(
          buildStaticUpiQrPayload(
            counterpartyVpa: vpa,
            transactionTitle: 'Shop',
          ),
          isNull,
          reason: 'Should reject $vpa',
        );
      }
      expect(
        buildStaticUpiQrPayload(
          counterpartyVpa:
              '${List.filled(256, 'a').join()}@${List.filled(64, 'h').join()}',
          transactionTitle: 'Shop',
        ),
        isNotNull,
      );
    });
  });

  for (final (name, theme) in <(String, ThemeData)>[
    ('light', ThemeData.light()),
    ('dark', ThemeData.dark()),
  ]) {
    testWidgets('shows and closes a responsive white QR sheet in $name theme',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: UpiQrAction(
                counterpartyVpa: 'shop@bank',
                transactionTitle: 'Shop & Tea',
              ),
            ),
          ),
        ),
      );

      final action = find.byTooltip('Show UPI QR');
      expect(action, findsOneWidget);
      expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(action).width, greaterThanOrEqualTo(48));
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text('UPI QR code'), findsOneWidget);
      expect(find.text('Shop & Tea'), findsOneWidget);
      expect(find.text('shop@bank'), findsOneWidget);
      expect(find.textContaining('Verify this payee'), findsOneWidget);
      final qr = find.byType(QrImageView);
      expect(qr, findsOneWidget);
      final qrWidget = tester.widget<QrImageView>(qr);
      expect(qrWidget.eyeStyle.eyeShape, QrEyeShape.square);
      expect(
        qrWidget.dataModuleStyle.dataModuleShape,
        QrDataModuleShape.square,
      );
      expect(qrWidget.gapless, isTrue);
      final moduleCount = QrCode.fromData(
        data: buildStaticUpiQrPayload(
          counterpartyVpa: 'shop@bank',
          transactionTitle: 'Shop & Tea',
        )!,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ).moduleCount;
      final qrSize = qrWidget.size!;
      final moduleSize = qrSize / moduleCount;
      final boundary = find.ancestor(
        of: qr,
        matching: find.byType(RepaintBoundary),
      );
      expect(tester.getSize(boundary.first).width, greaterThanOrEqualTo(256));
      expect(tester.getSize(boundary.first).height, greaterThanOrEqualTo(256));
      final qrSurface = find.ancestor(
        of: qr,
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.padding != null,
        ),
      );
      final surfacePadding =
          tester.widget<Container>(qrSurface.first).padding! as EdgeInsets;
      expect(surfacePadding.left, greaterThanOrEqualTo(4 * moduleSize));
      expect(surfacePadding.right, greaterThanOrEqualTo(4 * moduleSize));
      expect(surfacePadding.top, greaterThanOrEqualTo(4 * moduleSize));
      expect(surfacePadding.bottom, greaterThanOrEqualTo(4 * moduleSize));
      expect(
        find.textContaining('upi://'),
        findsNothing,
        reason: 'The encoded URI is an internal value, not sheet copy.',
      );
      final close = find.byTooltip('Close QR code');
      final closeButton = find.ancestor(
        of: close,
        matching: find.byType(IconButton),
      );
      final closeIcon =
          tester.widget<IconButton>(closeButton.first).icon as Icon;
      expect(closeIcon.color, Colors.black);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(qr, findsNothing);
      expect(action, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('maximum valid VPA keeps a 256dp QR and full quiet zone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final vpa =
        '${List.filled(256, 'a').join()}@${List.filled(64, 'h').join()}';
    final title = List.filled(120, '🧾').join();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: UpiQrAction(
              counterpartyVpa: vpa,
              transactionTitle: title,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Show UPI QR'));
    await tester.pumpAndSettle();

    final qr = find.byType(QrImageView);
    expect(qr, findsOneWidget);
    final qrWidget = tester.widget<QrImageView>(qr);
    final payload = buildStaticUpiQrPayload(
      counterpartyVpa: vpa,
      transactionTitle: title,
    )!;
    final moduleCount = QrCode.fromData(
      data: payload,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    ).moduleCount;
    final moduleSize = qrWidget.size! / moduleCount;
    final boundary = find
        .ancestor(
          of: qr,
          matching: find.byType(RepaintBoundary),
        )
        .first;
    final outerSize = tester.getSize(boundary);
    expect(outerSize.width, greaterThanOrEqualTo(256));
    expect(outerSize.height, greaterThanOrEqualTo(256));
    final surfaceFinder = find.ancestor(
      of: qr,
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.padding != null,
      ),
    );
    final padding =
        tester.widget<Container>(surfaceFinder.first).padding! as EdgeInsets;
    expect(padding.left, greaterThanOrEqualTo(4 * moduleSize));
    expect(padding.right, greaterThanOrEqualTo(4 * moduleSize));
    expect(padding.top, greaterThanOrEqualTo(4 * moduleSize));
    expect(padding.bottom, greaterThanOrEqualTo(4 * moduleSize));
    expect(tester.takeException(), isNull);
    await _exportQr(tester, qr, 't199-upi-qr-max-input.png');
  });

  testWidgets('missing or malformed VPA has no QR action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              UpiQrAction(counterpartyVpa: null, transactionTitle: 'Shop'),
              UpiQrAction(
                counterpartyVpa: 'not a vpa',
                transactionTitle: 'Shop',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byTooltip('Show UPI QR'), findsNothing);
  });

  testWidgets('exports a synthetic QR including its quiet zone for decoding',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: UpiQrAction(
              counterpartyVpa: 'synthetic.qr@upi',
              transactionTitle: 'Synthetic QR QA',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Show UPI QR'));
    await tester.pumpAndSettle();

    await _exportQr(
      tester,
      find.byType(QrImageView),
      't199-upi-qr.png',
    );
  });
}
