import 'package:flutter/material.dart';

import '../../core/design/shapes.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/json_util.dart';
import 'pressable.dart';

/// Rounded surface with a soft shadow. The basic building block of the UI.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Radii.lg,
    this.onTap,
    this.color,
    this.shadow = true,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final bool shadow;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);
    return Container(
      decoration: BoxDecoration(
        color: color ?? c.surfaceRaised,
        borderRadius: r,
        border: border ? Border.all(color: c.border) : null,
        boxShadow: shadow ? softShadow(context) : null,
      ),
      child: onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              borderRadius: r,
              clipBehavior: Clip.antiAlias,
              child: Pressable(onTap: onTap, borderRadius: r, child: content),
            ),
    );
  }
}

/// Square icon on a tinted rounded background.
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.color, this.size = 40});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withAlpha(34),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: tint),
    );
  }
}

/// A card containing rows separated by dividers (menu and settings style).
class GroupedList extends StatelessWidget {
  const GroupedList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SoftCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Column(
          children: <Widget>[
            for (var i = 0; i < children.length; i++) ...<Widget>[
              if (i > 0) Divider(height: 1, indent: 66, color: c.border),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class GroupedRow extends StatelessWidget {
  const GroupedRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Short text shown before the chevron (for example the current language).
  final String? value;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            IconTile(icon: icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: context.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: context.secondary),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Text(value!, style: context.secondary),
              ),
            ?trailing,
            if (onTap != null && trailing == null)
              Icon(
                rtl ? Icons.chevron_left : Icons.chevron_right,
                color: c.textSecondary,
              ),
          ],
        ),
      ),
    );
  }
}

/// Primary call-to-action with an accent gradient and glow.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hsl = HSLColor.fromColor(c.accent);
    final lighter = hsl
        .withLightness(clampDouble(hsl.lightness + 0.09, 0.0, 0.92))
        .toColor();
    final enabled = onPressed != null;
    final r = BorderRadius.circular(Radii.md);
    final button = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[lighter, c.accent],
          ),
          borderRadius: r,
          boxShadow: enabled
              ? <BoxShadow>[
                  BoxShadow(
                    color: c.accent.withAlpha(70),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Pressable(
            borderRadius: r,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: context.body.copyWith(
                        color: c.onAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (icon != null) ...<Widget>[
                    const SizedBox(width: 8),
                    Icon(icon, size: 18, color: c.onAccent),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Pill-shaped tab selector driven by a [TabController].
class PillTabBar extends StatelessWidget {
  const PillTabBar({super.key, required this.controller, required this.labels});

  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: Semantics(
                    button: true,
                    selected: controller.index == i,
                    child: Pressable(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      onTap: () {
                        if (context.pb.reducedMotion) {
                          controller.index = i;
                        } else {
                          controller.animateTo(i);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: controller.index == i
                              ? c.accent.withAlpha(36)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(Radii.pill),
                          border: Border.all(
                            color: controller.index == i ? c.accent : c.border,
                          ),
                        ),
                        child: Text(
                          labels[i],
                          style: context.body.copyWith(
                            fontSize: 13,
                            fontWeight: controller.index == i
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: controller.index == i
                                ? c.accent
                                : c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class NavItem {
  const NavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Floating pill navigation bar. The selected item expands to show its label.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelected,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fast = context.pb.reducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Container(
          height: 64,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: c.border),
            boxShadow: softShadow(context, strength: 1.3),
          ),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < items.length; i++)
                Expanded(
                  flex: i == index ? 3 : 1,
                  child: Tooltip(
                    message: items[i].label,
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: items[i].label,
                      child: Pressable(
                        borderRadius: BorderRadius.circular(Radii.pill),
                        onTap: () => onSelected(i),
                        child: AnimatedContainer(
                          duration: fast,
                          decoration: BoxDecoration(
                            color: i == index ? c.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(Radii.pill),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Icon(
                                i == index
                                    ? items[i].selectedIcon
                                    : items[i].icon,
                                size: 22,
                                color: i == index
                                    ? c.onAccent
                                    : c.textSecondary,
                              ),
                              if (i == index) ...<Widget>[
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    items[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.body.copyWith(
                                      color: c.onAccent,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft accent-coloured glow at the top of a page.
class AccentGlow extends StatelessWidget {
  const AccentGlow({super.key, required this.child, this.height = 280});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    c.accent.withAlpha(dark ? 52 : 28),
                    c.accent.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
