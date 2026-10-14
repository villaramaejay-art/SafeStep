import 'package:flutter/material.dart';

/// Fades and slides a list item up into place, staggered by [index], so a
/// freshly loaded list reads as populated one row at a time rather than
/// appearing all at once as a flat block of text.
class StaggeredFadeIn extends StatefulWidget {
  const StaggeredFadeIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Capped so a long list settles quickly rather than trickling in for
    // seconds - past a dozen rows the stagger has already made its point.
    final delay = Duration(milliseconds: 35 * widget.index.clamp(0, 12));
    Future.delayed(delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.06),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
