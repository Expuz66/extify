import 'package:finamp/models/finamp_models.dart';
import 'package:finamp/models/jellyfin_models.dart';
import 'package:finamp/screens/playlist_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

class PlaylistEditButton extends StatelessWidget {
  const PlaylistEditButton({super.key, required this.playlist});

  final BaseItemDto playlist;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(TablerIcons.edit),
      tooltip: AppLocalizations.of(context)!.editItemTitle(BaseItemDtoType.fromItem(playlist).name),
      onPressed: () => Navigator.pushNamed(context, PlaylistEditScreen.routeName, arguments: playlist),
    );
  }
}
