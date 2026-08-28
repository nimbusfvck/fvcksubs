import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A tappable, focusable surface used for cards. On hover or keyboard/remote
/// focus it shows a ring around the card — instead of the flat overlay tint
/// [InkWell] draws by default — which reads better once the card is mostly
/// covered by artwork.
class Clickable extends StatefulWidget {
  const Clickable({
    super.key,
    required this.child,
    this.onTap,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.onFocusChange,
    this.borderRadius,
    this.color = AppColors.surfaceDarkElevated,
    this.ringColor = AppColors.brandAccent,
    this.innerRingColor = AppColors.surfaceDark,
  });

  final Widget child;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool canRequestFocus;
  final ValueChanged<bool>? onFocusChange;

  /// Corner radius for the fill, clip, and ring. Defaults to [AppRadius.lg].
  final BorderRadius? borderRadius;

  /// Fill color behind [child].
  final Color color;

  /// Color of the ring shown on hover/focus.
  final Color ringColor;

  /// Color of the thin gap between the card edge and the ring — should
  /// match whatever surface the card sits on.
  final Color innerRingColor;

  /// How far the hover/focus ring bleeds beyond the card's own bounds.
  /// Containers that clip tightly around a card (e.g. a fixed-height
  /// horizontal shelf) need to reserve this much extra room on every side,
  /// or the ring gets cut off.
  static const double ringBleed = 4.0;

  @override
  State<Clickable> createState() => _ClickableState();
}

class _ClickableState extends State<Clickable> {
  static const _ringDuration = Duration(milliseconds: 120);
  static const _ringSpread = Clickable.ringBleed;
  static const _innerRingSpread = 2.0;

  bool _hovered = false;
  bool _focused = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused != value) setState(() => _focused = value);
    widget.onFocusChange?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;
    final showRing = isEnabled && (_hovered || _focused);
    final radius = widget.borderRadius ?? AppRadius.lg;

    return AnimatedContainer(
      duration: _ringDuration,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: showRing
            ? [
                BoxShadow(color: widget.ringColor, spreadRadius: _ringSpread),
                BoxShadow(
                  color: widget.innerRingColor,
                  spreadRadius: _innerRingSpread,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          color: widget.color,
          child: InkWell(
            onTap: widget.onTap,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            canRequestFocus: widget.canRequestFocus,
            onFocusChange: _setFocused,
            onHover: _setHovered,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            mouseCursor: isEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
