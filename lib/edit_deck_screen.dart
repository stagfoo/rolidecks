import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'app_picker_screen.dart';
import 'card_deck.dart';
import 'launcher_bridge.dart';
import 'card_editor_sheet.dart';
import 'models.dart';
import 'theme.dart';

/// The whole deck, laid out to be rearranged and filled.
///
/// Every card shows what is on it and a + to add more, so setting the launcher
/// up doesn't mean opening all-apps and filing one app at a time.
///
/// Dragging starts only from the handle. That is what lets this screen scroll:
/// a drag anywhere on the row would fight the list's own scroll, which is the
/// conflict that forced the earlier arrange mode to fit everything on one
/// screen and never scroll at all.
class EditDeckScreen extends StatefulWidget {
  const EditDeckScreen({
    super.key,
    required this.deck,
    required this.installed,
    required this.onDeckChanged,
  });

  final CardDeck deck;
  final List<LaunchableApp> installed;
  final ValueChanged<CardDeck> onDeckChanged;

  @override
  State<EditDeckScreen> createState() => _EditDeckScreenState();
}

class _EditDeckScreenState extends State<EditDeckScreen> {
  late CardDeck _deck = widget.deck;

  void _update(CardDeck deck) {
    setState(() => _deck = deck);
    widget.onDeckChanged(deck);
  }

  @override
  Widget build(BuildContext context) {
    final folders = _deck.folders;
    return Scaffold(
      backgroundColor: DeckColors.ground,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ReorderableListView.builder(
                // The row's own handle starts a drag; without this the whole
                // row would, and long-pressing anything would pick it up.
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                itemCount: folders.length + 1,
                // onReorderItem, not the deprecated onReorder: it hands back
                // a newIndex already adjusted for the removed row, which is
                // exactly what CardDeck.reorder expects. Doing the old manual
                // "subtract one when moving down" on top of it would correct
                // twice.
                onReorderItem: (oldIndex, newIndex) =>
                    _update(_deck.reorder(oldIndex, newIndex)),
                footer: _allAppsRow(),
                itemBuilder: (context, index) {
                  if (index >= folders.length) {
                    return const SizedBox(key: ValueKey('tail'));
                  }
                  return _cardRow(folders[index], index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.arrow_back_rounded,
              size: 22,
              color: DeckColors.text,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Edit deck',
              style: TextStyle(
                color: DeckColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: _addCard,
            icon: const Icon(Icons.add_rounded, color: DeckColors.textDim),
            tooltip: 'New card',
          ),
        ],
      ),
    );
  }

  Widget _cardRow(DeckCard card, int index) {
    final color = colorOf(card.colorKey);
    final onCard = onCardFor(color);
    final apps = card.resolve(widget.installed);

    return Padding(
      key: ValueKey(card.id),
      padding: const EdgeInsets.only(bottom: 10),
      // The whole card opens the editor, not just its name: a name strip is a
      // thin target, and the card is the thing being edited. The app chips, the
      // add button and the drag handle are children, so they are hit first and
      // still do their own jobs.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _editCard(card, index),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(DeckMetrics.cardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 2),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        // Generous padding: the handle is the only way to move a
                        // card, so it has to be an easy target.
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 20,
                          color: onCard,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        card.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onCard,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      iconOf(card.iconKey),
                      size: 17,
                      color: onCard,
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: onCard.withValues(alpha: 0.55),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 66,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  children: [
                    // A widget card holds a widget, so there is nothing to
                    // chip and nothing to add: offering an add button would file
                    // apps onto a card that does not draw them.
                    if (card.isWidget)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          card.hasWidget
                              ? 'a widget · three rows'
                              : 'a widget · none chosen yet',
                          style: TextStyle(
                            color: onCard.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else ...[
                      for (final app in apps) ...[
                        _AppChip(
                            app: app, onCard: onCard, onTap: () => _unfile(app)),
                        const SizedBox(width: 8),
                      ],
                      _AddChip(onCard: onCard, onTap: () => _addApps(card)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// All apps is the back of the deck: no handle, no +, nothing to file.
  /// The terminal card, at the foot of the list.
  ///
  /// Editable like the others, but not dimmed and not draggable: it can be
  /// restyled, and it still cannot be moved, deleted, or filled. It carries no
  /// add chip for that last reason — the deck would drop the apps anyway, so
  /// offering it would only look like it worked.
  Widget _allAppsRow() {
    final card = _deck.cards.last;
    final onCard = onCardForKey(card.colorKey);
    return GestureDetector(
      onTap: () => _editCard(card, _deck.folders.length),
      child: Container(
        decoration: BoxDecoration(
          color: colorOf(card.colorKey),
          borderRadius: BorderRadius.circular(DeckMetrics.cardRadius),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${card.name} · always last',
                style: TextStyle(
                  color: onCard,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${widget.installed.length}',
              style: TextStyle(
                color: onCard.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Icon(iconOf(card.iconKey), size: 17, color: onCard),
          ],
        ),
      ),
    );
  }

  Future<void> _addApps(DeckCard card) async {
    final chosen = await showAppPicker(
      context,
      card: card,
      deck: _deck,
      installed: widget.installed,
    );
    if (chosen == null || chosen.isEmpty) return;
    _update(_deck.assignAll(chosen, card.id));
  }

  void _unfile(LaunchableApp app) => _update(_deck.unassign(app.id));

  Future<void> _editCard(DeckCard card, int index) async {
    final result = await showCardEditor(
      context,
      card,
      position: index,
      folderCount: _deck.folders.length,
      apps: card.resolve(widget.installed),
    );
    if (result == null) return;
    // The card's widget goes back to the system with the card. Nothing else
    // releases one, and an id left allocated keeps its app updating a widget that
    // is on no card.
    final widgetId = card.widgetId;
    if (result.deleted && widgetId != null) {
      await LauncherBridge.instance.releaseWidget(widgetId);
    }
    _update(
      result.deleted
          ? _deck.removeCard(card.id)
          : _deck.updateCard(card.id, (_) => result.card),
    );
  }

  Future<void> _addCard() async {
    final deck = _deck.addCard('new card');
    _update(deck);
    await _editCard(deck.folders.last, deck.folders.length - 1);
  }
}

class _AppChip extends StatelessWidget {
  const _AppChip({
    required this.app,
    required this.onCard,
    required this.onTap,
  });

  final LaunchableApp app;
  final Color onCard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconImage(
              app: app,
              size: 42,
              color: onCard.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 3),
            Text(
              app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: onCard.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddChip extends StatelessWidget {
  const _AddChip({required this.onCard, required this.onTap});

  final Color onCard;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: onCard.withValues(alpha: 0.45),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 22,
                color: onCard.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'add',
              style: TextStyle(
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: onCard.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
