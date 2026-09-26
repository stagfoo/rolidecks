/// The look: near-black ground, saturated cards, black text on colour.
///
/// Borrowed from the rabbitOS stack — the colour is the whole interface, so
/// everything around it stays out of the way.
library;

import 'package:flutter/material.dart';

import 'card_style.dart';
import 'icon_catalogue.dart';

class DeckColors {
  static const ground = Color(0xFF08080A);

  /// What the home screen puts over the wallpaper, in place of [ground].
  ///
  /// Not fully transparent. App titles are near-white and the card labels are
  /// thin, and a bright or busy wallpaper leaves both unreadable — so the deck
  /// keeps its own ground colour and only thins it, which dims the wallpaper
  /// enough to read against while still plainly being the wallpaper. Only the
  /// home screen uses it: the full-screen editors stay on opaque [ground],
  /// where wallpaper behind a list of settings is just harder to read.
  ///
  /// The alpha is the whole of the effect and is meant to be adjusted by eye.
  static const wallpaperScrim = Color(0x5908080A);
  static const strip = Color(0xFF101014);
  static const surface = Color(0xFF1A1A1F);
  static const surfaceEdge = Color(0xFF2A2A32);
  static const text = Color(0xFFF4F4F7);
  static const textDim = Color(0xFF83838F);

  /// Text and glyphs on a palette card. Every palette colour is chosen so black
  /// reads on it, which is what keeps the stack looking like one thing. Custom
  /// colours are not chosen — see [onCardFor], which picks per colour.
  static const onCard = Color(0xFF0A0A0C);

  /// The light counterpart, for a custom colour too dark to take black.
  static const onCardLight = Color(0xFFF7F7FA);
}

class DeckMetrics {
  /// The action row along the bottom. Slim: it is two icons, and every pixel
  /// it takes is one the deck does not get.
  static const actionsHeight = 40.0;
  /// The full right band is the scrub area — a thin track would be a hairline
  /// target on a screen this small. The visible parts sit inside it.
  static const railWidth = 52.0;
  static const gutter = 12.0;
  static const cardRadius = 14.0;
}

Color colorOf(String key) => Color(colorForKey(key).value);

/// What to draw on top of [background].
///
/// The twelve palette colours were all picked to take black, so this only ever
/// changes its mind for a custom one. Letting the picker offer any colour
/// without this would let someone choose a navy card and lose the card's own
/// name into it.
///
/// The threshold is the WCAG contrast crossover: black wins on a background
/// whose relative luminance is above about 0.179, white below it.
Color onCardFor(Color background) =>
    background.computeLuminance() > 0.179
        ? DeckColors.onCard
        : DeckColors.onCardLight;

/// [onCardFor] for a stored key.
Color onCardForKey(String key) => onCardFor(colorOf(key));

/// Glyph for a stored icon key.
///
/// The model holds names, not Flutter types, so this is the one place the two
/// vocabularies meet — now a lookup into the generated catalogue rather than a
/// switch someone had to keep extending by hand.
IconData iconOf(String key) =>
    materialIcons[normaliseIconKey(key)] ?? Icons.folder_rounded;

/// Text in Lexend at a given weight.
///
/// Lexend ships as one variable font with a wght axis. Measured on this engine,
/// [TextStyle.fontWeight] alone does drive that axis — identical advance widths
/// to setting [FontVariation] explicitly — so this is not working around a bug.
/// Both are set anyway: the axis is then stated outright rather than depending
/// on that mapping continuing to hold, and fontWeight keeps fallback fonts and
/// any synthetic bolding honest. font_test.dart measures real widths, so if the
/// mapping ever changes it fails rather than silently flattening every weight.
TextStyle deckText({
  required double size,
  int weight = 400,
  Color color = DeckColors.text,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: 'Lexend',
    fontSize: size,
    color: color,
    fontWeight: FontWeight.values.firstWhere(
      (candidate) => candidate.value == weight,
      orElse: () => FontWeight.normal,
    ),
    fontVariations: [FontVariation('wght', weight.toDouble())],
    letterSpacing: letterSpacing,
    height: height,
  );
}

ThemeData buildDeckTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: DeckColors.ground,
    colorScheme: const ColorScheme.dark(
      surface: DeckColors.ground,
      primary: Color(0xFFFF4F00),
      onPrimary: DeckColors.onCard,
    ),
    fontFamily: 'Lexend',
    textTheme: const TextTheme().apply(
      fontFamily: 'Lexend',
      bodyColor: DeckColors.text,
      displayColor: DeckColors.text,
    ),
  );
}
