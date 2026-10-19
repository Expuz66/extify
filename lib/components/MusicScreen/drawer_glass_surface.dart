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
/// The panel is a thin veil: 20 % opaque, i.e. 80 % transparent, so the screen
/// behind it stays visible through the blur. The tint is [ColorScheme.surface],
/// which is pure black (0xFF000000) on the AMOLED scheme, so the glass stays
/// dark and elegant instead of washing out. The Scaffold's own drawer scrim
/// ([Colors.black54] by default) sits *below* the panel and already dims what is
/// behind it, so the effective backdrop is about `0.46 x 0.80 = 37 %` of the
/// original brightness - dark enough for [ColorScheme.onSurface] text, list
/// tiles and icons to stay readable.
///
/// The backdrop blur is skipped when the platform asks for reduced motion,
/// which doubles as the cheap fallback on low end devices. Without the blur the
/// content behind stays sharp, so that fallback keeps a thicker veil (22 %
/// transparent) instead of letting the screen compete with the text. A closed
/// drawer is not laid out at all, so no blur is ever rasterised while the
/// drawer is shut.
class DrawerGlassSurface extends StatelessWidget {
  const DrawerGlassSurface({super.key, required this.child});

  final Widget child;

  /// Share of the panel covered by the tint: 0.20 = 80 % transparency, the
  /// design target for the glass.
  static const double _panelOpacity = 0.20;

  /// Panel opacity used when the backdrop is not blurred (reduced motion).
  /// Sharp content behind the panel needs to be pushed back further, so this
  /// fallback is only 22 % transparent.
  static const double _panelOpacityUnblurred = 0.78;

  /// Small sigma: enough to soften what is behind the panel without turning the
  /// backdrop filter into an expensive full-screen effect.
  static const double _blurSigma = 12.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final useBlur = !MediaQuery.disableAnimationsOf(context);

    final panel = Material(
      color: colorScheme.surface.withValues(alpha: useBlur ? _panelOpacity : _panelOpacityUnblurred),
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
