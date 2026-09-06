import 'package:flutter_test/flutter_test.dart';
import 'package:rolidecks/stack_layout.dart';

void main() {
  // The Mind One in portrait: 1080 × 1240 physical, about 393 × 451 dp at a
  // 2.75 density. The stack gets what's left under the clock strip.
  const stackHeight = 390.0;

  group('solveStack on the Mind One panel', () {
    test('fits a six-card deck without overflowing', () {
      final spec = solveStack(height: stackHeight, cardCount: 6, focusedIndex: 0);
      expect(spec.totalHeight, lessThanOrEqualTo(stackHeight + 0.01));
      expect(spec.peek, greaterThanOrEqualTo(StackStyle.standard.minPeek));
      expect(spec.cardHeight, greaterThan(spec.peek));
    });

    test('the open card reveals much more than a covered strip', () {
      final spec = solveStack(height: stackHeight, cardCount: 6, focusedIndex: 2);
      expect(spec.revealOf(2), spec.cardHeight);
      expect(spec.revealOf(0), spec.peek);
      expect(spec.cardHeight, greaterThan(spec.peek * 2));
    });

    test('focusing the last card still shows every strip above it', () {
      final spec = solveStack(height: stackHeight, cardCount: 6, focusedIndex: 5);
      for (var i = 0; i < 5; i++) {
        expect(spec.revealOf(i), spec.peek, reason: 'card $i');
      }
      expect(spec.revealOf(5), spec.cardHeight);
    });

    test('every covered card reveals exactly one strip, at its bottom', () {
      // A covered card is behind the one in front of it, so the only part of
      // it you can see is the strip below that card's bottom edge — which is
      // why the card's name lives down there.
      for (final focus in [0, 3, 5]) {
        final spec =
            solveStack(height: stackHeight, cardCount: 6, focusedIndex: focus);
        for (var i = 0; i < spec.cardCount; i++) {
          if (i == focus) continue;
          expect(
            spec.revealTopOf(i),
            closeTo(spec.topOf(i) + spec.cardHeight - spec.peek, 0.01),
            reason: 'focus $focus, card $i',
          );
          expect(spec.revealOf(i), spec.peek, reason: 'focus $focus, card $i');
        }
      }
    });

    test('strips land a peek apart down the stack', () {
      final spec = solveStack(height: stackHeight, cardCount: 6, focusedIndex: 0);
      for (var i = 1; i < spec.cardCount; i++) {
        expect(
          spec.revealTopOf(i) - spec.revealTopOf(i - 1),
          closeTo(i == 1 ? spec.cardHeight : spec.peek, 0.01),
          reason: 'card $i',
        );
      }
    });

    test('nothing in front of the focused card overlaps it', () {
      // Cards in front slide up until their bottoms meet its top edge, so the
      // focused card is revealed whole without being lifted out of the stack.
      for (final focus in [1, 3, 5]) {
        final spec =
            solveStack(height: stackHeight, cardCount: 6, focusedIndex: focus);
        expect(spec.revealOf(focus), spec.cardHeight, reason: 'focus $focus');
        for (var i = 0; i < focus; i++) {
          expect(
            spec.topOf(i) + spec.cardHeight,
            lessThanOrEqualTo(spec.topOf(focus) + 0.01),
            reason: 'card $i must clear the focused card',
          );
        }
        expect(
          spec.topOf(focus - 1) + spec.cardHeight,
          closeTo(spec.topOf(focus), 0.01),
        );
      }
    });

    test('the first card is the front of the deck and all apps the back', () {
      // Painted back to front, so the last card — always all apps — is behind
      // everything and the first card is in front.
      final spec = solveStack(height: stackHeight, cardCount: 6, focusedIndex: 0);
      expect(spec.paintOrder.first, 5);
      expect(spec.paintOrder.last, 0);
      expect(spec.paintOrder, hasLength(6));
      expect(spec.paintOrder.toSet(), {0, 1, 2, 3, 4, 5});
    });

    test('the whole deck occupies the same band wherever focus is', () {
      for (var focus = 0; focus < 6; focus++) {
        final spec =
            solveStack(height: stackHeight, cardCount: 6, focusedIndex: focus);
        final top = spec.revealTopOf(0);
        final bottom = spec.topOf(5) + spec.cardHeight;
        expect(top, closeTo(spec.originY, 0.01), reason: 'focus $focus');
        expect(bottom - top, closeTo(spec.totalHeight, 0.01),
            reason: 'focus $focus');
      }
    });

    test('every card is drawn at full height, focused or not', () {
      // Laying collapsed cards out at strip height is what made them bars and
      // overflowed their contents by two pixels on the device.
      final spec = solveStack(height: stackHeight, cardCount: 6, focusedIndex: 0);
      for (var i = 0; i < spec.cardCount; i++) {
        expect(spec.heightOf(i), spec.cardHeight, reason: 'card $i');
      }
    });

    test('a strip is always tall enough for the card header', () {
      // The header holds the card's name; a strip shorter than it clips the
      // name, which is exactly the bug the first build shipped.
      for (final count in [2, 6, 9, 12]) {
        final spec = solveStack(
            height: stackHeight, cardCount: count, focusedIndex: 0);
        expect(spec.peek, greaterThanOrEqualTo(StackStyle.headerHeight - 0.01),
            reason: '$count cards');
      }
    });

    test('the revealed stack fits the box whatever is focused', () {
      for (var focus = 0; focus < 8; focus++) {
        final spec =
            solveStack(height: stackHeight, cardCount: 8, focusedIndex: focus);
        expect(spec.totalHeight, lessThanOrEqualTo(stackHeight + 0.01),
            reason: 'focus $focus');
        expect(spec.overflows, isFalse, reason: 'focus $focus');
      }
    });

    test('holds together wherever focus is', () {
      for (var focus = 0; focus < 8; focus++) {
        final spec = solveStack(height: stackHeight, cardCount: 8, focusedIndex: focus);
        expect(spec.totalHeight, lessThanOrEqualTo(stackHeight + 0.01),
            reason: 'focus $focus');
        // The front card's body runs above the box and is clipped once
        // anything is focused behind it; what has to stay in bounds is the
        // strip you can actually see.
        expect(spec.revealTopOf(0), greaterThanOrEqualTo(spec.originY - 0.01),
            reason: 'focus $focus');
      }
    });

    test('a short deck is centred rather than pinned to the top', () {
      final spec = solveStack(height: stackHeight, cardCount: 2, focusedIndex: 0);
      expect(spec.originY, greaterThan(0));
      expect(spec.originY, closeTo((stackHeight - spec.totalHeight) / 2, 0.01));
    });

    test('a crowded deck overflows to be scrolled, it does not crush strips', () {
      // Twenty cards do not fit at readable sizes. Both floors hold and the
      // stack reports that it overflows; thinning the strips until names clip
      // is not a trade worth making.
      final spec = solveStack(height: stackHeight, cardCount: 20, focusedIndex: 0);
      expect(spec.cardHeight,
          greaterThanOrEqualTo(StackStyle.standard.minCardHeight - 0.01));
      expect(spec.peek,
          greaterThanOrEqualTo(StackStyle.standard.minPeek - 0.01));
      expect(spec.overflows, isTrue);
    });

    test('a deck that fits does not claim to overflow', () {
      final spec = solveStack(height: stackHeight, cardCount: 6, focusedIndex: 0);
      expect(spec.overflows, isFalse);
    });
  });

  group('landscape', () {
    // The panel is 1080 x 1240, so turning the phone gives 1240 x 1080: wider
    // and shorter. The deck has no separate landscape layout — it solves for
    // whatever box it is handed — so what has to hold is that the box a
    // rotation produces still works.
    const landscapeHeight = 343.0;

    test('a normal deck still fits when the phone is turned', () {
      for (final count in [3, 5, 7]) {
        final spec = solveStack(
            height: landscapeHeight, cardCount: count, focusedIndex: 0);
        expect(spec.overflows, isFalse, reason: '$count cards');
        expect(spec.peek, greaterThanOrEqualTo(StackStyle.headerHeight - 0.01),
            reason: '$count cards');
      }
    });

    test('the card stays big enough to be worth opening', () {
      final spec =
          solveStack(height: landscapeHeight, cardCount: 7, focusedIndex: 0);
      expect(spec.cardHeight, greaterThan(spec.peek * 3));
    });

    test('the same deck holds together in both orientations', () {
      for (final height in [401.0, landscapeHeight]) {
        for (var focus = 0; focus < 7; focus++) {
          final spec =
              solveStack(height: height, cardCount: 7, focusedIndex: focus);
          expect(spec.revealOf(focus), spec.cardHeight,
              reason: 'height $height focus $focus');
          expect(spec.totalHeight, lessThanOrEqualTo(height + 0.01),
              reason: 'height $height focus $focus');
        }
      }
    });
  });

  group('solveStack edges', () {
    test('an empty deck produces no height and does not divide by zero', () {
      final spec = solveStack(height: stackHeight, cardCount: 0, focusedIndex: 0);
      expect(spec.totalHeight, 0);
    });

    test('a single card is the whole stack', () {
      final spec = solveStack(height: stackHeight, cardCount: 1, focusedIndex: 0);
      expect(spec.totalHeight, spec.cardHeight);
      expect(spec.revealOf(0), spec.cardHeight);
    });

    test('an out-of-range focus is clamped, not thrown', () {
      expect(solveStack(height: stackHeight, cardCount: 4, focusedIndex: 99).focusedIndex, 3);
      expect(solveStack(height: stackHeight, cardCount: 4, focusedIndex: -3).focusedIndex, 0);
    });

    test('a zero-height box still yields positive card heights', () {
      final spec = solveStack(height: 0, cardCount: 5, focusedIndex: 0);
      expect(spec.peek, greaterThan(0));
      expect(spec.cardHeight, greaterThan(0));
    });
  });

  group('solveKnob', () {
    const track = 340.0;

    test('sits at the top for the first card and the bottom for the last', () {
      final first = solveKnob(trackHeight: track, cardCount: 6, focusedIndex: 0);
      final last = solveKnob(trackHeight: track, cardCount: 6, focusedIndex: 5);
      expect(first.top, 0);
      expect(last.top + last.height, closeTo(track, 0.01));
    });

    test('shrinks as the deck grows, like a scrollbar thumb', () {
      final few = solveKnob(trackHeight: track, cardCount: 3, focusedIndex: 0);
      final many = solveKnob(trackHeight: track, cardCount: 12, focusedIndex: 0);
      expect(many.height, lessThan(few.height));
    });

    test('never shrinks below a grabbable size', () {
      final knob = solveKnob(trackHeight: track, cardCount: 200, focusedIndex: 0);
      expect(knob.height, greaterThanOrEqualTo(44));
    });

    test('stays on the track at every position', () {
      for (var i = 0; i < 9; i++) {
        final knob = solveKnob(trackHeight: track, cardCount: 9, focusedIndex: i);
        expect(knob.top, greaterThanOrEqualTo(-0.01), reason: 'card $i');
        expect(knob.top + knob.height, lessThanOrEqualTo(track + 0.01),
            reason: 'card $i');
      }
    });

    test('a one-card deck fills the track rather than leaving a stub', () {
      final knob = solveKnob(trackHeight: track, cardCount: 1, focusedIndex: 0);
      expect(knob.height, track);
    });
  });

  group('cardIndexForKnobPosition', () {
    const track = 340.0;

    test('dragging to the ends selects the first and last card', () {
      expect(cardIndexForKnobPosition(y: 0, trackHeight: track, cardCount: 6), 0);
      expect(cardIndexForKnobPosition(y: track, trackHeight: track, cardCount: 6), 5);
    });

    test('is the inverse of solveKnob, so the grip lands under the finger', () {
      // Round-tripping matters: if these disagree the knob jumps away from the
      // finger mid-drag, which feels broken even when the selection is right.
      for (var i = 0; i < 7; i++) {
        final knob = solveKnob(trackHeight: track, cardCount: 7, focusedIndex: i);
        expect(
          cardIndexForKnobPosition(
            y: knob.center,
            trackHeight: track,
            cardCount: 7,
          ),
          i,
          reason: 'card $i',
        );
      }
    });

    test('a drag beyond the track clamps to a real card', () {
      expect(cardIndexForKnobPosition(y: -500, trackHeight: track, cardCount: 5), 0);
      expect(cardIndexForKnobPosition(y: 5000, trackHeight: track, cardCount: 5), 4);
    });

    test('a single-card deck always answers zero', () {
      expect(cardIndexForKnobPosition(y: 200, trackHeight: track, cardCount: 1), 0);
    });
  });
}
