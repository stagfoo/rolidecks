/// Geometry for the rolodex of cards and the pull knob beside it.
///
/// The first card is the front of the deck and every card after it sits
/// *behind* the one before, receding downward — so "all apps", always last, is
/// always at the very back. Each covered card reveals its bottom strip below
/// the card in front of it, which is why a card's name lives at its bottom
/// edge: that strip is the only part of it you can see.
///
/// The focused card is revealed whole, and the cards in front of it slide up
/// until their bottoms meet its top edge, so nothing overlaps it. No card ever
/// has to be lifted out of the paint order; the positions alone do it.
///
/// Pure Dart, so it can be pinned down at the exact size this phone reports.
library;

import 'card_deck.dart';

class StackSpec {
  const StackSpec({
    required this.peek,
    required this.cardHeight,
    required this.cardCount,
    required this.focusedIndex,
    required this.originY,
    required this.boxHeight,
    this.rowHeight = StackStyle.defaultRowHeight,
    this.rows = const [],
  });

  /// How much of a covered card stays visible: its top strip.
  final double peek;

  /// Every card is drawn this tall, focused or not — the covered ones are
  /// simply overlapped. Laying collapsed cards out at sliver height instead is
  /// what made them bars, and made their contents overflow.
  final double cardHeight;

  final int cardCount;
  final int focusedIndex;

  /// Top of the stack, placed by [deckAlignment].
  final double originY;

  /// Height the stack was asked to fit into. When [totalHeight] exceeds it
  /// there are more cards than the box can hold at readable sizes, and the
  /// stack scrolls rather than crushing the strips.
  final double boxHeight;

  /// What each row of icons past the first adds to a card's height.
  final double rowHeight;

  /// Rows of icons per card, parallel to the deck. Empty means every card is a
  /// single row, which is the whole deck before anyone changes one.
  final List<int> rows;

  /// Rows on card [index], defaulting to one.
  int rowsOf(int index) =>
      index >= 0 && index < rows.length ? rows[index] : 1;

  bool get overflows => totalHeight > boxHeight + 0.01;

  /// The deck's height as if the open card were a single row, and where that
  /// band sits — what the side rail is measured against.
  ///
  /// Deliberately *not* [totalHeight]/[originY]. Those move when focus moves to
  /// a card with more rows, and the rail maps a finger position onto a card
  /// index through its own height: a track that resized as focus changed
  /// remapped the same finger position onto a different card on the very next
  /// drag update, so focus could bounce between two cards and the rail stopped
  /// snapping. The mapping has to be a fixed function of the deck, not of which
  /// card happens to be open.
  ///
  /// With every card a single row these are exactly [totalHeight] and
  /// [originY], so a deck that has never been given extra rows looks and
  /// behaves as it always did.
  double get railHeight =>
      cardCount <= 0 ? 0 : cardHeight + (cardCount - 1) * peek;

  double get railTop =>
      railHeight >= boxHeight ? 0.0 : (boxHeight - railHeight) * deckAlignment;

  /// Total revealed height. The focused card is seen whole, everything else
  /// contributes its strip.
  ///
  /// So the only card whose row count changes the deck's height is the open
  /// one. Opening a four-row card grows the stack and pushes everything below
  /// it down; closing it gives that room straight back.
  double get totalHeight => cardCount <= 0
      ? 0
      : heightOf(focusedIndex) + (cardCount - 1) * peek;

