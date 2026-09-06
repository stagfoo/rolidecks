import 'dart:io';

import 'package:flutter/material.dart';

import 'card_deck.dart';
import 'card_row.dart';
import 'models.dart';
import 'stack_layout.dart';
import 'theme.dart';

/// One card in the stack.
///
/// Always drawn at full height — what changes between focused and covered is
/// only how much of it the card in front leaves visible. That is what makes
/// the deck read as overlapping cards, and it means a covered card never has
/// to squeeze its contents into a sliver.
///
/// The name sits in a fixed strip at the card's *bottom* edge, because that is
/// the part left visible when the card in front covers it. It holds everything
/// needed to identify the card: name, count and mark.
class DeckCardView extends StatelessWidget {
  const DeckCardView({
    super.key,
    required this.card,
    required this.height,
    required this.focused,
    required this.apps,
    required this.totalInstalled,
    required this.onTap,
    required this.onAppTap,
    this.onLongPress,
    this.onAppLongPress,
    this.arranging = false,
    this.wigglePhase = 0,
    this.lifted = false,
    this.flushTop = false,
    this.topBleed = 0,
    this.imagePath,
    this.imageOffset = 0,
  });

  final DeckCard card;
  final double height;
  final bool focused;
  final List<LaunchableApp> apps;
  final int totalInstalled;
  final VoidCallback onTap;
  final ValueChanged<LaunchableApp> onAppTap;
  final VoidCallback? onLongPress;
  final ValueChanged<LaunchableApp>? onAppLongPress;

  /// While arranging, the card shows only its name strip and wiggles. Its app
  /// row is hidden — arrange mode is about position, and a row of tappable
  /// icons inside something you are dragging is only a way to misfire.
  final bool arranging;

  /// Offsets each card's wiggle so the deck doesn't pulse in unison.
  final double wigglePhase;

  /// This is the card currently under the finger.
  final bool lifted;

  /// Square off the top corners.
  ///
  /// The focused card's top edge meets the bottom edge of the card in front of
  /// it exactly. Rounding there curves away from a card that ends on the same
  /// line, so the background shows through as two dark notches. Squared, the
  /// card in front simply shingles over it.
  final bool flushTop;

  /// A picture for this card, filling it behind everything else.
  final String? imagePath;

  /// Where that picture sits vertically, -1 (top) to 1 (bottom).
  final double imageOffset;

  /// Extra height added above the card, hidden behind the card in front.
  ///
  /// Squaring this card's own corners was only half the notch: the card in
  /// front keeps its rounded *bottom* corners, and those curve away from a card
  /// that starts on the same line, leaving two slivers of background at the
  /// edges. Running this card up behind the one in front fills them, and keeps
  /// the shingle — the alternative, squaring the front card's bottom too, would
  /// flatten that boundary into a plain seam.
  final double topBleed;

  @override
  Widget build(BuildContext context) {
    final color = colorOf(card.colorKey);
    final onCard = onCardFor(color);
    final card_ = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: height + topBleed,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(flushTop ? 0 : DeckMetrics.cardRadius),
            bottom: const Radius.circular(DeckMetrics.cardRadius),
          ),
          // A covered card casts a shadow onto the one behind it. Without this
          // the overlap reads as flat stripes rather than stacked cards.
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: lifted ? 0.7 : (focused ? 0.55 : 0.4)),
              blurRadius: lifted ? 26 : (focused ? 20 : 10),
              offset: Offset(0, lifted ? 12 : (focused ? 8 : 3)),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imagePath != null) _picture(color),
            Padding(
              // The bleed is background only; the card's contents stay where
              // the layout put them.
              padding: EdgeInsets.only(top: topBleed),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                      child: arranging ? const SizedBox() : _body(color, onCard)),
                  _nameStrip(onCard),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!arranging || card.isAllApps || lifted) return card_;
    return Transform.rotate(angle: wigglePhase, child: card_);
  }

  /// The card's picture, faded into the card's own colour at the bottom.
  ///
  /// Fading to the card colour rather than to black means the name strip sits
  /// on exactly the colour it always did, so the foreground already chosen for
  /// that colour stays right and nothing has to be recomputed against the
  /// picture. It also keeps a covered card's strip looking like every other
  /// card's, since the strip is the part that shows.
  Widget _picture(Color color) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(imagePath!),
            fit: BoxFit.cover,
            // The card is far wider than it is tall, so a cover crop throws
            // away most of a portrait photo's height. This is which part of it
            // to keep.
            alignment: Alignment(0, imageOffset.clamp(-1.0, 1.0)),
            // Already downscaled on the way in; this keeps the decode to the
            // size actually drawn.
            cacheWidth: 1080,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0),
                  color.withValues(alpha: 0.55),
                  color,
                ],
                stops: const [0.35, 0.7, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The strip that stays visible when this card is covered.
  Widget _nameStrip(onCard) {
    return SizedBox(
      height: StackStyle.headerHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: deckText(
                  size: 16,
                  weight: 700,
                  color: onCard,
                  letterSpacing: -0.3,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              card.isAllApps ? '$totalInstalled' : '${apps.length}',
              style: deckText(
                size: 12,
                weight: 700,
                color: onCard.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              arranging && !card.isAllApps
                  ? Icons.drag_indicator_rounded
                  : iconOf(card.iconKey),
              size: 17,
              color: onCard,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(Color color, Color onCard) {
    if (apps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            card.isAllApps ? 'nothing installed' : 'empty — hold to fill',
            style: deckText(
              size: 12,
              weight: 500,
              color: onCard.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }
    return CardAppRow(
      apps: apps,
      cardColor: color,
      onTap: onAppTap,
      onLongPress: onAppLongPress,
    );
  }
}
