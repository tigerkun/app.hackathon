import 'package:flutter/material.dart';

class AnimatedEntry extends StatefulWidget {
  final Widget child;
  final int delay;

  const AnimatedEntry({
    super.key,
    required this.child,
    this.delay = 0,
  });

  @override
  State<AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<AnimatedEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController controller;
  late Animation<double> fade;
  late Animation<Offset> slide;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    fade = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(fade);

    if (widget.delay == 0) {
      controller.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) {
          controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: widget.child),
    );
  }
}
