import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Convenience text widgets using Bloom design system fonts.
///
/// [BloomText.display] renders Space Grotesk for headlines and UI labels.
/// [BloomText.mono] renders IBM Plex Mono for amounts, dates, percentages.
/// [BloomText.body] renders Space Grotesk 400 for readable body copy.
class BloomText extends StatelessWidget {
  const BloomText.display(
    this.text, {
    super.key,
    required this.size,
    this.weight = FontWeight.w600,
    this.letterSpacing = -0.02,
    this.color,
    this.maxLines,
    this.overflow,
    this.textAlign,
  }) : _family = _FontFamily.display;

  const BloomText.mono(
    this.text, {
    super.key,
    required this.size,
    this.weight = FontWeight.w500,
    this.letterSpacing = -0.03,
    this.color,
    this.maxLines,
    this.overflow,
    this.textAlign,
  }) : _family = _FontFamily.mono;

  const BloomText.body(
    this.text, {
    super.key,
    this.size = 14,
    this.weight = FontWeight.w400,
    this.letterSpacing = 0,
    this.color,
    this.maxLines,
    this.overflow,
    this.textAlign,
  }) : _family = _FontFamily.display;

  final String text;
  final double size;
  final FontWeight weight;
  final double letterSpacing;
  final Color? color;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final _FontFamily _family;

  @override
  Widget build(BuildContext context) {
    final style = switch (_family) {
      _FontFamily.display => AppTheme.bloomDisplay(
          size,
          weight,
          letterSpacing: letterSpacing,
          color: color,
        ),
      _FontFamily.mono => AppTheme.bloomMono(
          size,
          weight,
          letterSpacing: letterSpacing,
          color: color,
        ),
    };

    return Text(
      text,
      style: style.copyWith(
        height: _family == _FontFamily.display && weight == FontWeight.w400
            ? 1.5
            : null,
      ),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: true,
    );
  }
}

enum _FontFamily { display, mono }
