import 'package:flutter/material.dart';

import 'card_deck.dart';
import 'models.dart';
import 'theme.dart';

/// What the filing sheet came back with.
sealed class AppMenuChoice {
  const AppMenuChoice();
}

/// Take the app off whatever card it is filed under.
class UnfileApp extends AppMenuChoice {
  const UnfileApp();
}

/// Open Android's app-info screen.
class ShowAppInfo extends AppMenuChoice {
  const ShowAppInfo();
}

/// File the app under this card.
class FileUnder extends AppMenuChoice {
  const FileUnder(this.cardId);

  final String cardId;
}

/// Delete a shortcut outright. Only shortcuts can go: an app is removed by
/// uninstalling it, which is a different thing entirely.
class RemoveShortcut extends AppMenuChoice {
  const RemoveShortcut();
}

/// Where an app gets filed.
///
/// Scrollable and height-capped: the list grows with the deck, and a fixed
/// column of one row per card runs off the bottom of a screen this short as
/// soon as there are more than a few — which is exactly what it did, with no
/// way to reach the cards below the fold.
Future<AppMenuChoice?> showAppMenuSheet(
  BuildContext context, {
  required LaunchableApp app,
  required CardDeck deck,
  required DeckCard from,
}) {
  return showModalBottomSheet<AppMenuChoice>(
    context: context,
    backgroundColor: DeckColors.strip,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) {
      final filedUnder = deck.cardIdFor(app.id);
      return ConstrainedBox(
        // Never take the whole screen: leaving the deck visible behind the
        // sheet is what makes it read as a choice rather than a new page.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(app.label,
                    style: const TextStyle(color: DeckColors.text)),
                subtitle: Text(
                  app.packageName,
                  style:
                      const TextStyle(color: DeckColors.textDim, fontSize: 11),
                ),
              ),
              const Divider(height: 1, color: DeckColors.surfaceEdge),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    if (filedUnder != null)
                      ListTile(
                        leading: const Icon(Icons.remove_circle_outline,
                            color: DeckColors.textDim),
                        title: Text(
                          from.isAllApps
                              ? 'Unfile'
                              : 'Remove from ${from.name}',
                          style: const TextStyle(color: DeckColors.text),
                        ),
                        onTap: () => Navigator.pop(context, const UnfileApp()),
                      ),
                    for (final option in deck.folders)
                      if (option.id != from.id || from.isAllApps)
                        ListTile(
                          leading: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: colorOf(option.colorKey),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Icon(iconOf(option.iconKey),
                                size: 15, color: DeckColors.onCard),
                          ),
                          title: Text('File under ${option.name}',
                              style: const TextStyle(color: DeckColors.text)),
                          trailing: filedUnder == option.id
                              ? const Icon(Icons.check,
                                  size: 17, color: DeckColors.textDim)
                              : null,
                          onTap: () =>
                              Navigator.pop(context, FileUnder(option.id)),
                        ),
                    // A legacy shortcut has no package of its own — it is an
                    // intent — so there is no app to show information about.
                    if (app.packageName.isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.info_outline,
                            color: DeckColors.textDim),
                        title: const Text('App info',
                            style: TextStyle(color: DeckColors.text)),
                        onTap: () => Navigator.pop(context, const ShowAppInfo()),
                      ),
                    if (app.isShortcut)
                      ListTile(
                        leading: const Icon(Icons.delete_outline_rounded,
                            color: Color(0xFFFF6B5A)),
                        title: const Text('Delete shortcut',
                            style: TextStyle(color: DeckColors.text)),
                        subtitle: const Text(
                          'Removes it from Rolidecks, not from the app it came '
                          'from',
                          style:
                              TextStyle(color: DeckColors.textDim, fontSize: 11),
                        ),
                        onTap: () =>
                            Navigator.pop(context, const RemoveShortcut()),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
