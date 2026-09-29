import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// The Android app widget on a widget card.
///
/// Hybrid composition rather than a plain [AndroidView]: a widget's content is
/// RemoteViews owned by another process, and in the virtual-display mode a plain
/// AndroidView uses, its taps land at the wrong coordinates and its list widgets
/// do not scroll at all. [PlatformViewLink] with an expensive controller is the
/// mode that composites the real view into the Flutter scene, which costs a
/// little on every frame the card is on screen and is the only mode a widget is
/// actually usable in.
class WidgetCardBody extends StatelessWidget {
  const WidgetCardBody({
    super.key,
    required this.widgetId,
    required this.onCard,
    this.onPick,
    this.safeMode = false,
  });

  /// The host's id for the bound widget, or null when the card has none yet.
  final int? widgetId;

  final Color onCard;

  /// Opens the picker. Null when the card is not editable from here.
  final VoidCallback? onPick;

  /// The previous launch never reached the deck, so no widget is built this time.
  ///
  /// This is the switch the crash-loop breaker actually throws. Hosting another
  /// process's views is the most involved thing this launcher does and the most
  /// likely thing to have killed it, so a launch that follows a death leaves it
  /// out and says so, rather than reproducing the crash and being relaunched
  /// into it again.
  final bool safeMode;

  static const _viewType = 'rolidecks/widget';

  @override
  Widget build(BuildContext context) {
    if (safeMode) return _safe(context);
    final id = widgetId;
    if (id == null) return _empty(context);

    return Padding(
      // Inset from the card's edges so the widget sits on the card rather than
      // bleeding to its rounded corners, and clear of the name strip below.
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: PlatformViewLink(
          viewType: _viewType,
          surfaceFactory: (context, controller) => AndroidViewSurface(
            controller: controller as AndroidViewController,
            // The widget gets the gestures inside it: a tap on a widget belongs
            // to the widget, and the vertical drag that moves the deck is on the
            // rail and the card's own strip, not in here.
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          ),
          onCreatePlatformView: (params) {
            return PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: _viewType,
              layoutDirection: TextDirection.ltr,
              creationParams: {'widgetId': id},
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => params.onFocusChanged(true),
            )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..create();
          },
        ),
      ),
    );
  }

  /// What a widget card shows when widgets are switched off.
  ///
  /// Says which state it is in rather than just drawing nothing: a blank card
  /// after a crash is indistinguishable from the blank card that was the
  /// original complaint.
  Widget _safe(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, size: 18, color: onCard),
            const SizedBox(height: 6),
            Text(
              'Widgets are off — the launcher crashed last time',
              textAlign: TextAlign.center,
              style: deckText(size: 12, weight: 600, color: onCard),
            ),
            const SizedBox(height: 2),
            Text(
              'Settings › Diagnostics has the crash, and the switch to turn '
              'them back on',
              textAlign: TextAlign.center,
              style: deckText(
                size: 10.5,
                color: onCard.withValues(alpha: 0.75),
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A widget card with nothing on it yet.
  ///
  /// Its own state rather than a blank: making the card and choosing what goes on
  /// it are two steps, and between them the card has to say which step it is
  /// waiting for.
  Widget _empty(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onPick,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: onCard.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: onCard.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.widgets_outlined, size: 15, color: onCard),
              const SizedBox(width: 6),
              Text(
                onPick == null ? 'no widget yet' : 'choose a widget',
                style: deckText(size: 12, weight: 600, color: onCard),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
