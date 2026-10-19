import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../l10n/app_localizations.dart';
import '../services/update_service.dart';

/// True while an "Update available" dialog is on screen. The startup check is
/// driven by widget lifecycle events, which can fire again while the dialog is
/// still open; this keeps a second copy from being stacked on top.
bool _dialogVisible = false;

/// Shows the "Update available" dialog for [release].
///
/// Returns `true` only when the user chose "Update now". "Later" and dismissing
/// the dialog (tapping outside or the system back gesture) both return `false`,
/// so the caller can remember the release as dismissed in either case. Returns
/// `null` when a dialog was already on screen: nothing was asked, so nothing may
/// be remembered either.
///
/// Nothing here downloads or installs anything: the caller hands the work to the
/// verified download flow.
Future<bool?> showUpdateAvailableDialog(
  BuildContext context, {
  required ReleaseInfo release,
  required String installedVersion,
}) async {
  if (_dialogVisible) return null;
  _dialogVisible = true;
  try {
    final choice = await showDialog<bool>(
      context: context,
      builder: (context) => UpdateAvailableDialog(release: release, installedVersion: installedVersion),
    );
    return choice ?? false;
  } finally {
    _dialogVisible = false;
  }
}

/// Extify themed "Update available" dialog.
///
/// Everything shown is taken from the release the GitHub API returned: the
/// version, the changelog body and the publication date. Nothing is hardcoded.
/// The panel uses [ColorScheme.surface] with a hairline border, so on the AMOLED
/// scheme it stays pure black instead of the grey Material default.
///
/// The dialog scrolls as a whole ([AlertDialog.scrollable]), which is what keeps
/// a long changelog readable on a small screen without clipping the buttons.
class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({super.key, required this.release, required this.installedVersion});

  /// The newer release, as returned by [UpdateService.checkForUpdates].
  final ReleaseInfo release;

  /// Version name of the installed build, e.g. `1.0.2`.
  final String installedVersion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final notes = formatReleaseNotesForDisplay(release.releaseNotes);
    final newVersion = release.version.toString();

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      scrollable: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.0),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      titlePadding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0.0),
      contentPadding: const EdgeInsets.fromLTRB(24.0, 14.0, 24.0, 0.0),
      actionsPadding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 10.0),
      title: Row(
        children: [
          Icon(TablerIcons.download, size: 22.0, color: colorScheme.primary),
          const SizedBox(width: 10.0),
          Expanded(
            child: Text(
              l10n.updateDialogTitle,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: l10n.updateDialogCurrentVersion, value: 'v$installedVersion'),
            _InfoRow(label: l10n.updateDialogNewVersion, value: 'v$newVersion', emphasise: true),
            if (release.publishedAt != null)
              _InfoRow(label: l10n.updateDialogPublished, value: formatReleaseDate(release.publishedAt!)),
            const SizedBox(height: 18.0),
            Text(l10n.updateDialogChangelog, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6.0),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: SelectableText(
                  notes.isEmpty ? l10n.updateDialogNoChangelog : notes,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface, height: 1.35),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.updateDialogLater)),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(TablerIcons.download),
          label: Text(l10n.updateDialogUpdateNow),
        ),
      ],
    );
  }
}

/// One `label` + `value` row inside the dialog.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.emphasise = false});

  final String label;
  final String value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132.0,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasise ? FontWeight.w700 : FontWeight.w500,
                color: emphasise ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ISO `yyyy-MM-dd` in local time, formatted by hand so a missing locale cannot
/// throw. Matches the format used by the manual update screen.
String formatReleaseDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// Turns a GitHub release body into plain text for the dialog.
///
/// Deliberately conservative: it only rewrites the markdown that would otherwise
/// show up as literal noise (headings, `**bold**`, `__bold__`, list markers) and
/// leaves links, code spans and emoji alone, so a real changelog is never
/// mangled. Also collapses runs of blank lines so Markdown's paragraph spacing
/// does not turn into a wall of white space.
String formatReleaseNotesForDisplay(String raw) {
  if (raw.trim().isEmpty) return '';

  final heading = RegExp(r'^\s{0,3}#{1,6}\s+(.*)$');
  final bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
  final boldStars = RegExp(r'\*\*(.+?)\*\*');
  final boldUnderscores = RegExp(r'__(.+?)__');

  final lines = <String>[];
  var blankRun = 0;

  for (final raw in raw.replaceAll('\r\n', '\n').split('\n')) {
    var line = raw.trimRight();

    final headingMatch = heading.firstMatch(line);
    if (headingMatch != null) line = headingMatch.group(1)!.trim();

    final bulletMatch = bullet.firstMatch(line);
    if (bulletMatch != null) line = '${bulletMatch.group(1)}• ${bulletMatch.group(2)}';

    line = line
        .replaceAllMapped(boldStars, (match) => match.group(1)!)
        .replaceAllMapped(boldUnderscores, (match) => match.group(1)!);

    if (line.trim().isEmpty) {
      blankRun++;
      if (blankRun > 1) continue;
      lines.add('');
    } else {
      blankRun = 0;
      lines.add(line);
    }
  }

  return lines.join('\n').trim();
}
