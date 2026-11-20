import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';

/// Tap target built on [GestureDetector] (it replaces every `InkWell`).
///
/// A GestureDetector draws nothing on its own, so this adds the two cues the
/// ink splash used to give: a pointer cursor with a faint hover tint on
/// desktop, and a faint tint while pressed on touch screens. The tint is
/// painted over the child and never changes its size or layout.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    this.circle = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Corner radius of the tint. Null means square corners.
  final BorderRadius? borderRadius;

  /// Round tint (for circular buttons).
  final bool circle;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _set({bool? hover, bool? down}) {
    final h = hover ?? _hover;
    final d = down ?? _down;
    if (h == _hover && d == _down) return;
    setState(() {
      _hover = h;
      _down = d;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return widget.child;
    final accent = context.colors.accent;
    final tint = _down
        ? accent.withAlpha(34)
        : (_hover ? accent.withAlpha(16) : null);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _set(hover: true),
      onExit: (_) => _set(hover: false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _set(down: true),
        onTapUp: (_) => _set(down: false),
        onTapCancel: () => _set(down: false),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            color: tint,
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.circle ? null : widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
