import 'package:finamp/components/update_available_dialog.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A release shaped like the one the GitHub API returns for this repository.
ReleaseInfo testRelease({
  String tag = '1.0.3',
  String body = '**Highlights**\n\n- Faster startup\n- Fixed the drawer\n',
  DateTime? publishedAt,
  String name = 'Extify 1.0.3',
}) => ReleaseInfo(
  tagName: tag,
  version: AppVersion.tryParse(tag)!,
  name: name,
  releaseNotes: body,
  htmlUrl: Uri.parse('https://github.com/Expuz66/extify/releases/tag/$tag'),
  // Noon local time, so converting to local cannot shift the calendar day.
  publishedAt: publishedAt ?? DateTime(2026, 10, 18, 12),
  asset: ReleaseAsset(
    name: 'app-arm64-v8a-release.apk',
    size: 12345678,
    downloadUrl: Uri.parse('https://example.test/app-arm64-v8a-release.apk'),
    sha256: 'deadbeef',
  ),
);

Widget host(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

/// Pumps a button that shows the dialog and records what it returned.
Future<ValueNotifier<bool?>> pumpDialogTrigger(WidgetTester tester, ReleaseInfo release) async {
  final choice = ValueNotifier<bool?>(null);
  await tester.pumpWidget(
    host(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            choice.value = await showUpdateAvailableDialog(context, release: release, installedVersion: '1.0.2');
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  return choice;
}

void main() {
  group('release notes formatting', () {
    test('strips markdown noise but keeps the words', () {
      expect(
        formatReleaseNotesForDisplay('## Highlights\n\n**Fast** start\n\n- one\n* two\n'),
        'Highlights\n\nFast start\n\n• one\n• two',
      );
    });

    test('collapses runs of blank lines', () {
      expect(formatReleaseNotesForDisplay('a\n\n\n\nb'), 'a\n\nb');
    });

    test('returns an empty string for an empty body', () {
      expect(formatReleaseNotesForDisplay('   \n  '), '');
    });

    test('leaves links, code spans and underscores alone', () {
      const raw = 'See https://github.com/Expuz66/extify/pull/12 and `some_file_name`';
      expect(formatReleaseNotesForDisplay(raw), raw);
    });

    test('does not mistake a horizontal rule for a bullet', () {
      expect(formatReleaseNotesForDisplay('---'), '---');
    });

    test('handles carriage returns from the API', () {
      expect(formatReleaseNotesForDisplay('a\r\n\r\nb'), 'a\n\nb');
    });
  });

  group('update available dialog', () {
    testWidgets('renders the versions, the date and the changelog from the release', (tester) async {
      await tester.pumpWidget(host(UpdateAvailableDialog(release: testRelease(), installedVersion: '1.0.2')));

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Current version'), findsOneWidget);
      expect(find.text('v1.0.2'), findsOneWidget);
      expect(find.text('New version'), findsOneWidget);
      expect(find.text('v1.0.3'), findsOneWidget);
      expect(find.text('2026-10-18'), findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      expect(find.textContaining('Faster startup'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('omits the publication date when GitHub has none', (tester) async {
      await tester.pumpWidget(
        host(
          UpdateAvailableDialog(
            release: testRelease(publishedAt: DateTime(2026, 10, 18, 12)),
            installedVersion: '1.0.2',
          ),
        ),
      );
      expect(find.text('2026-10-18'), findsOneWidget);

      final noDate = ReleaseInfo(
        tagName: '1.0.3',
        version: const AppVersion(1, 0, 3),
        name: null,
        releaseNotes: 'Nothing to see',
        htmlUrl: Uri.parse('https://example.test'),
        publishedAt: null,
        asset: testRelease().asset,
      );
      await tester.pumpWidget(host(UpdateAvailableDialog(release: noDate, installedVersion: '1.0.2')));
      expect(find.text('Published'), findsNothing);
      expect(find.textContaining('Nothing to see'), findsOneWidget);
    });

    testWidgets('explains an empty changelog instead of showing a blank box', (tester) async {
      await tester.pumpWidget(
        host(
          UpdateAvailableDialog(
            release: testRelease(body: ''),
            installedVersion: '1.0.2',
          ),
        ),
      );
      expect(find.text('This release has no release notes.'), findsOneWidget);
    });

    testWidgets('keeps a long changelog scrollable and the buttons reachable', (tester) async {
      final long = List.generate(120, (index) => '- release note $index').join('\n');
      await tester.pumpWidget(
        host(
          UpdateAvailableDialog(
            release: testRelease(body: long),
            installedVersion: '1.0.2',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(position.maxScrollExtent, greaterThan(0.0), reason: 'a long changelog must scroll');

      await tester.drag(find.byType(Scrollable).first, const Offset(0.0, -240.0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
    });

    testWidgets('does not force scrolling for a short changelog', (tester) async {
      await tester.pumpWidget(
        host(
          UpdateAvailableDialog(
            release: testRelease(body: 'Small fix.'),
            installedVersion: '1.0.2',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent, 0.0);
    });
  });

  group('update available dialog result', () {
    testWidgets('reports "Update now" back to the caller', (tester) async {
      final choice = await pumpDialogTrigger(tester, testRelease());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(choice.value, isTrue);
    });

    testWidgets('reports "Later" back to the caller', (tester) async {
      final choice = await pumpDialogTrigger(tester, testRelease());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(choice.value, isFalse);
    });

    testWidgets('treats a barrier dismissal as "Later"', (tester) async {
      final choice = await pumpDialogTrigger(tester, testRelease());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Outside the dialog panel, still inside the app.
      await tester.tapAt(const Offset(4.0, 4.0));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
      expect(choice.value, isFalse);
    });

    testWidgets('never stacks a second dialog on top of an open one', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (widgetContext) {
              context = widgetContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final first = showUpdateAvailableDialog(context, release: testRelease(), installedVersion: '1.0.2');
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);

      // A second startup check finishes while the dialog is open: it must be
      // ignored rather than stacked, and must not be treated as a choice.
      expect(await showUpdateAvailableDialog(context, release: testRelease(), installedVersion: '1.0.2'), isNull);
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(await first, isFalse);
    });

    testWidgets('shows again once the previous dialog is gone', (tester) async {
      final choice = await pumpDialogTrigger(tester, testRelease());

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(choice.value, isTrue);
    });
  });

  group('asynchronous update notification race conditions', () {
    testWidgets('handles rapid dialog triggering and dismissal without errors', (tester) async {
      final choice = await pumpDialogTrigger(tester, testRelease());

      // Open, close, and open in rapid succession.
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('Later'));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(choice.value, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
