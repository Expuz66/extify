import 'package:finamp/components/MusicScreen/drawer_glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] under a [Material] ancestor (as the drawer does) and collects
/// every error the framework reports instead of letting the first one fail the
/// test.
///
/// This is needed because ListTile's "background color or ink splashes may be
/// invisible" check calls [FlutterError.reportError] without throwing, so it
/// never shows up as a caught exception.
Future<List<FlutterErrorDetails>> pumpCollectingReportedErrors(WidgetTester tester, Widget child) async {
  final errors = <FlutterErrorDetails>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = errors.add;
  try {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  } finally {
    FlutterError.onError = previousOnError;
  }
  return errors;
}

Material panelMaterial(WidgetTester tester) =>
    tester.widget<Material>(find.descendant(of: find.byType(DrawerGlassSurface), matching: find.byType(Material)));

void main() {
  // Control case: proves the debug check is actually active in this
  // environment, otherwise the "no errors" expectation below would pass even if
  // the pattern that hides ListTile ink came back.
  testWidgets('control: a coloured DecoratedBox around a ListTile is reported', (tester) async {
    final errors = await pumpCollectingReportedErrors(
      tester,
      Material(
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xFF33221C)),
          child: ListTile(title: const Text('Settings'), onTap: () {}),
        ),
      ),
    );

    expect(errors, isNotEmpty);
    expect(errors.first.exception.toString(), contains('may be invisible'));
  });

  testWidgets('DrawerGlassSurface keeps ListTile ink and background visible', (tester) async {
    final errors = await pumpCollectingReportedErrors(
      tester,
      Material(
        child: DrawerGlassSurface(
          child: ListTile(title: const Text('Settings'), onTap: () {}),
        ),
      ),
    );

    expect(errors, isEmpty);
  });

  testWidgets('the panel colour lives on the Material, not on the DecoratedBox', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DrawerGlassSurface(child: SizedBox())),
      ),
    );

    final material = panelMaterial(tester);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(of: find.byType(DrawerGlassSurface), matching: find.byType(DecoratedBox)),
                )
                .decoration
            as BoxDecoration;
    final surface = Theme.of(tester.element(find.byType(DrawerGlassSurface))).colorScheme.surface;

    expect(decoration.color, isNull, reason: 'a colour here is what hides ListTile ink splashes');
    expect(material.color, isNotNull);
    expect(material.color!.r, surface.r);
    expect(material.color!.g, surface.g);
    expect(material.color!.b, surface.b);
    expect(material.color!.a, closeTo(0.20, 0.001), reason: '80 % transparency is the design target for the glass');
    expect(material.color!.a, lessThan(0.5), reason: 'the screen behind must stay visible');
    expect(material.shape, drawerShape);
    expect(find.descendant(of: find.byType(DrawerGlassSurface), matching: find.byType(BackdropFilter)), findsOneWidget);
  });

  testWidgets('the glass keeps a backdrop blur', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DrawerGlassSurface(child: SizedBox())),
      ),
    );

    final filter = tester
        .widget<BackdropFilter>(
          find.descendant(of: find.byType(DrawerGlassSurface), matching: find.byType(BackdropFilter)),
        )
        .filter;

    expect(filter.toString(), contains('blur'));
  });

  testWidgets('reduced motion falls back to a thicker veil without a backdrop blur', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const Scaffold(body: DrawerGlassSurface(child: SizedBox())),
          ),
        ),
      ),
    );

    expect(find.descendant(of: find.byType(DrawerGlassSurface), matching: find.byType(BackdropFilter)), findsNothing);
    expect(
      panelMaterial(tester).color!.a,
      closeTo(0.78, 0.001),
      reason: 'without the blur the unsharp backdrop needs the thicker veil',
    );
    expect(panelMaterial(tester).color!.a, lessThan(1.0), reason: 'still hinting at the screen behind');
  });
}
