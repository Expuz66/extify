import 'package:finamp/components/global_snackbar.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/menus/components/menuEntries/menu_entry.dart';
import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/screens/playlist_edit_screen.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:finamp/services/permission_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

class EditItemMenuEntry extends ConsumerWidget implements HideableMenuEntry {
  final BaseItemDto baseItem;

  const EditItemMenuEntry({super.key, required this.baseItem});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemIsEditable = [BaseItemDtoType.playlist].contains(BaseItemDtoType.fromItem(baseItem));
    return Visibility(
      visible: itemIsEditable && !ref.watch(finampSettingsProvider.isOffline),
      child: MenuEntry(
        enabled: ref.watch(canDeleteFromServerProvider(baseItem)),
        icon: TablerIcons.edit,
        title: AppLocalizations.of(context)!.editItemTitle(BaseItemDtoType.fromItem(baseItem).name),
        onTap: () {
          Navigator.pop(context); // close menu
          switch (BaseItemDtoType.fromItem(baseItem)) {
            case BaseItemDtoType.playlist:
              Navigator.pushNamed(context, PlaylistEditScreen.routeName, arguments: baseItem);
              break;
            default:
              GlobalSnackbar.message((context) => AppLocalizations.of(context)!.notImplementedYet);
          }
        },
      ),
    );
  }

  @override
  bool get isVisible =>
      !FinampSettingsHelper.finampSettings.isOffline &&
      [BaseItemDtoType.playlist].contains(BaseItemDtoType.fromItem(baseItem));
}
