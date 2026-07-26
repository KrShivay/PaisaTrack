import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/category_visuals.dart';

/// A rounded-rect tile showing a category icon on a category-tinted background.
///
/// On light surfaces, the background uses 15% alpha of the category hue with
/// a darker icon color variant. On dark surfaces, 18% alpha with full-strength
/// hue for the icon.
class BloomCategoryTile extends StatelessWidget {
  const BloomCategoryTile({
    super.key,
    required this.categoryId,
    this.iconName,
    this.size = 36,
    this.borderRadius,
    this.iconSize,
  });

  /// Seed category ID (e.g. 'food_dining'). Drives the hue lookup.
  final String? categoryId;

  /// Optional icon name override. Defaults to the icon mapped from
  /// [CategoryVisuals.icon] for the category.
  final String? iconName;

  /// Tile dimensions (square).
  final double size;

  /// Corner radius. Defaults to [AppRadius.bloomIconTile] (13).
  final double? borderRadius;

  /// Icon size. Defaults to size * 0.5.
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hue = CategoryVisuals.color(categoryId);
    final icon = CategoryVisuals.icon(iconName);
    final radius = borderRadius ?? AppRadius.bloomIconTile;
    final iSize = iconSize ?? size * 0.5;

    final bgAlpha = isDark ? 0.18 : 0.15;
    final bgColor = hue.withValues(alpha: bgAlpha);

    // On dark: full-strength hue. On light: a darker variant.
    final iconColor = isDark ? hue : _darkenForLight(hue);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Icon(
          icon,
          size: iSize,
          color: iconColor,
        ),
      ),
    );
  }

  /// Darkens a color for better contrast on light backgrounds.
  ///
  /// Reduces lightness by ~25% in HSL space, similar to the design's
  /// approach of using darker icon variants on light surfaces.
  static Color _darkenForLight(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness * 0.65).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 1.1).clamp(0.0, 1.0))
        .toColor();
  }
}
