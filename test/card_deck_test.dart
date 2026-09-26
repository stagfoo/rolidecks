import 'package:flutter_test/flutter_test.dart';
import 'package:rolidecks/card_deck.dart';
import 'package:rolidecks/card_style.dart';
import 'package:rolidecks/icon_catalogue.dart';
import 'package:rolidecks/models.dart';

LaunchableApp app(String package, {String? label}) => LaunchableApp(
      packageName: package,
      activityName: '$package.Main',
      label: label ?? package.split('.').last,
    );

String idOf(String package) => '$package/$package.Main';

void main() {
  group('the all-apps card', () {
    test('is always present and always last', () {
      final deck = CardDeck.normalised(const []);
      expect(deck.length, 1);
      expect(deck.cards.last.isAllApps, isTrue);
    });

    test('stays last however many cards are added', () {
      var deck = CardDeck.seed();
      deck = deck.addCard('extra');
      expect(deck.cards.last.isAllApps, isTrue);
      expect(deck.folders.any((card) => card.isAllApps), isFalse);
    });

    test('cannot be removed', () {
      final deck = CardDeck.seed().removeCard(CardDeck.allAppsId);
      expect(deck.cards.last.isAllApps, isTrue);
    });

    test('cannot be edited into an ordinary card', () {
      final deck = CardDeck.seed()
          .updateCard(CardDeck.allAppsId, (card) => card.copyWith(name: 'hijacked'));
      expect(deck.cards.last.name, 'all apps');
    });

    test('cannot be displaced from the bottom by a reorder', () {
      final deck = CardDeck.seed();
      final reordered = deck.reorder(0, 99);
      expect(reordered.cards.last.isAllApps, isTrue);
    });

    test('reports every installed app, alphabetically, ignoring its own list', () {
      final installed = [app('com.z', label: 'Zeta'), app('com.a', label: 'Alpha')];
      expect(
        CardDeck.allAppsCard.resolve(installed).map((a) => a.label),
        ['Alpha', 'Zeta'],
      );
    });

    test('a duplicate all-apps card in stored data collapses to one', () {
      final deck = CardDeck.normalised(
        [CardDeck.allAppsCard, CardDeck.allAppsCard, CardDeck.allAppsCard],
      );
      expect(deck.length, 1);
    });
  });

  group('colours and icons', () {
    test('a new card takes the next palette colour, not always the first', () {
      var deck = CardDeck.normalised(const []);
      deck = deck.addCard('one');
      deck = deck.addCard('two');
      expect(deck.folders[0].colorKey, isNot(deck.folders[1].colorKey));
    });

    test('setting a colour and an icon sticks', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck.updateCard(id, (card) => card.copyWith(colorKey: 'mint', iconKey: 'map'));
      final card = deck.cards[deck.indexOfId(id)];
      expect(card.colorKey, 'mint');
      expect(card.iconKey, 'map');
      expect(card.color.value, colorForKey('mint').value);
    });

    test('editing a colour leaves the filed apps alone', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck.assign(idOf('com.a'), id);
      deck = deck.updateCard(id, (card) => card.copyWith(colorKey: 'red'));
      expect(deck.cards[deck.indexOfId(id)].appIds, [idOf('com.a')]);
    });

    test('a seeded deck walks the palette rather than repeating one colour', () {
      final keys = CardDeck.seed().folders.map((card) => card.colorKey).toSet();
      expect(keys.length, CardDeck.seed().folders.length);
    });
  });

  group('filing apps', () {
    test('assign puts an app on a card', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck.assign(idOf('com.a'), id);
      expect(deck.cardIdFor(idOf('com.a')), id);
    });

    test('an app lives on at most one card', () {
      // Two homes would show it twice and make "remove" ambiguous.
      var deck = CardDeck.seed();
      final first = deck.folders[0].id;
      final second = deck.folders[1].id;
      deck = deck.assign(idOf('com.a'), first);
      deck = deck.assign(idOf('com.a'), second);
      expect(deck.folders[0].appIds, isEmpty);
      expect(deck.folders[1].appIds, [idOf('com.a')]);
      expect(deck.cardIdFor(idOf('com.a')), second);
    });

    test('assigning the same app twice does not duplicate it', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck.assign(idOf('com.a'), id).assign(idOf('com.a'), id);
      expect(deck.cards[deck.indexOfId(id)].appIds, hasLength(1));
    });

    test('unassign takes it off every card', () {
      var deck = CardDeck.seed();
      deck = deck.assign(idOf('com.a'), deck.folders.first.id).unassign(idOf('com.a'));
      expect(deck.cardIdFor(idOf('com.a')), isNull);
    });

    test('resolve skips filed apps that are no longer installed', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck.assign(idOf('com.gone'), id).assign(idOf('com.a'), id);
      final resolved = deck.cards[deck.indexOfId(id)].resolve([app('com.a')]);
      expect(resolved.map((a) => a.packageName), ['com.a']);
    });

    test('keeps the id of an uninstalled app so reinstalling restores it', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck.assign(idOf('com.gone'), id);
      expect(deck.cards[deck.indexOfId(id)].appIds, contains(idOf('com.gone')));
    });
  });

  group('assignAll', () {
    test('files a batch onto one card', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck.assignAll([idOf('com.a'), idOf('com.b')], id);
      expect(deck.cards[deck.indexOfId(id)].appIds,
          [idOf('com.a'), idOf('com.b')]);
    });

    test('moves apps off whatever card they were on', () {
      var deck = CardDeck.seed();
      final first = deck.folders[0].id;
      final second = deck.folders[1].id;
      deck = deck.assign(idOf('com.a'), first);
      deck = deck.assignAll([idOf('com.a'), idOf('com.b')], second);
      expect(deck.folders[0].appIds, isEmpty);
      expect(deck.cardIdFor(idOf('com.a')), second);
    });

    test('does not duplicate an app already on the target card', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck.assign(idOf('com.a'), id).assignAll([idOf('com.a')], id);
      expect(deck.cards[deck.indexOfId(id)].appIds, hasLength(1));
    });

    test('an empty batch changes nothing', () {
      final deck = CardDeck.seed();
      final before = deck.folders.map((c) => c.appIds).toList();
      final after = deck.assignAll(const [], deck.folders.first.id);
      expect(after.folders.map((c) => c.appIds), before);
    });
  });

  group('reorder', () {
    test('matches what a ReorderableListView reports', () {
      // The edit screen uses onReorderItem, which hands back a newIndex
      // already adjusted for the removed row — the index CardDeck.reorder
      // wants. These pin that the two agree.
      const deck = CardDeck([
        DeckCard(id: 'a', name: 'a', colorKey: 'cyan', iconKey: 'folder'),
        DeckCard(id: 'b', name: 'b', colorKey: 'cyan', iconKey: 'folder'),
        DeckCard(id: 'c', name: 'c', colorKey: 'cyan', iconKey: 'folder'),
      ]);
      // Dragging 'a' below 'b' reports (0, 1).
      expect(deck.reorder(0, 1).folders.map((c) => c.id), ['b', 'a', 'c']);
      // Dragging 'a' to the end reports (0, 2).
      expect(deck.reorder(0, 2).folders.map((c) => c.id), ['b', 'c', 'a']);
      // Dragging 'c' to the top reports (2, 0).
      expect(deck.reorder(2, 0).folders.map((c) => c.id), ['c', 'a', 'b']);
    });

    test('moves a card and keeps every other one', () {
      final deck = CardDeck.seed();
      final names = deck.folders.map((c) => c.name).toList();
      final moved = deck.reorder(0, 2);
      expect(moved.folders.map((c) => c.name).toSet(), names.toSet());
      expect(moved.folders.map((c) => c.name).toList(), isNot(names));
    });

    test('never loses or duplicates a card, wherever it is dropped', () {
      final deck = CardDeck.seed();
      final ids = deck.folders.map((c) => c.id).toSet();
      for (var from = 0; from < deck.folders.length; from++) {
        for (var to = -2; to < deck.folders.length + 2; to++) {
          final moved = deck.reorder(from, to);
          expect(moved.folders.map((c) => c.id).toSet(), ids,
              reason: '$from -> $to');
          expect(moved.folders, hasLength(ids.length), reason: '$from -> $to');
        }
      }
    });

    test('reordering an empty deck is a no-op', () {
      expect(CardDeck.normalised(const []).reorder(0, 1).folders, isEmpty);
    });
  });

  group('persistence', () {
    test('round-trips colours, icons and filed apps', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck
          .updateCard(
              id, (card) => card.copyWith(colorKey: 'violet', iconKey: 'menu_book'))
          .assign(idOf('com.a'), id);

      final restored = CardDeck.fromJson(deck.toJson());
      final card = restored.cards[restored.indexOfId(id)];
      expect(card.colorKey, 'violet');
      expect(card.iconKey, 'menu_book');
      expect(card.appIds, [idOf('com.a')]);
      expect(restored.cards.last.isAllApps, isTrue);
    });

    test('the all-apps card is not written out — it is always re-added', () {
      expect(CardDeck.seed().toJson().any((card) => card['isAllApps'] == true),
          isFalse);
    });

    test('survives corrupt or absent stored data', () {
      expect(CardDeck.fromJson(null).cards.last.isAllApps, isTrue);
      expect(CardDeck.fromJson('nonsense').length, 1);
      expect(CardDeck.fromJson([1, null]).length, 1);
    });

    test('an icon key from before the catalogue is translated, not lost', () {
      // Early builds invented their own short names; a card saved then must
      // keep its icon rather than falling back to a folder.
      final restored = CardDeck.fromJson([
        {'id': 'x', 'name': 'x', 'colorKey': 'cyan', 'iconKey': 'game'},
      ]);
      expect(restored.folders.single.iconKey, 'sports_esports');
    });

    test('a colour or icon this build does not know falls back, not crashes', () {
      // A deck written by a future version with a bigger palette must still open.
      final restored = CardDeck.fromJson([
        {'id': 'x', 'name': 'x', 'colorKey': 'ultraviolet', 'iconKey': 'hologram'},
      ]);
      final card = restored.folders.single;
      expect(isKnownColorKey(card.colorKey), isTrue);
      expect(materialIcons.keys, contains(card.iconKey));
    });
  });

  group('search', () {
    test('matches label and package, case-insensitively', () {
      final installed = [app('com.spotify.music', label: 'Spotify'), app('com.b')];
      expect(searchApps(installed, 'SPOT').map((a) => a.label), ['Spotify']);
      expect(searchApps(installed, '  ').length, 2);
    });
  });

  group('rows of icons', () {
    DeckCard card({int? appRows}) => DeckCard(
          id: 'c1',
          name: 'Card',
          colorKey: cardPalette.first.key,
          iconKey: 'star',
          appRows: appRows ?? 1,
        );

    test('defaults to one row, and is left out of the json at the default', () {
      expect(card().appRows, 1);
      expect(card().toJson().containsKey('appRows'), isFalse);
    });

    test('round-trips through json', () {
      for (final rows in [2, 3, 4]) {
        final json = card(appRows: rows).toJson();
        expect(json['appRows'], rows);
        expect(DeckCard.fromJson(json).appRows, rows, reason: '$rows rows');
      }
    });

    test('a deck saved before rows existed reads back as one row', () {
      final json = card().toJson()..remove('appRows');
      expect(DeckCard.fromJson(json).appRows, 1);
    });

    test('a count outside the range is clamped rather than laid out', () {
      // A card taller than the stack can place would push every strip off the
      // box, so this is clamped on the way in like imageOffset is.
      expect(DeckCard.fromJson({...card().toJson(), 'appRows': 9}).appRows,
          maxAppRows);
      expect(DeckCard.fromJson({...card().toJson(), 'appRows': 0}).appRows, 1);
      expect(DeckCard.fromJson({...card().toJson(), 'appRows': -3}).appRows, 1);
      expect(card().copyWith(appRows: 99).appRows, maxAppRows);
      expect(card().copyWith(appRows: 0).appRows, 1);
    });

    test('copyWith leaves it alone when not asked', () {
      expect(card(appRows: 3).copyWith(name: 'Renamed').appRows, 3);
    });
  });
}
