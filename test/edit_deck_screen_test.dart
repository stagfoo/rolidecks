import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolidecks/card_deck.dart';
import 'package:rolidecks/edit_deck_screen.dart';
import 'package:rolidecks/models.dart';

LaunchableApp app(String package, {String? label}) => LaunchableApp(
      packageName: package,
      activityName: '$package.Main',
      label: label ?? package.split('.').last,
    );

String idOf(String package) => '$package/$package.Main';

final installed = [
  app('com.a', label: 'Alpha'),
  app('com.b', label: 'Bravo'),
  app('com.c', label: 'Charlie'),
];

Future<void> pump(
  WidgetTester tester,
  CardDeck deck, {
  Size size = const Size(393, 451),
  ValueChanged<CardDeck>? onChanged,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    home: EditDeckScreen(
      deck: deck,
      installed: installed,
      onDeckChanged: onChanged ?? (_) {},
    ),
  ));
  await tester.pumpAndSettle();
}

/// The outer reorderable list. Each card also holds a horizontal app row, so a
/// bare Scrollable finder picks the wrong one.
Finder get deckList => find.byType(Scrollable).first;

void main() {
  group('the screen', () {
    testWidgets('lists every card and does not overflow', (tester) async {
      await pump(tester, CardDeck.seed());
      expect(tester.takeException(), isNull);
      expect(find.text('daily'), findsOneWidget);
    });

    testWidgets('scrolls, so a long deck stays reachable', (tester) async {
      // The whole reason dragging is confined to the handle: this list has to
      // be able to scroll.
      var deck = CardDeck.seed();
      for (var i = 0; i < 8; i++) {
        deck = deck.addCard('extra $i');
      }
      await pump(tester, deck);
      final last = find.text('extra 7');
      await tester.scrollUntilVisible(last, 100, scrollable: deckList);
      expect(last, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a move handle on every card', (tester) async {
      // Tall surface: the list only builds the rows it can show, so a
      // phone-sized viewport would find fewer handles than there are cards.
      final deck = CardDeck.seed();
      await pump(tester, deck, size: const Size(393, 1000));
      expect(
        find.byType(ReorderableDragStartListener),
        findsNWidgets(deck.folders.length),
      );
    });

    testWidgets('all apps is shown last with no handle of its own',
        (tester) async {
      await pump(tester, CardDeck.seed());
      final footer = find.textContaining('always last');
      await tester.scrollUntilVisible(footer, 100, scrollable: deckList);
      expect(footer, findsOneWidget);
      // The footer is not part of the reorderable list, so it carries no
      // handle of its own — asserted against the footer's own subtree rather
      // than a global count, which only reflects whatever is on screen.
      //
      // Anchored on the row's Container. It used to be the Opacity that dimmed
      // the row to say "not editable"; the row is editable now, so that wrapper
      // is gone and anchoring on it silently stopped finding anything.
      expect(
        find.descendant(
          of: find.ancestor(of: footer, matching: find.byType(Container)).first,
          matching: find.byType(ReorderableDragStartListener),
        ),
        findsNothing,
      );
    });

    testWidgets('all apps opens the editor when tapped', (tester) async {
      // It was dimmed and inert; its name, colour, icon and rows are choices
      // like any other card's now.
      await pump(tester, CardDeck.seed());
      final footer = find.textContaining('always last');
      await tester.scrollUntilVisible(footer, 100, scrollable: deckList);
      await tester.tap(footer);
      await tester.pumpAndSettle();
      expect(find.text('Rows of icons'), findsOneWidget);
      expect(find.text('Colour'), findsOneWidget);
    });

    testWidgets('all apps is offered no way to be filled', (tester) async {
      // No add chip on the footer: the deck drops apps filed under all apps, so
      // an add button could only look like it worked.
      await pump(tester, CardDeck.seed());
      final footer = find.textContaining('always last');
      await tester.scrollUntilVisible(footer, 100, scrollable: deckList);
      expect(
        find.descendant(
          of: find.ancestor(of: footer, matching: find.byType(Container)).first,
          matching: find.byIcon(Icons.add_rounded),
        ),
        findsNothing,
      );
    });

  });

  group('tapping a card opens its editor', () {
    testWidgets('from the name', (tester) async {
      await pump(tester, CardDeck.seed());
      await tester.tap(find.text('daily'));
      await tester.pumpAndSettle();
      expect(find.text('Colour'), findsOneWidget);
      expect(find.text('Icon'), findsOneWidget);
    });

    testWidgets('from empty space on the card, not just the name',
        (tester) async {
      // The name strip alone is a thin target; the card is the thing being
      // edited, so the whole of it should open the editor.
      await pump(tester, CardDeck.seed());
      final card = find.ancestor(
        of: find.text('daily'),
        matching: find.byType(GestureDetector),
      ).last;
      final box = tester.getRect(card);
      // Low on the card, below the name row and clear of the app chips.
      await tester.tapAt(Offset(box.right - 12, box.bottom - 6));
      await tester.pumpAndSettle();
      expect(find.text('Colour'), findsOneWidget);
    });

    testWidgets('but tapping add still opens the picker', (tester) async {
      // The chips are children, so they are hit first and keep their own jobs.
      await pump(tester, CardDeck.seed());
      await tester.tap(find.text('add').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Add to'), findsOneWidget);
      expect(find.text('Colour'), findsNothing);
    });

    testWidgets('and tapping an app still unfiles it', (tester) async {
      final deck = CardDeck.seed().assign(idOf('com.a'), 'card-seed-0');
      await pump(tester, deck);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Colour'), findsNothing);
    });
  });

  group('apps on a card', () {
    testWidgets('are shown, with an add button beside them', (tester) async {
      final deck = CardDeck.seed().assign(idOf('com.a'), 'card-seed-0');
      await pump(tester, deck, size: const Size(393, 1000));
      expect(find.text('Alpha'), findsOneWidget);
      // One "add" per folder card.
      expect(find.text('add'), findsNWidgets(deck.folders.length));
    });

    testWidgets('tapping an app takes it off the card', (tester) async {
      final deck = CardDeck.seed().assign(idOf('com.a'), 'card-seed-0');
      await pump(tester, deck);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('add opens a picker listing the installed apps',
        (tester) async {
      await pump(tester, CardDeck.seed());
      await tester.tap(find.text('add').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Add to'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
    });

    testWidgets('the picker files everything picked at once', (tester) async {
      var latest = CardDeck.seed();
      await pump(tester, latest, onChanged: (value) => latest = value);
      await tester.tap(find.text('add').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alpha'));
      await tester.tap(find.text('Bravo'));
      await tester.pumpAndSettle();
      expect(find.text('Add 2'), findsOneWidget);

      await tester.tap(find.text('Add 2'));
      await tester.pumpAndSettle();

      expect(latest.folders.first.appIds,
          containsAll([idOf('com.a'), idOf('com.b')]));
    });

    testWidgets('the picker will not add before anything is picked',
        (tester) async {
      await pump(tester, CardDeck.seed());
      await tester.tap(find.text('add').first);
      await tester.pumpAndSettle();
      // The confirm sits beside the search field now, disabled until
      // something is chosen.
      expect(find.text('Add'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('an app already on the card cannot be added twice',
        (tester) async {
      final deck = CardDeck.seed().assign(idOf('com.a'), 'card-seed-0');
      await pump(tester, deck);
      await tester.tap(find.text('add').first);
      await tester.pumpAndSettle();
      expect(find.text('already on this card'), findsOneWidget);
    });

    testWidgets('an app filed elsewhere says where it will move from',
        (tester) async {
      final deck = CardDeck.seed().assign(idOf('com.a'), 'card-seed-1');
      await pump(tester, deck);
      await tester.tap(find.text('add').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('will move here'), findsOneWidget);
    });
  });
}
