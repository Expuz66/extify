import 'dart:io';
import 'dart:math';

import 'package:finamp/components/HomeScreen/finamp_music_screen_header.dart';
import 'package:finamp/components/MusicScreen/drawer_glass_surface.dart';
import 'package:finamp/components/MusicScreen/offline_mode_status_label.dart';
import 'package:finamp/components/MusicScreen/offline_mode_switch_list_tile.dart';
import 'package:finamp/components/finamp_icon.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/screens/downloads_screen.dart';
import 'package:finamp/screens/logs_screen.dart';
import 'package:finamp/screens/playback_history_screen.dart';
import 'package:finamp/screens/queue_restore_screen.dart';
import 'package:finamp/screens/settings_screen.dart';
import 'package:finamp/services/downloads_service.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/finamp_user_helper.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../extensions/localizations.dart';

class MusicScreenDrawer extends ConsumerWidget {
  const MusicScreenDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadsService = GetIt.instance<DownloadsService>();
    final colorScheme = ColorScheme.of(context);
    final FinampSettings? settings = ref.watch(finampSettingsProvider).value;
    final appName = ref.watch(packageNameProvider).valueOrNull ?? AppLocalizations.of(context)!.finamp;
    // Comes from the installed package metadata (pubspec `version:`), not from
    // the Jellyfin server.
    final appVersion = ref.watch(packageVersionProvider).valueOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = min(304.0, constraints.maxWidth * .70);
        final excessWidth = constraints.maxWidth - minWidth;
        final expandedWidth = minWidth + excessWidth * 0.5;
        final targetWidth = min(expandedWidth, 450.0);
        return Drawer(
          // [DrawerGlassSurface] paints the visible background on its own
          // Material, so ListTile ink and tile colours stay visible while this
          // drawer's own material stays invisible and shadow-free. The shape is
          // kept here so the backdrop blur is clipped to the rounded corners.
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: drawerShape,
          clipBehavior: Clip.antiAlias,
          width: targetWidth,
          child: DrawerGlassSurface(
            child: SafeArea(
              bottom: false,
              child: ListTileTheme(
                // Shrink trailing padding from 24 to 8
                contentPadding: const EdgeInsetsDirectional.only(start: 16.0, end: 8.0),
                // Manually handle padding in leading/trailing icons
                horizontalTitleGap: 0,
                child: CustomScrollView(
                  slivers: [
                    SliverList(
                      delegate: SliverChildListDelegate.fixed([
                        Padding(
                          padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 20.0, bottom: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              FinampIcon(
                                56,
                                56,
                                overrideColor: (settings?.isOffline ?? false)
                                    ? TextTheme.of(context).bodyMedium?.color?.withValues(alpha: 0.6)
                                    : null,
                              ),
                              const SizedBox(height: 8),
                              Text(appName, style: const TextStyle(fontSize: 20.0)),
                              if (appVersion != null)
                                Text(
                                  "v$appVersion",
                                  style: TextStyle(fontSize: 13.0, color: colorScheme.onSurfaceVariant),
                                ),
                              if (settings?.isOffline ?? false) ...[
                                const SizedBox(height: 4),
                                Text(
                                  AppLocalizations.of(context)!.offlineMode,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ],
                              if (ref.watch(isDownloadingOrSyncingPollingProvider)) ...[
                                const SizedBox(height: 8),
                                Text(
                                  context.l10n.connectionStateInfoString(
                                    ((ref.watch(FinampUserHelper.finampCurrentUserProvider)?.isLocal ?? false)
                                            ? switch (true) {
                                                _ when downloadsService.syncBuffer.isRunning =>
                                                  ConnectionStateInfo.syncingLocal,
                                                _ when downloadsService.downloadTaskQueue.isRunning =>
                                                  ConnectionStateInfo.downloadingLocal,
                                                _ when downloadsService.deleteBuffer.isRunning =>
                                                  ConnectionStateInfo.deleting,
                                                _ => ConnectionStateInfo.connectedLocal,
                                              }
                                            : switch (true) {
                                                _ when downloadsService.syncBuffer.isRunning =>
                                                  ConnectionStateInfo.syncing,
                                                _ when downloadsService.downloadTaskQueue.isRunning =>
                                                  ConnectionStateInfo.downloading,
                                                _ when downloadsService.deleteBuffer.isRunning =>
                                                  ConnectionStateInfo.deleting,
                                                _ => ConnectionStateInfo.other,
                                              })
                                        .name,
                                  ),
                                  style: const TextStyle(fontStyle: FontStyle.italic),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const OfflineModeSwitchListTile(),
                        const OfflineModeStatusLabel(),
                        ListTile(
                          leading: const Padding(
                            padding: EdgeInsets.only(left: 2.0, right: 12.0),
                            child: Icon(Icons.file_download, size: 20.0),
                          ),
                          title: Text(AppLocalizations.of(context)!.downloads, style: TextStyle(fontSize: 15.0)),
                          onTap: () => Navigator.of(context).pushNamed(DownloadsScreen.routeName),
                          dense: true,
                        ),
                        ListTile(
                          leading: const Padding(
                            padding: EdgeInsets.only(left: 2.0, right: 12.0),
                            child: Icon(TablerIcons.clock, size: 20.0),
                          ),
                          title: Text(AppLocalizations.of(context)!.playbackHistory, style: TextStyle(fontSize: 15.0)),
                          onTap: () => Navigator.of(context).pushNamed(PlaybackHistoryScreen.routeName),
                          dense: true,
                        ),
                        ListTile(
                          leading: const Padding(
                            padding: EdgeInsets.only(left: 2.0, right: 12.0),
                            child: Icon(Icons.auto_delete, size: 20.0),
                          ),
                          title: Text(AppLocalizations.of(context)!.queuesScreen, style: TextStyle(fontSize: 15.0)),
                          onTap: () => Navigator.of(context).pushNamed(QueueRestoreScreen.routeName),
                          dense: true,
                        ),
                      ]),
                    ),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: SafeArea(
                        bottom: true,
                        top: false,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Divider(height: 1.0, indent: 16.0, endIndent: 16.0),
                              ListTile(
                                leading: const Padding(
                                  padding: EdgeInsets.only(left: 2.0, right: 12.0),
                                  child: Icon(Icons.warning, size: 20.0),
                                ),
                                title: Text(AppLocalizations.of(context)!.logs, style: TextStyle(fontSize: 15.0)),
                                onTap: () => Navigator.of(context).pushNamed(LogsScreen.routeName),
                                dense: true,
                              ),
                              ListTile(
                                leading: const Padding(
                                  padding: EdgeInsets.only(left: 2.0, right: 12.0),
                                  child: Icon(Icons.settings, size: 20.0),
                                ),
                                title: Text(AppLocalizations.of(context)!.settings, style: TextStyle(fontSize: 15.0)),
                                onTap: () => Navigator.of(context).pushNamed(SettingsScreen.routeName),
                                dense: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final packageNameProvider = FutureProvider((Ref ref) async {
  final info = await PackageInfo.fromPlatform();
  if (Platform.isLinux) {
    return info.appName.capitalize;
  }
  return info.appName;
});

/// Version name of the installed app, as reported by the platform.
final packageVersionProvider = FutureProvider((Ref ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

enum ConnectionStateInfo { syncing, downloading, deleting, connectedLocal, syncingLocal, downloadingLocal, other }
