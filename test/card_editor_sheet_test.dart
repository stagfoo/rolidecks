import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolidecks/card_deck.dart';
import 'package:rolidecks/card_editor_sheet.dart';

const card = DeckCard(
  id: 'c',
  name: 'media',
  colorKey: 'cyan',
  iconKey: 'music',
);

/// Opens the editor and hands back whatever it returns.
Future<CardEditResult?> open(
  WidgetTester tester, {
  int position = 2,
  int folderCount = 5,
}) async {
  CardEditResult? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCardEditor(
                  context,
                  card,
                  position: position,
                  folderCount: folderCount,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

/// Opens the editor on an arbitrary card, for the all-apps case.
Future<CardEditResult?> openCard(
  WidgetTester tester,
  DeckCard subject, {
  int position = 2,
  int folderCount = 5,
}) async {
  CardEditResult? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showCardEditor(
                  context,
                  subject,
                  position: position,
                  folderCount: folderCount,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

/// The sheet scrolls, so the delete button can sit below the fold in the test
/// viewport even though it is reachable on the device.
Future<void> tapDelete(WidgetTester tester) async {
  final button = find.byIcon(Icons.delete_outline_rounded);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// The gradient container behind a picker tile, found via its glyph.
BoxDecoration decorationBehind(WidgetTester tester, IconData icon) {
  final container = find
      .ancestor(of: find.byIcon(icon), matching: find.byType(Container))
      .first;
  return tester.widget<Container>(container).decoration! as BoxDecoration;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the two picker tiles match', () {
    testWidgets('both wear the same rainbow, so they read as the same door', (
      tester,
    ) async {
      // The icon search used to be a plain grey square, which read as another
      // choice rather than a way out to the full set.
      await open(tester);
      final colour = decorationBehind(tester, Icons.colorize_rounded);
      final icon = decorationBehind(tester, Icons.search_rounded);

      expect(colour.gradient, isA<SweepGradient>());
      expect(icon.gradient, isA<SweepGradient>());
      expect(
        (icon.gradient! as SweepGradient).colors,
        (colour.gradient! as SweepGradient).colors,
      );
      expect(icon.borderRadius, colour.borderRadius);
    });
  });

  group('what was picked before comes back', () {
    testWidgets('a saved custom colour appears in the grid', (tester) async {
      SharedPreferences.setMockInitialValues({
        'rolidecks.recentColors.v1': ['#ff3366'],
      });
      await open(tester);
      await tester.pumpAndSettle();

      // Twelve presets, the picker tile, and the remembered colour.
      final swatches = find.byType(AnimatedContainer);
      expect(swatches, findsWidgets);
      expect(
        tester
            .widgetList<AnimatedContainer>(swatches)
            .map((c) => (c.decoration! as BoxDecoration).color)
            .contains(const Color(0xFFFF3366)),
        isTrue,
      );
    });

    testWidgets('a saved icon appears alongside the common ones', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'rolidecks.recentIcons.v1': ['rocket_launch'],
      });
      await open(tester);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.rocket_launch_rounded), findsOneWidget);
    });

    testWidgets('nothing saved yet just shows the presets', (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.rocket_launch_rounded), findsNothing);
    });
  });

  group('delete', () {
    testWidgets('carries the card position through untouched', (tester) async {
      // Reordering moved to a drag on the cards themselves; the sheet only
      // passes the position along so the caller has one result shape.
      await open(tester, position: 3);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Forward'), findsNothing);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('asks before removing a card', (tester) async {
      await open(tester);
      await tapDelete(tester);
      expect(find.text('Delete media?'), findsOneWidget);
      // Says plainly that the apps survive, since that is the thing a person
      // would otherwise hesitate over.
      expect(find.textContaining('apps are not removed'), findsOneWidget);
    });

    testWidgets('keeping the card leaves the editor open', (tester) async {
      await open(tester);
      await tapDelete(tester);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Done'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('previews the name as it is typed', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'podcasts');
      await tester.pump();
      // Once in the field, once in the live card preview.
      expect(find.text('podcasts'), findsNWidgets(2));
    });

    testWidgets('an emptied name falls back rather than blanking the card', (
      tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(find.text('media'), findsOneWidget);
    });
  });

  group('the all-apps card', () {
    testWidgets('opens in the editor and can be restyled', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await openCard(tester, CardDeck.allAppsCard);
      // The same controls as any other card.
      expect(find.text('Rows of icons'), findsOneWidget);
      expect(find.text('App titles'), findsOneWidget);
      expect(find.text('Colour'), findsOneWidget);
    });

    testWidgets('is not offered a delete button', (tester) async {
      // The deck refuses to remove it, so a delete button here could only do
      // nothing.
      SharedPreferences.setMockInitialValues({});
      await openCard(tester, CardDeck.allAppsCard);

      // Scrolled to the button row first, and Done asserted present in the same
      // breath: a bare findsNothing would pass just as well if the row were
      // merely below the fold, which would prove nothing at all.
      final done = find.text('Done');
      await tester.ensureVisible(done);
      await tester.pumpAndSettle();
      expect(done, findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    });

    testWidgets('an ordinary card still is', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await openCard(tester, card);
      await tapDelete(tester);
      expect(find.textContaining('Delete'), findsWidgets);
    });
  });
}
