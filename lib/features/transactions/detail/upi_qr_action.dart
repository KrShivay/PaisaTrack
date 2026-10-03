import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/widgets/bloom/bloom_sheet_scaffold.dart';

const _maxVpaLocalPartLength = 256;
const _maxVpaHandleLength = 64;
const _maxPayeeRunes = 120;
const _maxQrSize = 320.0;

/// Builds a static, escaped UPI payment URI from source-stored VPA evidence.
/// The URI deliberately has no amount, transaction reference, or app ID.
String? buildStaticUpiQrPayload({
  required String? counterpartyVpa,
  required String transactionTitle,
}) {
  final vpa = counterpartyVpa?.trim();
  if (vpa == null || !_isValidVpa(vpa)) return null;

  final payeeName = _safePayeeName(transactionTitle, vpa);
  return Uri(
    scheme: 'upi',
    host: 'pay',
    queryParameters: {
      'pa': vpa,
      'pn': payeeName,
      'cu': 'INR',
    },
  ).toString();
}

bool _isValidVpa(String value) {
  final parts = value.split('@');
  if (parts.length != 2) return false;
  final localPart = parts[0];
  final handle = parts[1];
  if (localPart.isEmpty ||
      localPart.length > _maxVpaLocalPartLength ||
      handle.isEmpty ||
      handle.length > _maxVpaHandleLength) {
    return false;
  }
  const partPattern = r'^[A-Za-z0-9][A-Za-z0-9._-]*$';
  return RegExp(partPattern).hasMatch(localPart) &&
      RegExp(partPattern).hasMatch(handle);
}

String _safePayeeName(String title, String vpa) {
  final safeRunes = title.runes
      .where((rune) => rune >= 0x20 && !(rune >= 0x7f && rune <= 0x9f))
      .take(_maxPayeeRunes)
      .toList(growable: false);
  final trimmed = String.fromCharCodes(safeRunes).trim();
  return trimmed.isEmpty || trimmed.toLowerCase() == 'transaction'
      ? vpa
      : trimmed;
}

/// A shared QR action for stored VPAs in transaction details and Sort.
class UpiQrAction extends StatelessWidget {
  const UpiQrAction({
    super.key,
    required this.counterpartyVpa,
    required this.transactionTitle,
  });

  final String? counterpartyVpa;
  final String transactionTitle;

  @override
  Widget build(BuildContext context) {
    final vpa = counterpartyVpa?.trim();
    if (vpa == null || !_isValidVpa(vpa)) return const SizedBox.shrink();
    final payeeName = _safePayeeName(transactionTitle, vpa);
    final payload = buildStaticUpiQrPayload(
      counterpartyVpa: vpa,
      transactionTitle: transactionTitle,
    );
    if (payload == null) return const SizedBox.shrink();

    return IconButton(
      tooltip: 'Show UPI QR',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: const Icon(Icons.qr_code_2_rounded),
      onPressed: () => _showQr(
        context,
        payload: payload,
        vpa: vpa,
        payeeName: payeeName,
      ),
    );
  }

  Future<void> _showQr(
    BuildContext context, {
    required String payload,
    required String vpa,
    required String payeeName,
  }) {
    return showBloomModalSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => _UpiQrSheet(
        payload: payload,
        vpa: vpa,
        payeeName: payeeName,
        onClose: () => Navigator.of(sheetContext, rootNavigator: true).pop(),
      ),
    );
  }
}

class _UpiQrSheet extends StatelessWidget {
  const _UpiQrSheet({
    required this.payload,
    required this.vpa,
    required this.payeeName,
    required this.onClose,
  });

  final String payload;
  final String vpa;
  final String payeeName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    QrCode? qr;
    try {
      qr = QrCode.fromData(
        data: payload,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
    } catch (_) {
      // Bounded inputs should fit. Keep a defensive fallback if the renderer
      // rejects an unexpected payload instead of crashing the detail route.
    }

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'UPI QR code',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close QR code',
                      onPressed: onClose,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (qr == null)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'This VPA could not be encoded as a QR code.',
                            style: TextStyle(color: Colors.black),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final availableSize = math.min(
                              _maxQrSize,
                              constraints.maxWidth,
                            );
                            // qr_flutter rounds module pixels to the nearest
                            // half logical pixel. Quantize downward and render
                            // gapless so the matrix cannot grow into its quiet
                            // zone after that rounding.
                            final moduleSize =
                                (availableSize / (qr!.moduleCount + 8) * 2)
                                        .floorToDouble() /
                                    2;
                            if (moduleSize <= 0) {
                              return const SizedBox.shrink();
                            }
                            final qrSize = qr.moduleCount * moduleSize;
                            final outerSize = availableSize;
                            final quietZone = (outerSize - qrSize) / 2;
                            return RepaintBoundary(
                              child: Container(
                                width: outerSize,
                                height: outerSize,
                                color: Colors.white,
                                padding: EdgeInsets.all(quietZone),
                                child: QrImageView.withQr(
                                  qr: qr,
                                  size: qrSize,
                                  gapless: true,
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.white,
                                  semanticsLabel: 'UPI QR code for $vpa',
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Colors.black,
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'Scan with a UPI app',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        payeeName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        vpa,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Verify this payee in your UPI app before paying. This name is not verified.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
