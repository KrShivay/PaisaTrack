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
    this.size = 15,
    this.weight = FontWeight.w500,
    this.letterSpacing = -0.03,
    this.showPaise = true,
    this.showSign = false,
    this.color,
    this.textAlign,
  });

  final double amount;
  final double size;
  final FontWeight weight;
  final double letterSpacing;

  /// When false, strips the decimal portion for cleaner display.
  final bool showPaise;

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
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _format() {
    var text = formatInr(amount);

    if (!showPaise) {
      // Remove the ".XX" decimal portion.
      final dotIndex = text.lastIndexOf('.');
      if (dotIndex != -1) {
        text = text.substring(0, dotIndex);
      }
    }

    if (showSign && amount > 0) {
      text = '+$text';
    }

    return text;
  }
}
