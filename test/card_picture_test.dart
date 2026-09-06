import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolidecks/card_deck.dart';
import 'package:rolidecks/deck_card_view.dart';
import 'package:rolidecks/theme.dart';

const card = DeckCard(
  id: 'c',
  name: 'media',
  colorKey: 'cyan',
  iconKey: 'music_note',
);

Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 379, child: child)),
    );

DeckCardView view({String? imagePath, bool focused = true}) => DeckCardView(
      card: card,
      height: 158,
      focused: focused,
      apps: const [],
      totalInstalled: 0,
      imagePath: imagePath,
      onTap: () {},
      onAppTap: (_) {},
    );

extension on DeckCardView {
  DeckCardView copyWithOffset(double offset) => DeckCardView(
        card: card,
        height: height,
        focused: focused,
        apps: apps,
        totalInstalled: totalInstalled,
        imagePath: imagePath,
        imageOffset: offset,
        onTap: onTap,
        onAppTap: onAppTap,
      );
}

void main() {
  late Directory temp;
  late String imagePath;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('rolidecks_picture');
    // A one-pixel PNG is enough: what is under test is the composition, not
    // the decoding.
    final file = File('${temp.path}/card.png');
    file.writeAsBytesSync(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
    imagePath = file.path;
  });

  tearDownAll(() => temp.deleteSync(recursive: true));

  group('framing', () {
    testWidgets('the picture is aligned by the card offset', (tester) async {
      // A card is far wider than it is tall, so a cover crop throws away most
      // of a photo's height; the offset is which part is kept.
      await tester.pumpWidget(host(DeckCardView(
        card: card.copyWith(imageOffset: -0.6),
        height: 158,
        focused: true,
        apps: const [],
        totalInstalled: 0,
        imagePath: imagePath,
        imageOffset: -0.6,
        onTap: () {},
        onAppTap: (_) {},
      )));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.alignment, const Alignment(0, -0.6));
      expect(image.fit, BoxFit.cover);
    });

    testWidgets('an offset beyond the range is clamped, not honoured',
        (tester) async {
      // Past the ends there is nothing left to show.
      await tester.pumpWidget(host(view(imagePath: imagePath)
          .copyWithOffset(4)));
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.alignment, const Alignment(0, 1));
    });

    test('a stored offset round-trips, and a silly one is clamped', () {
      final saved = card.copyWith(imageOffset: -0.4).toJson();
      expect(DeckCard.fromJson(saved).imageOffset, -0.4);

      expect(
        DeckCard.fromJson({...saved, 'imageOffset': 9.0}).imageOffset,
        1.0,
      );
      expect(DeckCard.fromJson({...saved}..remove('imageOffset')).imageOffset, 0);
    });
  });

  group('a card without a picture', () {
    testWidgets('draws no image at all', (tester) async {
      await tester.pumpWidget(host(view()));
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('a card with a picture', () {
    testWidgets('draws it', (tester) async {
      await tester.pumpWidget(host(view(imagePath: imagePath)));
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fades to the card colour, not to black', (tester) async {
      // The name strip has to sit on exactly the colour it always did, or the
      // foreground already chosen for that colour stops being the right one.
      await tester.pumpWidget(host(view(imagePath: imagePath)));
      final gradients = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.gradient)
          .whereType<LinearGradient>();

      expect(gradients, isNotEmpty);
      final fade = gradients.first;
      expect(fade.colors.last, colorOf('cyan'));
      expect(fade.colors.first.a, 0);
      expect(fade.begin, Alignment.topCenter);
      expect(fade.end, Alignment.bottomCenter);
    });

    testWidgets('the name is still drawn over it', (tester) async {
      await tester.pumpWidget(host(view(imagePath: imagePath)));
      expect(find.text('media'), findsOneWidget);
    });

    testWidgets('a missing file does not take the card down', (tester) async {
      // The picture lives in app storage, but a file can still go missing —
      // the card must survive that rather than showing a broken box.
      await tester.pumpWidget(host(view(imagePath: '${temp.path}/gone.png')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('media'), findsOneWidget);
    });

    testWidgets('a covered card still shows its strip over the picture',
        (tester) async {
      await tester.pumpWidget(host(view(imagePath: imagePath, focused: false)));
      expect(find.text('media'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
