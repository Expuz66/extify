import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class ConfirmationPromptDialog extends StatelessWidget {
  const ConfirmationPromptDialog({
    super.key,
    required this.promptText,
    required this.confirmButtonText,
    this.abortButtonText,
    this.onConfirmed,
    this.centerText = false,
  });
  final String promptText;
  final String confirmButtonText;
  final String? abortButtonText;
  final void Function()? onConfirmed;
  final bool centerText;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      buttonPadding: const EdgeInsets.all(0.0),
      contentPadding: const EdgeInsets.all(0.0),
      insetPadding: const EdgeInsets.all(32.0),
      actionsPadding: const EdgeInsets.all(0.0),
      actionsAlignment: MainAxisAlignment.spaceAround,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      actionsOverflowDirection: VerticalDirection.up,
      title: Text(promptText, style: const TextStyle(fontSize: 18), textAlign: centerText ? TextAlign.center : null),
      actions: [
        Container(
          constraints: const BoxConstraints(maxWidth: 150.0),
          child: TextButton(
            child: Text(abortButtonText ?? AppLocalizations.of(context)!.genericCancel, textAlign: TextAlign.center),
            onPressed: () {
              // The widget may be dismissed via the modal instead of the cancel button, so return null to unify behaviors.
              Navigator.of(context).pop(null);
            },
          ),
        ),
        Container(
          constraints: const BoxConstraints(maxWidth: 150.0),
          child: TextButton(
            child: Text(confirmButtonText, textAlign: TextAlign.center, softWrap: true),
            onPressed: () {
              Navigator.of(context).pop(true); // Close the dialog
              onConfirmed?.call();
            },
          ),
        ),
      ],
    );
  }
}