  /// Top edge of card [index].
  ///
  /// From the focused card down, cards sit a strip apart and recede behind one
  /// another. Cards in front of the focused one are pushed up so their *bottom*
  /// edges land a strip apart, clearing the focused card entirely — the last of
  /// them ends exactly where the focused card begins.
  /// Cards are positioned by the edge that shows, not by their top, which is
  /// what lets them differ in height without disturbing each other. A card in
  /// front of the focused one is placed by its *bottom* — a strip below the one
  /// before it — and a card behind the focused one by the top of its strip, a
  /// strip below the card in front. Only the focused card is placed by its top.
  ///
  /// With every card a single row this reduces exactly to the flat
  /// `originY + index * peek`, which is why the whole deck is unmoved until a
  /// card is actually given more rows.
  double topOf(int index) {
    if (index < focusedIndex) {
      return originY + (index + 1) * peek - heightOf(index);
    }
    if (index == focusedIndex) {
      return originY + index * peek;
    }
    return revealTopOf(index) - (heightOf(index) - peek);
  }

  /// Where the visible slice of card [index] starts. For a covered card that
  /// is its bottom strip; the focused card is visible from its top.
  double revealTopOf(int index) {
    if (index == focusedIndex) return originY + index * peek;
    if (index < focusedIndex) return originY + index * peek;
    // Behind the focused card: the first one starts where the focused card
    // ends, and the rest follow a strip apart. Written from the focused card's
    // bottom rather than from index alone, because that bottom is the only
    // thing its height can move.
    return originY +
        focusedIndex * peek +
        heightOf(focusedIndex) +
        (index - focusedIndex - 1) * peek;
  }

  /// Back-to-front paint order. The first card is the front of the deck, so it
  /// is painted last; "all apps" is painted first and stays at the very back.
  List<int> get paintOrder =>
      [for (var i = cardCount - 1; i >= 0; i--) i];

  /// How tall card [index] is drawn — its base height plus the rows it was
  /// given past the first. A covered card is drawn at its full height just as
  /// before; only how much of it shows varies.
  double heightOf(int index) =>
      cardHeight + (rowsOf(index) - 1) * rowHeight;

  /// What the eye actually gets of card [index].
  double revealOf(int index) =>
      index == focusedIndex ? heightOf(index) : peek;
}

/// Where a deck shorter than its box sits in it: 0 hangs it from the top, 0.5
/// centres it, 1 pins it to the bottom.
///
/// Cards are a fixed height, so on a phone taller than the deck needs, all the
/// spare room is at one end or the other and this decides which. Centred looks
/// composed; pinned to the bottom keeps it under a thumb. On the phone this was
/// built for the deck fills its box, so the value makes no difference there.
const double deckAlignment = 0.5;

class StackStyle {
  const StackStyle({
    this.preferredPeek = 44,
    this.minPeek = 32,
    this.preferredCardHeight = 158,
    this.minCardHeight = 108,
    this.rowHeight = defaultRowHeight,
  });

  final double preferredPeek;

  /// Never let the strip shrink below the card header, or the name in it gets
  /// clipped — which is exactly the overflow the first build shipped.
  final double minPeek;

  final double preferredCardHeight;
  final double minCardHeight;

  /// What each row of icons past the first adds to a card.
  ///
  /// One icon and its title, plus the gap above the next row — the single-row
  /// card already has the room for its own row inside [preferredCardHeight], so
  /// this is the cost of each *extra* one. Kept here rather than in the card
  /// widget because the stack has to know a card's height before the card is
  /// built, and two copies of this number would drift into the rows not fitting
  /// the space reserved for them.
  final double rowHeight;

  static const standard = StackStyle();

  /// The fixed top strip of a card: name on the left, mark on the right. Kept
  /// here because it is the floor [minPeek] has to respect.
  static const headerHeight = 32.0;

  /// The default [rowHeight], as a constant so a [StackSpec] built without a
  /// style can still state one.
  static const defaultRowHeight = 64.0;
}

