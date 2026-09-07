import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolidecks/app_icon.dart';
import 'package:rolidecks/card_deck.dart';
import 'package:rolidecks/deck_card_view.dart';
import 'package:rolidecks/models.dart';

const card = DeckCard(
  id: 'c',
  name: 'daily',
  colorKey: 'cyan',
  iconKey: 'star',
);

final apps = [
  for (var i = 0; i < 3; i++)
    LaunchableApp(
      packageName: 'com.app$i',
      activityName: 'com.app$i.Main',
      label: 'App $i',
    ),
];

Future<void> pump(WidgetTester tester, {required bool showLabels}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 379,
        child: DeckCardView(
          card: card.copyWith(showAppLabels: showLabels),
          height: 158,
          focused: true,
          apps: apps,
          totalInstalled: apps.length,
          onTap: () {},
          onAppTap: (_) {},
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rolidecks/launcher');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('app titles on a card', () {
    testWidgets('are shown by default', (tester) async {
      await pump(tester, showLabels: true);
      expect(find.text('App 0'), findsOneWidget);
      expect(find.text('App 2'), findsOneWidget);
    });

    testWidgets('can be hidden per card', (tester) async {
      await pump(tester, showLabels: false);
      expect(find.text('App 0'), findsNothing);
      // The card's own name is not an app title and stays.
      expect(find.text('daily'), findsOneWidget);
    });

    testWidgets('the icons take the room the titles were using',
        (tester) async {
      // Hiding the titles to leave a gap would be the worst of both.
      await pump(tester, showLabels: true);
      final withLabels =
          tester.getSize(find.byType(AppIconImage).first).height;

      await pump(tester, showLabels: false);
      final without = tester.getSize(find.byType(AppIconImage).first).height;

      expect(without, greaterThan(withLabels));
    });
  });

  group('the setting is part of the card', () {
    test('round-trips, and defaults to shown', () {
      final hidden = card.copyWith(showAppLabels: false);
      expect(DeckCard.fromJson(hidden.toJson()).showAppLabels, isFalse);
      expect(DeckCard.fromJson(card.toJson()).showAppLabels, isTrue);
    });

    test('a card saved before the option existed shows its titles', () {
      // Absent means shown: that is what those cards have always looked like.
      final older = card.toJson()..remove('showAppLabels');
      expect(DeckCard.fromJson(older).showAppLabels, isTrue);
    });

    test('one card hiding them does not affect another', () {
      var deck = CardDeck.seed();
      final first = deck.folders[0].id;
      deck = deck.updateCard(first, (c) => c.copyWith(showAppLabels: false));
      expect(deck.cards[deck.indexOfId(first)].showAppLabels, isFalse);
      expect(deck.folders[1].showAppLabels, isTrue);
    });
  });
}
