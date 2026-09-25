import 'dart:ui';

import 'package:flutter/material.dart';

class StaggeredItem extends StatefulWidget {
  final int index;
  final bool stagger;
  final bool enabled;
  final Widget child;

  const StaggeredItem({
    super.key,
    required this.index,
    this.stagger = false,
    this.enabled = true,
    required this.child,
  });

  @override
  State<StaggeredItem> createState() => _StaggeredItemState();
}

class _StaggeredItemState extends State<StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  late final Animation<double> _scale;
  bool _animated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
    ));
    _scale = Tween<double>(begin: 0.98, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    if (!widget.enabled || _reduceMotion) {
      _controller.value = 1.0;
      _animated = true;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _animated) return;
        _animated = true;
        if (widget.stagger) {
          final delay = Duration(
            milliseconds: (widget.index * 40).clamp(0, 400),
          );
          Future.delayed(delay, () {
            if (mounted) _controller.forward();
          });
        } else {
          _controller.forward();
        }
      });
    }
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void didUpdateWidget(covariant StaggeredItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && !_animated) {
      _animated = true;
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(
          scale: _scale,
          child: widget.child,
        ),
      ),
    );
  }
}

class HeaderBlur extends StatelessWidget {
  final Widget? child;

  const HeaderBlur({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final cs = Theme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          height: topPadding + kToolbarHeight + 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.scrim.withValues(alpha: 0.35),
                cs.scrim.withValues(alpha: 0.15),
                Colors.transparent,
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