/// Fits [cardCount] overlapping cards into [height].
///
/// Squeezes the strips first, then the card itself, because a slightly shorter
/// card costs less than strips too thin to read a name in.
StackSpec solveStack({
  required double height,
  required int cardCount,
  required int focusedIndex,
  StackStyle style = StackStyle.standard,
  List<int> rows = const [],
}) {
  if (cardCount <= 0) {
    return StackSpec(
      peek: style.preferredPeek,
      cardHeight: style.preferredCardHeight,
      cardCount: 0,
      focusedIndex: 0,
      originY: 0,
      boxHeight: height,
      rowHeight: style.rowHeight,
      rows: rows,
    );
  }

  final safeIndex = focusedIndex.clamp(0, cardCount - 1);
  final strips = cardCount - 1;

  // Only the focused card is drawn at full height, so its extra rows are the
  // only ones competing with the strips for the box. The rest can be as tall as
  // they like while closed.
  final focusedRows =
      safeIndex < rows.length ? clampAppRows(rows[safeIndex]) : 1;
  final extra = (focusedRows - 1) * style.rowHeight;

  var cardHeight = style.preferredCardHeight;
  var peek = style.preferredPeek;

  if (strips > 0) {
    final spare = height - cardHeight - extra;
    final fitted = spare / strips;
    if (fitted < peek) peek = fitted;

    if (peek < style.minPeek) {
      peek = style.minPeek;
      cardHeight = height - strips * peek - extra;

      // If the card would now be below its floor there are simply more cards
      // than fit. Both floors hold and the stack overflows, to be scrolled —
      // strips too thin to read a name in are not a trade worth making, and
      // that crushing is what clipped the labels on the device.
      cardHeight = cardHeight.clamp(style.minCardHeight, double.infinity);
    }
  }

  cardHeight = cardHeight.clamp(style.minCardHeight, double.infinity);
  peek = peek.clamp(1.0, double.infinity);

  final total = cardHeight + extra + strips * peek;
  final originY = total >= height ? 0.0 : (height - total) * deckAlignment;

  return StackSpec(
    peek: peek,
    cardHeight: cardHeight,
    cardCount: cardCount,
    focusedIndex: safeIndex,
    originY: originY,
    boxHeight: height,
    rowHeight: style.rowHeight,
    rows: rows,
  );
}

/// Where the grip sits on its track, and how big it is.
class KnobSpec {
  const KnobSpec({required this.top, required this.height, required this.trackHeight});

  final double top;
  final double height;
  final double trackHeight;

  double get center => top + height / 2;
}

/// The knob shrinks as the deck grows, the way a scrollbar thumb does, so its
/// size reads as "how much deck there is" without any extra chrome.
KnobSpec solveKnob({
  required double trackHeight,
  required int cardCount,
  required int focusedIndex,
  double minHeight = 44,
}) {
  if (cardCount <= 1 || trackHeight <= 0) {
    return KnobSpec(
      top: 0,
      height: trackHeight <= 0 ? 0 : trackHeight,
      trackHeight: trackHeight,
    );
  }
  final proportional = trackHeight / cardCount;
  final floor = minHeight.clamp(0.0, trackHeight);
  final height = proportional.clamp(floor, trackHeight);
  final travel = trackHeight - height;
  final safeIndex = focusedIndex.clamp(0, cardCount - 1);
  return KnobSpec(
    top: travel * (safeIndex / (cardCount - 1)),
    height: height,
    trackHeight: trackHeight,
  );
}

/// Which card a drag to [y] on the track selects.
///
/// Uses the knob's own travel rather than the raw track, so the card under the
/// grip matches where the grip actually is — dividing the bare track into equal
/// bands would drift, because the knob can't reach the last band's top.
int cardIndexForKnobPosition({
  required double y,
  required double trackHeight,
  required int cardCount,
  double minHeight = 44,
}) {
  if (cardCount <= 1) return 0;
  final knob = solveKnob(
    trackHeight: trackHeight,
    cardCount: cardCount,
    focusedIndex: 0,
    minHeight: minHeight,
  );
  final travel = trackHeight - knob.height;
  if (travel <= 0) return 0;
  final centred = (y - knob.height / 2).clamp(0.0, travel);
  return (centred / travel * (cardCount - 1)).round().clamp(0, cardCount - 1);
}
