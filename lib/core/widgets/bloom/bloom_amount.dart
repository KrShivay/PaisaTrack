import 'package:flutter/material.dart';

import '../../format.dart';
import '../../theme/app_theme.dart';
import '../../theme/paisa_colors.dart';

/// Renders a formatted rupee amount in IBM Plex Mono with semantic coloring.
///
/// The amount is formatted using [formatInr] and displayed with tight letter
/// spacing as required by the Bloom design system. Optionally hides paise
/// when [showPaise] is false to keep hero numbers clean.
class BloomAmount extends StatelessWidget {
  const BloomAmount({
    super.key,
    required this.amount,
    this.currencyCode,
    this.currencySymbol,
    this.size = 15,
    this.weight = FontWeight.w500,
    this.letterSpacing = -0.03,
    this.showPaise = true,
    this.maxLines = 1,
    this.showSign = false,
    this.color,
    this.textAlign,
  });

  final double amount;
  final String? currencyCode;
  final String? currencySymbol;
  final double size;
  final FontWeight weight;
  final double letterSpacing;

  /// When false, strips the decimal portion for cleaner display.
  final bool showPaise;
  final int maxLines;

  /// When true, prefixes positive amounts with '+'.
  final bool showSign;

  /// Explicit color override. When null, uses semantic credit/debit colors
  /// from [PaisaColors].
  final Color? color;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final paisa = PaisaColors.of(context);
    final formatted = _format();
    final resolvedColor =
        color ?? (amount >= 0 ? paisa.bloomCredit : paisa.bloomDebit);

    return Text(
      formatted,
      style: AppTheme.bloomMono(
        size,
        weight,
        letterSpacing: letterSpacing,
        color: resolvedColor,
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _format() {
    var text = formatSourceAmount(
      amount,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
    );

    if (!showPaise) {
      // Remove only the numeric paise suffix; preserve currency labels.
      text = text.replaceFirst(RegExp(r'\.\d{2}(?=\s|$)'), '');
    }

    if (showSign && amount > 0) {
      text = '+$text';
    }

    return text;
  }
}
