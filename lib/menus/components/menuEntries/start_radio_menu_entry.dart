import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/menus/components/menuEntries/menu_entry.dart';
import 'package:finamp/menus/components/radio_mode_menu.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

class StartRadioMenuEntry extends ConsumerWidget implements HideableMenuEntry {
  final BaseItemDto baseItem;

  const StartRadioMenuEntry({super.key, required this.baseItem});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MenuEntry(
      icon: TablerIcons.radio,
      title: AppLocalizations.of(context)!.startRadio,
      onTap: () async {
        if (context.mounted) {
          Navigator.pop(context);
        }
        await showRadioMenu(context, seedItem: baseItem, startNewQueue: true);
      },
    );
  }

  @override
  bool get isVisible => true;
}
