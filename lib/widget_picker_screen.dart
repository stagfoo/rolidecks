import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'card_deck.dart';
import 'launcher_bridge.dart';
import 'stack_layout.dart';
import 'models.dart';
import 'theme.dart';

/// Which app widget goes on a widget card.
///
/// The launcher's own list rather than the system picker: ACTION_APPWIDGET_PICK
/// hands back an id allocated by the system picker itself, and on several OEM
/// builds returns nothing at all to an app that is not the default launcher.
/// Listing the providers is also what lets this screen say which widgets want
/// more height than a three-row card gives them, before one is chosen rather
/// than after.
///
/// Returns the chosen provider, or null if the user backed out.
Future<WidgetProvider?> pickWidget(BuildContext context, DeckCard card) {
  return Navigator.of(context).push<WidgetProvider>(
    MaterialPageRoute(builder: (context) => WidgetPickerScreen(card: card)),
  );
}

class WidgetPickerScreen extends StatefulWidget {
  const WidgetPickerScreen({super.key, required this.card});

  final DeckCard card;

  @override
  State<WidgetPickerScreen> createState() => _WidgetPickerScreenState();
}

class _WidgetPickerScreenState extends State<WidgetPickerScreen> {
  List<WidgetProvider>? _providers;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final providers = await LauncherBridge.instance.listWidgetProviders();
      if (mounted) setState(() => _providers = providers);
    } catch (e) {
      // Shown rather than swallowed: an empty list and a failed call look the
      // same on screen, and only one of them is worth retrying.
      if (mounted) setState(() => _error = e);
    }
  }

  List<WidgetProvider> get _matches {
    final all = _providers ?? const <WidgetProvider>[];
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return all;
    return [
      for (final provider in all)
        if (provider.label.toLowerCase().contains(query) ||
            provider.packageName.toLowerCase().contains(query))
          provider,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final color = colorOf(widget.card.colorKey);
    return Scaffold(
      backgroundColor: DeckColors.ground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            _search(),
            Expanded(child: _body(color)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(
                Icons.arrow_back_rounded,
                size: 22,
                color: DeckColors.text,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Choose a widget',
              style: deckText(size: 17, weight: 700, color: DeckColors.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _search() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: TextField(
        style: const TextStyle(color: DeckColors.text, fontSize: 15),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: DeckColors.surface,
          hintText: 'Search widgets',
          hintStyle: deckText(size: 14, color: DeckColors.textDim),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 19,
            color: DeckColors.textDim,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _body(Color color) {
    if (_error != null) {
      return _note('Could not read the widget list: $_error');
    }
    if (_providers == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF4F00)),
      );
    }
    if (_providers!.isEmpty) {
      return _note('No app widgets are installed on this phone.');
    }
    final matches = _matches;
    if (matches.isEmpty) return _note('Nothing matches “$_query”.');

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      itemCount: matches.length,
      itemBuilder: (context, index) => _row(matches[index], color),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          style: deckText(size: 13, color: DeckColors.textDim),
        ),
      );

  Widget _row(WidgetProvider provider, Color color) {
    // Three rows of card, less the name strip the card always keeps.
    final available = StackMetricsForPicker.widgetCardBodyHeight;
    final cramped = provider.minHeight > available && !provider.resizable;

    return GestureDetector(
      onTap: () => Navigator.pop(context, provider),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: DeckColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DeckColors.surfaceEdge),
        ),
        child: Row(
          children: [
            // The widget's own app icon: a widget is recognised by the app it
            // came from more than by its label, several of which are just the
            // app's name again.
            AppIconImage(
              app: LaunchableApp(
                packageName: provider.packageName,
                activityName: '',
                label: provider.label,
              ),
              size: 34,
              color: DeckColors.textDim,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: deckText(
                      size: 14,
                      weight: 600,
                      color: DeckColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      '${provider.minWidth}×${provider.minHeight} dp',
                      if (cramped) 'taller than a card',
                      if (provider.needsConfigure) 'has setup',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: deckText(
                      size: 11,
                      color: cramped ? color : DeckColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The height a widget actually gets on a three-row card.
///
/// Read off [StackStyle] rather than written out, so the picker's "taller than a
/// card" note and the card's real height come from the same numbers. A warning
/// computed from its own copy of them is worse than no warning: it would keep
/// claiming a widget fits long after the card stopped being that tall.
class StackMetricsForPicker {
  const StackMetricsForPicker._();

  static double get widgetCardBodyHeight =>
      StackStyle.standard.preferredCardHeight +
      (widgetCardRows - 1) * StackStyle.standard.rowHeight -
      StackStyle.headerHeight;
}
