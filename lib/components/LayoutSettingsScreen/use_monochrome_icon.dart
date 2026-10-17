import 'package:finamp/l10n/app_localizations.dart';
import 'package:finamp/services/finamp_settings_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UseMonochromeIcon extends ConsumerWidget {
  const UseMonochromeIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile.adaptive(
      title: Text(AppLocalizations.of(context)!.useMonochromeIcon),
      subtitle: Text(AppLocalizations.of(context)!.useMonochromeIconSubtitle),
      value: ref.watch(finampSettingsProvider.useMonochromeIcon),
      onChanged: (value) => FinampSetters.setUseMonochromeIcon(value),
    );
  }
}
