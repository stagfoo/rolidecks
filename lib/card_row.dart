import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'models.dart';
import 'theme.dart';

/// The apps on a card: rows you scroll sideways, right on the card itself.
///
/// Always sideways, however many rows — a card is wide and short, and a grid
/// that wrapped downward would either shrink the icons or force the card taller
/// than the stack can afford. Scrolling horizontally also keeps the vertical
/// gesture free for the stack, which is the one that has to stay reliable.
///
/// With more than one row the apps fill column by column, so scrolling right
/// reaches new apps rather than re-reading the same ones a row lower.
class CardAppRow extends StatelessWidget {
  const CardAppRow({
    super.key,
    required this.apps,
    required this.cardColor,
    required this.onTap,
    this.onLongPress,
    this.showLabels = true,
    this.rows = 1,
  });

  final List<LaunchableApp> apps;
  final Color cardColor;

  /// Whether each app is named underneath. With names off the icons take the
  /// room the names were using rather than leaving a gap.
  final bool showLabels;

  /// How many rows of icons to lay the apps out in.
  final int rows;

  final ValueChanged<LaunchableApp> onTap;
  final ValueChanged<LaunchableApp>? onLongPress;

  static const _padding = EdgeInsets.fromLTRB(14, 10, 14, 2);
  static const _gap = 10.0;

  double _tileWidth() => showLabels ? 58 : 64;

  Widget _app(int index) {
    final app = apps[index];
    return _CardApp(
      onCard: onCardFor(cardColor),
      showLabel: showLabels,
      app: app,
      onTap: () => onTap(app),
      onLongPress: onLongPress == null ? null : () => onLongPress!(app),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The single-row case stays on the list it has always used rather than a
    // one-row grid. A grid tile is stretched to fill its row, where the list
    // lets the column size itself — so routing every card through the grid
    // would have quietly restyled every existing card, and a closed card is
    // supposed to look exactly as it did.
    if (rows <= 1) {
      return ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: _padding,
        // The card clips, so a bouncing overscroll would reveal nothing and just
        // look loose. Clamp it.
        physics: const ClampingScrollPhysics(),
        itemCount: apps.length,
        separatorBuilder: (context, index) => const SizedBox(width: _gap),
        itemBuilder: (context, index) => _app(index),
      );
    }

    return GridView.builder(
      scrollDirection: Axis.horizontal,
      padding: _padding,
      physics: const ClampingScrollPhysics(),
      // Horizontal scrolling puts the cross axis vertical, so crossAxisCount is
      // the row count and mainAxisExtent is each tile's width. Giving the width
      // outright avoids childAspectRatio, which would otherwise tie the tile's
      // width to whatever height the card happens to have.
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: rows,
        mainAxisExtent: _tileWidth(),
        mainAxisSpacing: _gap,
        crossAxisSpacing: 2,
      ),
      itemCount: apps.length,
      itemBuilder: (context, index) => _app(index),
    );
  }
}

class _CardApp extends StatelessWidget {
  const _CardApp({
    required this.app,
    required this.onCard,
    required this.showLabel,
    required this.onTap,
    this.onLongPress,
  });

  final LaunchableApp app;
  final Color onCard;
  final bool showLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: showLabel ? 58 : 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIconImage(
              app: app,
              size: showLabel ? 48 : 56,
              color: onCard.withValues(alpha: 0.5),
            ),
            if (showLabel) ...[
              const SizedBox(height: 4),
              Text(
                app.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: deckText(
                  size: 9.5,
                  weight: 600,
                  height: 1.1,
                  color: onCard.withValues(alpha: 0.75),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
