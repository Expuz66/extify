import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Rounded right edge shared by the drawer panel and the drawer itself. Kept
/// subtle so the drawer still reads as an Extify surface rather than a floating
/// card.
const drawerShape = RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(18.0)));

/// Paints the drawer's translucent "glass" background.
///
/// The panel colour is painted by a [Material] and not by a [DecoratedBox]:
/// [ListTile] paints its background and ink splashes on the nearest [Material]
/// ancestor, so a coloured container between the two hides those effects, and
/// Flutter reports "ListTile background color or ink splashes may be invisible"
/// on every rebuild of every affected tile. The [DecoratedBox] below therefore
/// only draws the border (no colour of its own).
///
/// The effect is deliberately restrained: the panel stays clearly darker than
/// the screen behind it and only keeps a faint hint of the content below, which
/// also keeps the text contrast intact.
///
/// The backdrop blur is skipped when the platform asks for reduced motion,
/// which doubles as the cheap fallback on low end devices. A closed drawer is
/// not laid out at all, so no blur is ever rasterised while the drawer is shut.
class DrawerGlassSurface extends StatelessWidget {
  const DrawerGlassSurface({super.key, required this.child});

  final Widget child;

  /// How much of the screen behind the drawer remains visible.
  static const double _panelOpacity = 0.82;

  /// Small sigma: enough to soften what is behind the panel without turning the
  /// backdrop filter into an expensive full-screen effect.
  static const double _blurSigma = 12.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final useBlur = !MediaQuery.disableAnimationsOf(context);

    final panel = Material(
      color: useBlur ? colorScheme.surface.withValues(alpha: _panelOpacity) : colorScheme.surface,
      shape: drawerShape,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: drawerShape.borderRadius,
          border: Border(right: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
        ),
        child: child,
      ),
    );

    if (!useBlur) return panel;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
      child: panel,
    );
  }
}
