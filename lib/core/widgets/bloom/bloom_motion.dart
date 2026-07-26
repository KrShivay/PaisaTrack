import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Returns true when the platform requests reduced motion.
///
/// Animations larger than opacity/color transitions should check this and
/// fall back to static states.
bool useReduceMotion(BuildContext context) {
  return MediaQuery.of(context).disableAnimations;
}

/// 3s ease-in-out bob: translateY 0 → -4px, infinite.
///
/// Used by the Bloom mascot. Returns null when reduce-motion is active.
class BloomBobController {
  BloomBobController(TickerProvider vsync)
      : controller = AnimationController(
          vsync: vsync,
          duration: AppDurations.bloomMascotBob,
        ),
        animation = CurvedAnimation(
          parent: AnimationController(
            vsync: vsync,
            duration: AppDurations.bloomMascotBob,
          ),
          curve: Curves.easeInOut,
        ) {
    // Re-create with the same controller.
    animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    );
    controller.repeat(reverse: true);
  }

  final AnimationController controller;
  late CurvedAnimation animation;

  void dispose() {
    animation.dispose();
    controller.dispose();
  }
}

/// Ask orb pulse ring: scale 1 → 1.4, opacity 0.55 → 0, 2.6s ease-out.
class BloomPulseRingController {
  BloomPulseRingController(TickerProvider vsync)
      : controller = AnimationController(
          vsync: vsync,
          duration: AppDurations.bloomAskOrbPulse,
        ) {
    controller.repeat();
  }

  final AnimationController controller;

  double get scale => 1.0 + (0.4 * controller.value);
  double get opacity => (0.55 * (1 - controller.value)).clamp(0.0, 1.0);

  void dispose() => controller.dispose();
}

/// Streak pop: 1.0 → 1.12 → 1.0 at 400ms.
class BloomStreakPopController {
  BloomStreakPopController(TickerProvider vsync)
      : controller = AnimationController(
          vsync: vsync,
          duration: AppDurations.bloomStreakPop,
        ),
        animation = CurvedAnimation(
          parent: AnimationController(
            vsync: vsync,
            duration: AppDurations.bloomStreakPop,
          ),
          curve: Curves.easeOut,
        ) {
    animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOut,
    );
  }

  final AnimationController controller;
  late CurvedAnimation animation;

  /// Runs the pop once. Returns a Future that completes when the pop is done.
  Future<void> pop() async {
    controller.reset();
    await controller.forward();
  }

  /// The scale value: 1.0 → 1.12 (halfway) → 1.0.
  double get scale {
    final t = animation.value;
    // Parabolic curve peaking at t=0.5.
    return 1.0 + 0.12 * (1 - (2 * t - 1) * (2 * t - 1));
  }

  void dispose() {
    animation.dispose();
    controller.dispose();
  }
}

/// Wraps a child with a bob animation that translates it vertically.
///
/// No-ops when reduce-motion is active.
class BloomBobWrapper extends StatefulWidget {
  const BloomBobWrapper({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  State<BloomBobWrapper> createState() => _BloomBobWrapperState();
}

class _BloomBobWrapperState extends State<BloomBobWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.bloomMascotBob,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate = widget.enabled && !useReduceMotion(context);
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || useReduceMotion(context)) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.translate(
          offset: Offset(0, -4 * t),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
