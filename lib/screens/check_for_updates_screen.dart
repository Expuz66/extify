import 'dart:io';

import 'package:finamp/components/finamp_app_bar_back_button.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/services/update_installer.dart';
import 'package:finamp/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum _Stage { checking, upToDate, available, downloading, verifying, ready, error, unsupported }

/// Manual, user-driven update flow.
///
/// Nothing here installs anything silently: the download is verified against
/// the checksum GitHub publishes for the asset, the APK's application ID and
/// signing certificate are compared with the installed app, and the actual
/// install is handed to Android's package installer for the user to confirm.
class CheckForUpdatesScreen extends StatefulWidget {
  const CheckForUpdatesScreen({super.key});

  static const routeName = "/check-for-updates";

  @override
  State<CheckForUpdatesScreen> createState() => _CheckForUpdatesScreenState();
}

class _CheckForUpdatesScreenState extends State<CheckForUpdatesScreen> {
  static final _logger = Logger("CheckForUpdates");

  _Stage _stage = _Stage.checking;

  UpdateService? _service;
  InstalledAppInfo? _installed;
  String _installedVersion = '';

  ReleaseInfo? _release;
  File? _downloadedFile;

  String? _errorMessage;
  String? _errorDetail;

  double? _progress;

  bool _canInstallPackages = true;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  Future<void> _initialise() async {
    final packageInfo = await PackageInfo.fromPlatform();
    _installedVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

    if (!UpdateInstaller.isSupported) {
      if (mounted) setState(() => _stage = _Stage.unsupported);
      return;
    }

    try {
      final installed = await UpdateInstaller.installedApp();
      final abis = await UpdateInstaller.supportedAbis();
      if (!mounted) return;

      _installed = installed;
      _service = UpdateService(
        owner: UpdateService.defaultOwner,
        repository: UpdateService.defaultRepository,
        installedVersion: _installedVersion,
        installedPackageName: installed.packageName,
        supportedAbis: abis,
      );

      await _check();
    } catch (e) {
      _logger.warning("Could not prepare the update check", e);
      if (mounted) {
        setState(() {
          _errorMessage = AppLocalizations.of(context)!.updateErrorGeneric(e.toString());
          _errorDetail = null;
          _stage = _Stage.error;
        });
      }
    }
  }

  Future<void> _check() async {
    final service = _service;
    if (service == null) return;

    setState(() {
      _stage = _Stage.checking;
      _errorMessage = null;
      _errorDetail = null;
      _release = null;
      _downloadedFile = null;
      _progress = null;
    });

    final result = await service.checkForUpdates();
    if (!mounted) return;

    switch (result) {
      case UpdateAvailable():
        setState(() {
          _release = result.release;
          _stage = _Stage.available;
        });
      case UpdateUpToDate():
        setState(() => _stage = _Stage.upToDate);
      case UpdateCheckFailed():
        setState(() {
          _errorMessage = _messageForUpdateError(result.error);
          _errorDetail = result.error.detail;
          _stage = _Stage.error;
        });
    }
  }

  String _messageForUpdateError(UpdateException error) {
    final l10n = AppLocalizations.of(context)!;
    return switch (error.kind) {
      UpdateErrorKind.network => l10n.updateErrorNetwork,
      UpdateErrorKind.rateLimit => l10n.updateErrorRateLimit,
      UpdateErrorKind.noReleases => l10n.updateErrorNoReleases,
      UpdateErrorKind.noCompatibleApk => l10n.updateErrorNoCompatibleApk,
      UpdateErrorKind.malformedResponse => l10n.updateErrorGeneric(error.detail ?? error.kind.name),
      UpdateErrorKind.download => l10n.updateErrorGeneric(error.detail ?? error.kind.name),
    };
  }

