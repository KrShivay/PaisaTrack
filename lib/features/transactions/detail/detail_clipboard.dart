import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Single clipboard path for the transaction detail page: copies [text] and
/// confirms with the app snackbar ("Copied [label]").
Future<void> copyDetailValue(
  BuildContext context, {
  required String text,
  required String label,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: text));
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Copied $label')));
}
