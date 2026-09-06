/// The deck: a vertical stack of coloured cards, each a folder of apps, with
/// an "all apps" card pinned at the bottom.
///
/// Pure Dart, so every rule about the deck — the terminal card staying last,
/// reorder never losing a card, an app living in at most one folder — is
/// testable without a device.
library;

import 'card_style.dart';
import 'models.dart';

class DeckCard {
  const DeckCard({
    required this.id,
    required this.name,
    required this.colorKey,
    required this.iconKey,
    this.appIds = const [],
    this.isAllApps = false,
    this.imageOffset = 0,
  });

  final String id;
  final String name;

  /// Key into [cardPalette], not a raw colour: the palette is closed, and
  /// storing the key means a palette tweak restyles existing decks.
  final String colorKey;

  final String iconKey;

  /// Apps filed under this card, in the order they were added.
  final List<String> appIds;

  /// How the card's picture is framed vertically, from -1 (its top edge) to 1
  /// (its bottom). The picture itself is not in the model — it is a file named
  /// after the card — but where you chose to sit it is a decision, and belongs
  /// with the colour and the icon.
  final double imageOffset;

  /// The terminal card. It holds no [appIds] of its own — it shows everything
  /// installed — and it cannot be deleted or moved off the bottom.
  final bool isAllApps;

  CardColor get color => colorForKey(colorKey);

  DeckCard copyWith({
    String? name,
    String? colorKey,
    String? iconKey,
    List<String>? appIds,
    double? imageOffset,
  }) {
    return DeckCard(
      id: id,
      name: name ?? this.name,
      colorKey: colorKey ?? this.colorKey,
      iconKey: iconKey ?? this.iconKey,
      appIds: appIds ?? this.appIds,
      isAllApps: isAllApps,
      imageOffset: imageOffset ?? this.imageOffset,
    );
  }

  /// The apps on this card that are actually installed, in card order.
  /// The all-apps card ignores its own list and reports everything.
  List<LaunchableApp> resolve(List<LaunchableApp> installed) {
    if (isAllApps) {
      final all = [...installed]..sort(compareByLabel);
      return all;
    }
    final byId = {for (final app in installed) app.id: app};
    return [
      for (final id in appIds)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorKey': colorKey,
        'iconKey': iconKey,
        'appIds': appIds,
        'isAllApps': isAllApps,
        if (imageOffset != 0) 'imageOffset': imageOffset,
      };

  static DeckCard fromJson(Map<String, dynamic> json) {
    final colorKey = json['colorKey'] as String? ?? cardPalette.first.key;
    return DeckCard(
      id: json['id'] as String? ?? 'card',
      name: json['name'] as String? ?? 'Card',
      colorKey: isKnownColorKey(colorKey) ? colorKey : cardPalette.first.key,
      iconKey: normaliseIconKey(json['iconKey'] as String?),
      appIds: [
        for (final entry in (json['appIds'] as List? ?? const []))
          if (entry is String) entry,
      ],
      isAllApps: json['isAllApps'] as bool? ?? false,
      // Clamped on the way in: a value outside the range would frame the
      // picture off the card entirely.
      imageOffset:
          ((json['imageOffset'] as num?)?.toDouble() ?? 0).clamp(-1.0, 1.0),
    );
  }
}

class CardDeck {
  const CardDeck(this.cards);

  final List<DeckCard> cards;

  static const allAppsId = '__all__';

  /// The card every deck ends with. Seeded rather than special-cased in the
  /// UI, so the stack renders one kind of thing.
  static const allAppsCard = DeckCard(
    id: allAppsId,
    name: 'all apps',
    colorKey: 'butter',
    iconKey: 'apps',
    isAllApps: true,
  );

  bool get isEmpty => cards.isEmpty;

  int get length => cards.length;

  DeckCard operator [](int index) => cards[index];

  int indexOfId(String id) => cards.indexWhere((card) => card.id == id);

  /// Cards the user made, i.e. everything but the terminal card.
  List<DeckCard> get folders =>
      [for (final card in cards) if (!card.isAllApps) card];

  /// Guarantees the invariant the whole layout leans on: exactly one all-apps
  /// card, and it is last.
  static CardDeck normalised(List<DeckCard> cards) {
    final folders = [for (final card in cards) if (!card.isAllApps) card];
    return CardDeck([...folders, allAppsCard]);
  }

