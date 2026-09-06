import 'package:flutter/material.dart';

import 'app_menu_sheet.dart';
import 'app_tile.dart';
import 'card_deck.dart';
import 'launcher_bridge.dart';
import 'models.dart';
import 'theme.dart';

/// What's inside a card: a grid of apps on the card's own colour.
///
/// The all-apps card shows everything installed and offers filing an app onto
/// another card; an ordinary card shows what's filed on it.
class FolderScreen extends StatefulWidget {
  const FolderScreen({
    super.key,
    required this.card,
    required this.deck,
    required this.installed,
    required this.onDeckChanged,
    required this.onRemoveShortcut,
  });

  final DeckCard card;
  final CardDeck deck;
  final List<LaunchableApp> installed;
  final ValueChanged<CardDeck> onDeckChanged;

  /// Deleting is the home screen's job — it owns the store and the undo — but
  /// this is where a shortcut is long-pressed.
  final Future<void> Function(LaunchableApp) onRemoveShortcut;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

/// The two halves of the all-apps card.
enum _Tab { apps, shortcuts }

class _FolderScreenState extends State<FolderScreen> {
  late CardDeck _deck = widget.deck;
  String _query = '';
  _Tab _tab = _Tab.apps;

  /// Null until asked. Android only sends shortcuts to the home app, so an
  /// empty Shortcuts tab means something different depending on this.
  bool? _isHomeApp;

  /// The card's apps, resolved once rather than on every build. For the
  /// all-apps card that resolve sorts every app on the phone, and rebuilding
  /// on each keystroke of the search field made typing sort a hundred apps per
  /// character.
  late List<LaunchableApp> _apps = _card.resolve(widget.installed);

  DeckCard get _card {
    final index = _deck.indexOfId(widget.card.id);
    return index >= 0 ? _deck[index] : widget.card;
  }

  @override
  void initState() {
    super.initState();
    if (widget.card.isAllApps) _loadShortcutState();
  }

  Future<void> _loadShortcutState() async {
    final state = await LauncherBridge.instance.shortcutDiagnostics();
    if (!mounted) return;
    setState(() => _isHomeApp = state['isDefaultLauncher'] == true);
  }

  @override
  void didUpdateWidget(FolderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.installed, widget.installed)) {
      _apps = _card.resolve(widget.installed);
    }
  }

  void _update(CardDeck deck) {
    setState(() {
      _deck = deck;
      // Filing an app changes what this card holds, so the resolved list has
      // to follow — but only then, not on every frame.
      _apps = _deck[_deck.indexOfId(widget.card.id).clamp(0, _deck.length - 1)]
          .resolve(widget.installed);
    });
    widget.onDeckChanged(deck);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final color = colorOf(card.colorKey);
    final showingShortcuts = card.isAllApps && _tab == _Tab.shortcuts;
    final apps = searchApps(
      card.isAllApps
          ? [
              for (final entry in _apps)
                if (entry.isShortcut == showingShortcuts) entry,
            ]
          : _apps,
      _query,
    );

    return Scaffold(
      backgroundColor: DeckColors.ground,
      body: SafeArea(
        child: Column(
          children: [
            _header(card, color),
            if (card.isAllApps) _tabs(color),
            if (card.isAllApps) _search(),
            Expanded(
              child: apps.isEmpty
                  ? _empty(card)
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 92,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: apps.length,
                      itemBuilder: (context, index) => AppTile(
                        app: apps[index],
                        size: 54,
                        accent: color,
                        filed: _deck.cardIdFor(apps[index].id) != null,
                        onTap: () => Navigator.pop(context, apps[index]),
                        onLongPress: () => _showAppMenu(apps[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(DeckCard card, Color color) {
    final onCard = onCardFor(color);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(DeckMetrics.cardRadius),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(Icons.arrow_back_rounded, size: 22, color: onCard),
          ),
          const SizedBox(width: 10),
          Icon(iconOf(card.iconKey), size: 19, color: onCard),
          const Spacer(),
          Text(
            card.name,
            style: TextStyle(
              color: onCard,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Shortcuts are their own list rather than mixed into the apps: they arrive
  /// from somewhere else, there are far fewer of them, and this is where the
  /// button to make one belongs.
  Widget _tabs(Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: [
          for (final tab in _Tab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _tab = tab),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _tab == tab ? color : DeckColors.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: _tab == tab ? color : DeckColors.surfaceEdge,
                    ),
                  ),
                  child: Text(
                    tab == _Tab.apps ? 'Apps' : 'Shortcuts',
                    style: deckText(
                      size: 12,
                      weight: 600,
                      color: _tab == tab ? onCardFor(color) : DeckColors.textDim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _search() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: TextField(
        style: const TextStyle(color: DeckColors.text, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: DeckColors.surface,
          hintText: 'Search ${widget.installed.length} apps',
          hintStyle: const TextStyle(color: DeckColors.textDim, fontSize: 13),
          prefixIcon:
              const Icon(Icons.search, size: 18, color: DeckColors.textDim),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _empty(DeckCard card) {
    if (card.isAllApps && _tab == _Tab.shortcuts) {
      if (_query.trim().isNotEmpty) {
        return Center(
          child: Text('Nothing matches',
              style: deckText(size: 13, color: DeckColors.textDim)),
        );
      }
      // An empty tab means one of two very different things, and only one of
      // them is worth doing anything about — so it says which.
      final notHome = _isHomeApp == false;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notHome
                    ? 'Rolidecks is not the home app, so Android will not send '
                        'it shortcuts at all.'
                    : 'No shortcuts yet.\n\nUse "add to home screen" in any app '
                        'and it will appear here.',
                textAlign: TextAlign.center,
                style: deckText(size: 13, color: DeckColors.textDim),
              ),
              if (notHome) ...[
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: LauncherBridge.instance.openHomeSettings,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorOf(card.colorKey),
                    foregroundColor: onCardForKey(card.colorKey),
                  ),
                  child: Text('Set as home app',
                      style: deckText(
                          size: 13,
                          weight: 600,
                          color: onCardForKey(card.colorKey))),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          card.isAllApps
              ? 'Nothing matches'
              : 'Nothing filed here yet.\nOpen all apps and hold an app to file it.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: DeckColors.textDim, fontSize: 13),
        ),
      ),
    );
  }

  Future<void> _showAppMenu(LaunchableApp app) async {
    final choice = await showAppMenuSheet(
      context,
      app: app,
      deck: _deck,
      from: _card,
    );
    switch (choice) {
      case null:
        return;
      case UnfileApp():
        _update(_deck.unassign(app.id));
      case ShowAppInfo():
        await LauncherBridge.instance.openAppInfo(app.packageName);
      case FileUnder(:final cardId):
        _update(_deck.assign(app.id, cardId));
      case RemoveShortcut():
        await widget.onRemoveShortcut(app);
        // This screen was pushed with a snapshot of the list, so it drops the
        // shortcut itself rather than waiting to be rebuilt with a new one.
        if (mounted) {
          setState(() =>
              _apps = _apps.where((entry) => entry.id != app.id).toList());
        }
    }
  }
}
