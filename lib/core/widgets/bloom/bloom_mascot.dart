import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';
import 'bloom_motion.dart';

/// The PaisaTrack Bloom mascot — two white dots on a violet gradient circle.
///
/// Sizes used in the design: 36px (header), 92px (onboarding/completion).
/// Optionally bobs (3s ease-in-out translateY 0→-4px) and shows a pulsing
/// ring border. Both animations respect [MediaQuery.disableAnimations].
class BloomMascot extends StatefulWidget {
  const BloomMascot({
    super.key,
    this.size = 36,
    this.bob = true,
    this.pulseRing = false,
    this.borderRadius,
  });

  /// Diameter of the mascot circle.
  final double size;

  /// Whether the mascot bobs vertically. Disabled when reduce-motion is on.
  final bool bob;

  /// Whether a pulsing ring border animates outward.
  final bool pulseRing;

  /// Custom border radius. Defaults to half the [size] for a circle.
  /// At 92px, the design uses radius 34.
  final double? borderRadius;

  @override
  State<BloomMascot> createState() => _BloomMascotState();
}

class _BloomMascotState extends State<BloomMascot>
    with TickerProviderStateMixin {
  AnimationController? _bobController;
  AnimationController? _pulseController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = useReduceMotion(context);

    _setupBob(reduceMotion);
    _setupPulse(reduceMotion);
  }

  void _setupBob(bool reduceMotion) {
    if (widget.bob && !reduceMotion) {
      _bobController ??= AnimationController(
        vsync: this,
        duration: AppDurations.bloomMascotBob,
      )..repeat(reverse: true);
    } else {
      _bobController?.dispose();
      _bobController = null;
    }
  }

  void _setupPulse(bool reduceMotion) {
    if (widget.pulseRing && !reduceMotion) {
      _pulseController ??= AnimationController(
        vsync: this,
        duration: AppDurations.bloomAskOrbPulse,
      )..repeat();
    } else {
      _pulseController?.dispose();
      _pulseController = null;
    }
  }

  @override
  void dispose() {
    _bobController?.dispose();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? widget.size / 2;

    Widget mascot = _MascotBody(size: widget.size, borderRadius: radius);

    if (widget.pulseRing && _pulseController != null) {
      mascot = _PulseRingWrapper(
        controller: _pulseController!,
        size: widget.size,
        borderRadius: radius,
        child: mascot,
      );
    }

    if (_bobController != null) {
      mascot = AnimatedBuilder(
        animation: _bobController!,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_bobController!.value);
          return Transform.translate(
            offset: Offset(0, -4 * t),
            child: child,
          );
        },
        child: mascot,
      );
    }

    final extra = widget.pulseRing ? 16.0 : 0.0;
    return SizedBox(
      width: widget.size + extra,
      height: widget.size + extra,
      child: Center(child: mascot),
    );
  }
}

class _MascotBody extends StatelessWidget {
  const _MascotBody({required this.size, required this.borderRadius});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    // Eye sizing proportional to mascot: 92px → 9px dots / 9px gap.
    final eyeSize = size * 0.098;
    final eyeGap = size * 0.098;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: AppColorTokens.bloomOnboardingGradient,
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Eye(size: eyeSize),
            SizedBox(width: eyeGap),
            _Eye(size: eyeSize),
          ],
        ),
      ),
    );
  }
}

class _Eye extends StatelessWidget {
  const _Eye({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
    );
  }
}

class _PulseRingWrapper extends StatelessWidget {
  const _PulseRingWrapper({
    required this.controller,
    required this.size,
    required this.borderRadius,
    required this.child,
  });

  final AnimationController controller;
  final double size;
  final double borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, childWidget) {
        final t = controller.value;
        final scale = 1.0 + (0.4 * t);
        final opacity = (0.45 * (1 - t)).clamp(0.0, 1.0);

        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: scale,
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: opacity),
                    width: 2,
                  ),
                ),
              ),
            ),
            childWidget!,
          ],
        );
      },
      child: child,
    );
  }
}
