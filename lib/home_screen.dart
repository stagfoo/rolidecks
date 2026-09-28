import 'dart:async';

import 'package:flutter/material.dart';

import 'card_deck.dart';
import 'app_cache.dart';
import 'app_menu_sheet.dart';
import 'deck_card_view.dart';
import 'deck_actions.dart';
import 'deck_store.dart';
import 'diagnostics_screen.dart';
import 'edit_deck_screen.dart';
import 'folder_screen.dart';
import 'card_editor_sheet.dart';
import 'launcher_bridge.dart';
import 'saved_shortcuts.dart';
import 'models.dart';
import 'side_rail.dart';
import 'stack_layout.dart';
import 'theme.dart';

/// The home screen: a vertical stack of coloured cards with a pull knob down
/// the right edge, the last card being everything installed.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  final _store = DeckStore();
  final _appCache = AppCache();
  final _savedShortcuts = SavedShortcutStore();

  List<LaunchableApp> _installed = const [];
  CardDeck _deck = CardDeck.normalised(const []);

  /// Each card's apps, resolved once when the deck or the installed list
  /// changes rather than in build. The all-apps card sorts every app on the
  /// phone, and doing that per card per frame is a hundred-element sort in the
  /// middle of an animation.
  Map<String, List<LaunchableApp>> _appsByCard = const {};

  /// Card id to picture path, read off disk rather than stored in the deck.
  /// The picker is another app and can outlive this activity, so the file
  /// arriving is the record — there is nothing to deliver or lose.
  Map<String, String> _cardImages = const {};
  int _focused = 0;
  final _scroll = ScrollController();
  StackSpec? _lastSpec;


  bool _loading = true;
  bool _isDefault = true;
  StreamSubscription<String>? _packageSub;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _packageSub =
        LauncherBridge.instance.packageChanges.listen((_) => _refreshApps());
    LauncherBridge.instance.onPlatformCalls(
      onHomePressed: () {
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        setState(() => _focused = 0);
      },
      onShortcutsChanged: _resumeRefresh,
      onShortcutFailed: () => _toast('That app could not make a shortcut'),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _packageSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Coming back to the launcher is the moment anything missed by the package
  /// broadcasts would show up — a shortcut added, an app renamed, a profile
  /// changed. The refresh is off the critical path and only redraws if the list
  /// actually moved, so paying it on every resume costs nothing visible.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resumeRefresh();
  }

  Future<void> _openEditDeck() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditDeckScreen(
          deck: _deck,
          installed: _installed,
          onDeckChanged: _update,
        ),
      ),
    );
    if (!mounted) return;
    // A card deleted in there leaves its picture behind otherwise.
    await _reloadCardImages();
    if (mounted) setState(() => _focused = _focused.clamp(0, _deck.length - 1));
  }

  Future<void> _load() async {
    // The deck and the app snapshot both come from local storage, so the real
    // launcher — cards, and the apps on them — is on screen from the first
    // frame. The platform is asked afterwards and only redraws if it disagrees.
    var loaded = await _store.load();
    if (loaded == null || loaded.folders.isEmpty) {
      // First run: a stack with nothing but "all apps" looks broken, and naming
      // a few starter cards is a better first impression than an empty screen.
      loaded = CardDeck.seed();
      await _store.save(loaded);
    }
    final deck = loaded;
    // Before the first list is built, so a shortcut made just before the
    // launcher was killed is already in it.
    await _collectPendingShortcuts();
    // Widget ids outlive the cards that held them — a card deleted while the
    // launcher was not running, or a deck restored from a backup — and an id
    // nobody releases keeps its app doing update work for a widget on no screen
    // at all. Done on load, where the full deck is known.
    await _reapWidgets(deck);
    final images = await LauncherBridge.instance.cardImages();
    final cached = await _appCache.load();

    if (!mounted) return;
    setState(() {
      _deck = deck;
      _cardImages = images;
      if (cached != null) {
        _installed = cached.apps;
        _appsByCard = _resolveApps(deck, cached.apps);
      }
      _loading = false;
    });

    // Wrapped, because this had no error handling at all: one failing platform
    // call left the launcher running on nothing but its cache, silently, with
    // the cause three method calls away from the symptom.
    try {
      final results = await Future.wait([
        _everything(),
        LauncherBridge.instance.isDefaultLauncher(),
      ]);
      if (!mounted) return;

      setState(() => _isDefault = results[1] as bool);
      await _adopt(results[0] as List<LaunchableApp>);
    } catch (e) {
      if (mounted) _toast('Could not read the app list: $e');
    }
  }

  /// Takes a freshly fetched list, redrawing and rewriting the snapshot only if
  /// it differs from what is already shown.
  Future<void> _adopt(List<LaunchableApp> apps) async {
    if (!appListsDiffer(_installed, apps)) return;
    if (!mounted) return;
    setState(() {
      _installed = apps;
      _appsByCard = _resolveApps(_deck, apps);
    });
    await _appCache.save(apps);
  }

  Future<void> _refreshApps() async {
    await _adopt(await _everything());
  }

  /// Everything launchable: apps, shortcuts the system remembers, and the
  /// older kind only this launcher remembers.
  /// Picks up anything the Android side recorded while the launcher was away.
  ///
  /// Results are written down there before they are announced, because this
  /// activity can be destroyed while another app's confirm screen is up — a
  /// message sent straight down the channel then arrives with nobody listening.
  Future<int> _collectPendingShortcuts() async {
    final pending = await LauncherBridge.instance.takePendingShortcuts();
    var added = 0;
    for (final record in pending) {
      final app = record.toApp();
      if (app == null) continue;
      await _savedShortcuts.add(StoredShortcut(app: app, icon: record.icon));
      added++;
    }
    return added;
  }

  /// Coming back is when a shortcut made in another app is collected.
  Future<void> _resumeRefresh() async {
    final added = await _collectPendingShortcuts();
    await _reloadCardImages();
    await _refreshApps();
    if (added > 0) {
      _toast(added == 1
          ? 'Shortcut added — find it under all apps'
          : '$added shortcuts added — find them under all apps');
    }
  }

  Future<void> _reloadCardImages() async {
    final images = await LauncherBridge.instance.cardImages();
    if (!mounted) return;
    setState(() => _cardImages = images);
  }

  Future<List<LaunchableApp>> _everything() async {
    final results = await Future.wait([
      LauncherBridge.instance.listEverything(),
      _savedShortcuts.load(),
    ]);
    final stored = results[1] as List<StoredShortcut>;
    for (final entry in stored) {
      // Their icons came with them rather than from the platform, so seed the
      // cache the icon widget reads.
      LauncherBridge.instance.primeIcon(entry.app.id, entry.icon);
    }
    // The system's own list is kept as a second source: it catches anything
    // pinned before this launcher started keeping its own copy. Merged by id,
    // so a shortcut in both appears once.
    final merged = <String, LaunchableApp>{
      for (final app in results[0] as List<LaunchableApp>) app.id: app,
    };
    for (final entry in stored) {
      merged[entry.app.id] = entry.app;
    }
    return merged.values.toList();
  }

  /// Opens [app], and says so when it does not open.
  ///
  /// The bool that `open` returns used to be dropped at the call site, so a
  /// shortcut whose target had been uninstalled, renamed, or locked behind
  /// Android 12's non-exported-activity rule was indistinguishable from a tap
  /// that had not registered: the tile dimmed and nothing else happened. The
  /// Android side writes the reason down under `lastLaunch`, so the toast can
  /// point at Diagnostics, where the actual cause is spelled out.
  Future<void> _launch(LaunchableApp app) async {
    final opened = await LauncherBridge.instance.open(app);
    if (opened || !mounted) return;
    _toast('${app.label} did not open — see Diagnostics for why');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: DeckColors.surface,
        content: Text(message, style: deckText(size: 12)),
      ),
    );
  }

  /// The manual refresh, for when something changed that neither a package
  /// broadcast nor a resume caught.
  Future<void> _refreshNow() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apps = await _everything();
      final changed = appListsDiffer(_installed, apps);
      await _adopt(apps);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: DeckColors.surface,
          duration: const Duration(seconds: 2),
          content: Text(
            changed ? 'App list updated' : '${apps.length} apps, nothing new',
            style: deckText(size: 12),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  static Map<String, List<LaunchableApp>> _resolveApps(
    CardDeck deck,
    List<LaunchableApp> installed,
  ) {
    return {
      for (final card in deck.cards) card.id: card.resolve(installed),
    };
  }

  Future<void> _update(CardDeck deck) async {
    setState(() {
      _deck = deck;
      _appsByCard = _resolveApps(deck, _installed);
      _focused = _focused.clamp(0, deck.length - 1);
    });
    await _store.save(deck);
  }

  @override
  Widget build(BuildContext context) {
    // Back must not leave the home screen — there is nothing behind it, and
    // letting the activity finish makes the system restart it.
    return PopScope(
      canPop: false,
      child: Scaffold(
        // Translucent, so the system wallpaper shows through. Three other
        // layers have to agree for this to be visible at all — the window
        // background and windowShowWallpaper in styles.xml, and Flutter's
        // transparent BackgroundMode in MainActivity — and an opaque colour at
        // any one of them puts the black back.
        backgroundColor: DeckColors.wallpaperScrim,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF4F00)),
                )
              : Column(
                  children: [
                    // Nothing above the deck: the front card starts at the top
                    // edge of the screen.
                    Expanded(child: _stack()),
                    if (!_isDefault) _defaultLauncherBanner(),
                    DeckActions(
                      onSettings: LauncherBridge.instance.openSettings,
                      onAdd: _openEditDeck,
                      onRefresh: _refreshNow,
                      refreshing: _refreshing,
                      onLongPressSettings: _showMetrics,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _defaultLauncherBanner() {
    return Material(
      color: const Color(0xFFFF4F00).withValues(alpha: 0.16),
      child: InkWell(
        onTap: LauncherBridge.instance.openHomeSettings,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            children: [
              Icon(Icons.home_outlined, size: 15, color: Color(0xFFFF7A3C)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Not the home app yet — tap to set Rolidecks as default',
                  style: TextStyle(fontSize: 11, color: DeckColors.text),
                ),
              ),
              Icon(Icons.chevron_right, size: 15, color: Color(0xFFFF7A3C)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stack() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(DeckMetrics.gutter, 4, 4, 4),
      // One layout pass for both. Solving inside the stack and stashing the
      // result for the rail meant the rail was built before that ran, so it
      // used the previous frame's numbers — and none at all on the first.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spec = solveStack(
            height: constraints.maxHeight,
            cardCount: _deck.length,
            focusedIndex: _focused,
            rows: _rowCounts(),
          );
          // Kept so the knob can scroll a long deck to the card it just
          // selected; a plain field, not setState, since this is build.
          _lastSpec = spec;

          // Measured against the rail's own band, not the revealed deck. The
          // deck's height moves with the open card's row count, and sizing the
          // track to it fed focus changes back into the mapping that produced
          // them — see StackSpec.railHeight.
          final reveal = spec.railHeight.clamp(0.0, constraints.maxHeight);
          final below = (constraints.maxHeight - spec.railTop - reveal)
              .clamp(0.0, double.infinity);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _restingStack(spec)),
              Padding(
                // The rail is exactly as tall as the cards and sits with them,
                // so a centred deck reads as one centred thing rather than a
                // block of cards beside a full-height track.
                padding: EdgeInsets.only(top: spec.railTop, bottom: below),
                child: _rail(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rail() {
    return SizedBox(
      width: DeckMetrics.railWidth,
      child: SideRail(
        cardCount: _deck.length,
        focusedIndex: _focused,
        onFocusChanged: _focus,
        color: colorOf(_deck[_focused.clamp(0, _deck.length - 1)].colorKey),
      ),
    );
  }

  /// Opens the editor on one card, straight from the deck.
  ///
  /// The widget picker lives in the editor, so "choose a widget" on an empty
  /// widget card goes there rather than duplicating the bind-and-release
  /// handling that has to happen around the pick.
  Future<void> _editCardFromHome(DeckCard card) async {
    final result = await showCardEditor(
      context,
      card,
      position: _deck.folders.indexWhere((entry) => entry.id == card.id),
      folderCount: _deck.folders.length,
      apps: card.resolve(_installed),
    );
    if (result == null) return;
    final widgetId = card.widgetId;
    if (result.deleted && widgetId != null) {
      await LauncherBridge.instance.releaseWidget(widgetId);
    }
    await _update(
      result.deleted
          ? _deck.removeCard(card.id)
          : _deck.updateCard(card.id, (_) => result.card),
    );
  }

  /// Hands back every widget this launcher holds that no card is using.
  Future<void> _reapWidgets(CardDeck deck) async {
    try {
      await LauncherBridge.instance.reapWidgets([
        for (final card in deck.cards)
          if (card.widgetId case final id?) id,
      ]);
    } catch (e) {
      // A failed reap leaks an id until the next launch, which is a great deal
      // better than a launcher that will not start.
    }
  }

  /// Rows per card, parallel to the deck. One place, so the layout the rail
  /// scrolls to is solved from the same numbers the deck is drawn with.
  List<int> _rowCounts() => [for (final card in _deck.cards) card.rows];

  Widget _restingStack(StackSpec spec) {
    final stack = SizedBox(
      height: spec.totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Back to front: the last card — always all apps — is painted first
          // and stays behind everything.
          for (final i in spec.paintOrder)
            AnimatedPositioned(
              key: ValueKey(_deck[i].id),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              // The focused card runs up behind the one in front of it, so the
              // background cannot show through that card's rounded bottom
              // corners.
              top: spec.topOf(i) - _bleedFor(i, spec),
              height: spec.heightOf(i) + _bleedFor(i, spec),
              child: DeckCardView(
                card: _deck[i],
                height: spec.heightOf(i),
                topBleed: _bleedFor(i, spec),
                focused: i == spec.focusedIndex,
                // Only when something is actually in front of it: the first
                // card has nothing above, so its rounded top reads correctly
                // against the background.
                flushTop: i == spec.focusedIndex && i > 0,
                imagePath: _cardImages[_deck[i].id],
                imageOffset: _deck[i].imageOffset,
                apps: _appsByCard[_deck[i].id] ?? const [],
                totalInstalled: _installed.length,
                onTap: () => i == _focused
                    ? _openCard(_deck[i])
                    : setState(() => _focused = i),
                onLongPress: _openEditDeck,
                // Only on the open card, and only while it has no widget: the
                // empty state is the one thing on a widget card worth tapping,
                // and on a covered card it is not visible to tap.
                onPickWidget: _deck[i].isWidget &&
                        !_deck[i].hasWidget &&
                        i == spec.focusedIndex
                    ? () => _editCardFromHome(_deck[i])
                    : null,
                onAppTap: _launch,
                onAppLongPress: (app) => _showAppMenu(_deck[i], app),
              ),
            ),
        ],
      ),
    );

    return ClipRect(
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -200) {
            _moveFocus(1);
          } else if (velocity > 200) {
            _moveFocus(-1);
          }
        },
        child: spec.overflows
            ? SingleChildScrollView(
                controller: _scroll,
                physics: const ClampingScrollPhysics(),
                child: stack,
              )
            : stack,
      ),
    );
  }

  /// How far card [i] runs up behind the card in front of it. Only the focused
  /// card needs it, and only when something is actually in front.
  double _bleedFor(int i, StackSpec spec) =>
      i == spec.focusedIndex && i > 0 ? DeckMetrics.cardRadius : 0;

  /// Moves focus and, when the deck is long enough to scroll, brings the newly
  /// focused card into view — otherwise the knob can select a card that is off
  /// the bottom of the stack.
  void _focus(int index) {
    setState(() => _focused = index);
    if (!_scroll.hasClients) return;
    final previous = _lastSpec;
    if (previous == null) return;

    // Solved for the card being focused, not read off the last frame's spec.
    // A card's height depends on its rows, so moving focus changes the layout —
    // and asking the outgoing layout where the incoming card sits scrolled to
    // where it used to be. The extent comes from the same new layout rather than
    // from the controller, whose maxScrollExtent is still the old one until this
    // rebuild lands.
    final spec = solveStack(
      height: previous.boxHeight,
      cardCount: _deck.length,
      focusedIndex: index,
      rows: _rowCounts(),
    );
    if (!spec.overflows) return;
    final extent =
        (spec.totalHeight - spec.boxHeight).clamp(0.0, double.infinity);
    final target = (spec.revealTopOf(index) - spec.peek).clamp(0.0, extent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _moveFocus(int delta) {
    setState(() => _focused = (_focused + delta).clamp(0, _deck.length - 1));
  }

  Future<void> _openCard(DeckCard card) async {
    // A widget card has no folder to open — the widget takes the taps inside it,
    // so this only fires on the card's name strip, where the useful thing is the
    // card's own settings rather than a folder that would always be empty.
    if (card.isWidget) return _editCardFromHome(card);

    final chosen = await Navigator.of(context).push<LaunchableApp>(
      MaterialPageRoute(
        builder: (context) => FolderScreen(
          card: card,
          deck: _deck,
          installed: _installed,
          onDeckChanged: _update,
          onRemoveShortcut: _removeShortcut,
        ),
      ),
    );
    if (chosen != null) await _launch(chosen);
  }

  /// Filing an app straight from the card it is sitting on, so the common case
  /// never needs the all-apps screen.
  Future<void> _showAppMenu(DeckCard from, LaunchableApp app) async {
    final choice = await showAppMenuSheet(
      context,
      app: app,
      deck: _deck,
      from: from,
    );
    switch (choice) {
      case null:
        return;
      case UnfileApp():
        await _update(_deck.unassign(app.id));
      case ShowAppInfo():
        await LauncherBridge.instance.openAppInfo(app.packageName);
      case FileUnder(:final cardId):
        await _update(_deck.assign(app.id, cardId));
      case RemoveShortcut():
        await _removeShortcut(app);
    }
  }

  /// Deletes a shortcut, and offers to put it back.
  ///
  /// One made in another app cannot always be made again — a legacy one is an
  /// intent that only that app knows how to build — so an undo matters more
  /// here than a confirmation would.
  Future<void> _removeShortcut(LaunchableApp app) async {
    final removed = await _savedShortcuts.remove(app.id);
    await _update(_deck.unassign(app.id));
    await _refreshApps();
    if (!mounted || removed == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: DeckColors.surface,
        duration: const Duration(seconds: 6),
        content: Text('Deleted ${app.label}', style: deckText(size: 12)),
        action: SnackBarAction(
          label: 'Undo',
          textColor: const Color(0xFFFF7A3C),
          onPressed: () async {
            await _savedShortcuts.add(removed);
            await _refreshApps();
          },
        ),
      ),
    );
  }

  /// A screen, not a snackbar: the long-press was showing one that evidently
  /// never arrived, which left five releases with no signal at all.
  void _showMetrics() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const DiagnosticsScreen(),
      ),
    );
  }
}
