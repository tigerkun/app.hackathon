import 'package:flutter/material.dart';

/// Single-shot entrance animation (fade + slight vertical slide) for feed cards
/// and sections. Respects platform disableAnimations accessibility settings.
class FadeSlideEntrance extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final double offsetY;

  const FadeSlideEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 280),
    this.offsetY = 14,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return child;
    }

    final clampedDelayMs = (index.clamp(0, 6)) * 35;
    final effectiveDuration = Duration(milliseconds: duration.inMilliseconds + clampedDelayMs);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: effectiveDuration,
      curve: Curves.easeOutCubic,
      builder: (context, t, builtChild) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - t)),
            child: builtChild,
          ),
        );
      },
      child: child,
    );
  }
}

/// Interactive press-and-pop wrapper for vote chips and safety actions.
class ScaleTapPop extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const ScaleTapPop({
    super.key,
    required this.child,
    this.onTap,
  });

  @override
  State<ScaleTapPop> createState() => _ScaleTapPopState();
}

class _ScaleTapPopState extends State<ScaleTapPop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.92,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _triggerTap() {
    _controller.reverse().then((_) {
      if (mounted) _controller.forward();
    });
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTap == null ? null : _triggerTap,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}

/// Smoothly animates changes to numeric vote tallies and Karma scores.
class AnimatedMetricText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const AnimatedMetricText(
    this.text, {
    super.key,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) {
      return Text(text, style: style);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(animation), child: child),
      ),
      child: Text(
        text,
        key: ValueKey<String>(text),
        style: style,
      ),
    );
  }
}