  CardDeck addCard(String name) {
    final index = folders.length;
    return normalised([
      ...folders,
      DeckCard(
        id: 'card-${DateTime.now().microsecondsSinceEpoch}-$index',
        name: name,
        colorKey: paletteAt(index).key,
        iconKey: starterIconKeys[(index + 1) % starterIconKeys.length],
      ),
    ]);
  }

  CardDeck updateCard(String id, DeckCard Function(DeckCard) change) {
    return normalised([
      for (final card in cards)
        if (card.id == id && !card.isAllApps) change(card) else card,
    ]);
  }

  /// Removing the all-apps card is not offered; asking for it is a no-op
  /// rather than an error, so callers don't have to guard.
  CardDeck removeCard(String id) =>
      normalised([for (final card in folders) if (card.id != id) card]);

  /// Moves a folder card. Indices are into the folder list, and are clamped —
  /// dragging past the end of the stack is a normal gesture, and the all-apps
  /// card can never be displaced from the bottom.
  CardDeck reorder(int from, int to) {
    final moved = [...folders];
    if (moved.isEmpty) return normalised(moved);
    final safeFrom = from.clamp(0, moved.length - 1);
    final card = moved.removeAt(safeFrom);
    moved.insert(to.clamp(0, moved.length), card);
    return normalised(moved);
  }

  /// Files [appId] under [cardId], removing it from any other card first: an
  /// app in two folders would show up twice and be ambiguous to remove.
  CardDeck assign(String appId, String cardId) {
    return normalised([
      for (final card in folders)
        if (card.id == cardId)
          card.copyWith(appIds: [
            ...card.appIds.where((existing) => existing != appId),
            appId,
          ])
        else
          card.copyWith(
            appIds: [...card.appIds.where((existing) => existing != appId)],
          ),
    ]);
  }

  /// Files several apps at once, for the add-apps picker. Same rule as
  /// [assign]: each app ends up on this card and nowhere else.
  CardDeck assignAll(Iterable<String> appIds, String cardId) {
    final moving = appIds.toSet();
    return normalised([
      for (final card in folders)
        if (card.id == cardId)
          card.copyWith(appIds: [
            ...card.appIds.where((existing) => !moving.contains(existing)),
            ...moving,
          ])
        else
          card.copyWith(
            appIds: [
              ...card.appIds.where((existing) => !moving.contains(existing)),
            ],
          ),
    ]);
  }

  CardDeck unassign(String appId) {
    return normalised([
      for (final card in folders)
        card.copyWith(
          appIds: [...card.appIds.where((existing) => existing != appId)],
        ),
    ]);
  }

  /// Which card an app is filed under, or null when it only lives in all-apps.
  String? cardIdFor(String appId) {
    for (final card in folders) {
      if (card.appIds.contains(appId)) return card.id;
    }
    return null;
  }

  /// A deck for a phone that has never run the launcher. An empty stack looks
  /// broken, and naming the starter cards is a better first impression than
  /// asking the user to build the whole thing before seeing anything.
  static CardDeck seed() => normalised([
        for (var i = 0; i < _seedNames.length; i++)
          DeckCard(
            id: 'card-seed-$i',
            name: _seedNames[i],
            colorKey: paletteAt(i).key,
            iconKey: _seedIcons[i],
          ),
      ]);

  static const _seedNames = ['daily', 'media', 'talk', 'play', 'tools'];
  // Material names, not the short ones the earliest builds invented, so a
  // seeded card's icon matches the shelf it is shown next to.
  static const _seedIcons = starterIconKeys;

  List<Map<String, dynamic>> toJson() =>
      [for (final card in folders) card.toJson()];

  static CardDeck fromJson(Object? json) {
    // normalised rather than an empty deck: a corrupt or missing stored value
    // must still come back with the all-apps card, since the stack, the knob
    // and the folder screen all assume it is there.
    if (json is! List) return normalised(const []);
    return normalised([
      for (final entry in json)
        if (entry is Map) DeckCard.fromJson(entry.cast<String, dynamic>()),
    ]);
  }
}

int compareByLabel(LaunchableApp a, LaunchableApp b) {
  final byLabel = a.label.toLowerCase().compareTo(b.label.toLowerCase());
  return byLabel != 0 ? byLabel : a.id.compareTo(b.id);
}

List<LaunchableApp> searchApps(List<LaunchableApp> apps, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return apps;
  return [
    for (final app in apps)
      if (app.label.toLowerCase().contains(needle) ||
          app.packageName.toLowerCase().contains(needle))
        app,
  ];
}