  Future<void> _download() async {
    final service = _service;
    final release = _release;
    final installed = _installed;
    if (service == null || release == null || installed == null) return;

    _cancelRequested = false;
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _errorMessage = null;
      _errorDetail = null;
    });

    try {
      final directory = await UpdateInstaller.updateDirectory();
      final file = await service.downloadAsset(
        asset: release.asset,
        directory: directory,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => _progress = (total == null || total <= 0) ? null : (received / total).clamp(0.0, 1.0));
        },
        shouldCancel: () => _cancelRequested,
      );

      if (!mounted) return;
      setState(() => _stage = _Stage.verifying);

      // Reject anything that is not exactly the published Extify APK.
      final apk = await UpdateInstaller.inspectApk(file);
      final validation = UpdateInstaller.validate(apk: apk, installed: installed, asset: release.asset);

      if (!validation.isValid) {
        _logger.warning("Rejected downloaded APK: ${validation.problems.map((p) => p.name).join(', ')}");
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // Nothing else to do if the rejected file cannot be removed.
        }
        if (!mounted) return;
        setState(() {
          _errorMessage = _messageForValidationProblem(validation.problems);
          _errorDetail = null;
          _progress = null;
          _stage = _Stage.error;
        });
        return;
      }

      final canInstall = await UpdateInstaller.canRequestPackageInstalls();
      if (!mounted) return;
      setState(() {
        _downloadedFile = file;
        _progress = null;
        _canInstallPackages = canInstall;
        _stage = _Stage.ready;
      });
    } on UpdateException catch (e) {
      if (_cancelRequested) {
        // The user cancelled; that is not an error.
        _logger.info("Update download cancelled by the user");
        if (!mounted) return;
        setState(() {
          _progress = null;
          _stage = _Stage.available;
        });
        return;
      }
      _logger.warning("Update download failed", e);
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageForUpdateError(e);
        _errorDetail = e.detail;
        _progress = null;
        _stage = _Stage.error;
      });
    } catch (e) {
      _logger.warning("Unexpected update download failure", e);
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.updateErrorGeneric(e.toString());
        _errorDetail = null;
        _progress = null;
        _stage = _Stage.error;
      });
    }
  }

  String _messageForValidationProblem(List<ApkValidationProblem> problems) {
    final l10n = AppLocalizations.of(context)!;
    if (problems.contains(ApkValidationProblem.signatureMismatch)) return l10n.updateErrorSignatureMismatch;
    if (problems.contains(ApkValidationProblem.packageMismatch)) return l10n.updateErrorPackageMismatch;
    if (problems.contains(ApkValidationProblem.checksumMismatch)) return l10n.updateErrorChecksumMismatch;
    if (problems.contains(ApkValidationProblem.sizeMismatch)) return l10n.updateErrorChecksumMismatch;
    return l10n.updateErrorGeneric(problems.map((p) => p.name).join(', '));
  }

  Future<void> _install() async {
    final file = _downloadedFile;
    if (file == null) return;

    // Android wants explicit consent before an app may install packages.
    if (!_canInstallPackages) {
      final granted = await UpdateInstaller.requestPackageInstallPermission();
      if (!mounted) return;
      setState(() => _canInstallPackages = granted);
    }

    try {
      await UpdateInstaller.installApk(file);
    } catch (e) {
      _logger.warning("Could not open the package installer", e);
      if (!mounted) return;
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.updateErrorGeneric(e.toString());
        _errorDetail = null;
        _stage = _Stage.error;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  /// ISO date, formatted by hand so a missing/odd `intl` locale cannot throw.
  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.checkForUpdates), leading: const FinampAppBarBackButton()),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 200.0),
        children: [
          ListTile(
            leading: const Icon(TablerIcons.device_mobile),
            title: Text(l10n.finamp),
            subtitle: Text('${l10n.updateInstalledVersion(_installedVersion)}\n${_installed?.packageName ?? ''}'),
          ),
          const Divider(height: 1),
          ..._buildBody(context, theme, l10n),
        ],
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, ThemeData theme, AppLocalizations l10n) {
    switch (_stage) {
      case _Stage.unsupported:
        return [Padding(padding: const EdgeInsets.all(16.0), child: Text(l10n.updateNotSupported))];

      case _Stage.checking:
        return [
          ListTile(
            leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            title: Text(l10n.updateCheckingForUpdates),
          ),
        ];

      case _Stage.upToDate:
        return [
          ListTile(
            leading: Icon(TablerIcons.circle_check, color: theme.colorScheme.primary),
            title: Text(l10n.updateUpToDate),
          ),
          _buildCheckAgainButton(l10n),
        ];

      case _Stage.error:
        return [
          ListTile(
            leading: Icon(TablerIcons.alert_triangle, color: theme.colorScheme.error),
            title: Text(_errorMessage ?? ''),
            subtitle: _errorDetail == null ? null : Text(_errorDetail!),
          ),
          _buildCheckAgainButton(l10n),
        ];

      case _Stage.available:
        final release = _release!;
        return [
          ListTile(
            leading: Icon(TablerIcons.download, color: theme.colorScheme.primary),
            title: Text(l10n.updateAvailableMessage(release.version.toString())),
            subtitle: Text(
              [
                if (release.name != null && release.name!.isNotEmpty) release.name!,
                l10n.updateLatestVersion(release.version.toString()),
                if (release.publishedAt != null) _formatDate(release.publishedAt!),
              ].join('\n'),
            ),
          ),
          ListTile(
            leading: const Icon(TablerIcons.package),
            title: Text(release.asset.name),
            subtitle: Text(_formatBytes(release.asset.size)),
          ),
          if (release.releaseNotes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
              child: Text(l10n.updateReleaseNotes, style: theme.textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(release.releaseNotes, style: theme.textTheme.bodySmall),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: FilledButton.icon(
              onPressed: _download,
              icon: const Icon(TablerIcons.download),
              label: Text(l10n.updateDownloadButton),
            ),
          ),
        ];

      case _Stage.downloading:
        final release = _release!;
        final percent = _progress == null ? null : (_progress! * 100).round();
        return [
          ListTile(
            leading: const Icon(TablerIcons.download),
            title: Text(percent == null ? release.asset.name : l10n.updateDownloadingProgress(percent)),
            subtitle: Text(_formatBytes(release.asset.size)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: LinearProgressIndicator(value: _progress),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: OutlinedButton(
              onPressed: () => setState(() => _cancelRequested = true),
              child: Text(l10n.updateCancelButton),
            ),
          ),
        ];

      case _Stage.verifying:
        return [
          ListTile(
            leading: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            title: Text(l10n.updateVerifyingDownload),
          ),
        ];

      case _Stage.ready:
        return [
          ListTile(
            leading: Icon(TablerIcons.circle_check, color: theme.colorScheme.primary),
            title: Text(l10n.updateReadyToInstall),
            subtitle: _downloadedFile == null ? null : Text(_downloadedFile!.path.split(Platform.pathSeparator).last),
          ),
          if (!_canInstallPackages)
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 12.0),
              child: Text(l10n.updateUnknownSourcesNotice, style: theme.textTheme.bodySmall),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: FilledButton.icon(
              onPressed: _install,
              icon: const Icon(TablerIcons.download),
              label: Text(l10n.updateInstallButton),
            ),
          ),
        ];
    }
  }

  Widget _buildCheckAgainButton(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
    child: OutlinedButton.icon(
      onPressed: _check,
      icon: const Icon(TablerIcons.refresh),
      label: Text(l10n.updateCheckAgainButton),
    ),
  );
}
