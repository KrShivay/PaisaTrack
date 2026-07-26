import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import '../../theme/paisa_colors.dart';
import 'bloom_motion.dart';

/// Shimmer loading placeholder using the surface/card color.
///
/// Disables the shimmer animation when [MediaQuery.disableAnimations] is true,
/// showing a static tinted rectangle instead.
class BloomSkeleton extends StatefulWidget {
  const BloomSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  /// Width of the skeleton. Defaults to expanding to fill available width.
  final double? width;

  /// Height of the skeleton bar.
  final double height;

  /// Corner radius.
  final double borderRadius;

  @override
  State<BloomSkeleton> createState() => _BloomSkeletonState();
}

class _BloomSkeletonState extends State<BloomSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.bloomShimmer,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = useReduceMotion(context);
    if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    } else if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paisa = PaisaColors.of(context);
    final baseColor = paisa.surfaceCard;
    final reduceMotion = useReduceMotion(context);

    if (reduceMotion) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final shimmerProgress = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2.0 * shimmerProgress, 0),
              end: Alignment(0.0 + 2.0 * shimmerProgress, 0),
              colors: [
                baseColor,
                baseColor.withValues(alpha: 0.4),
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
