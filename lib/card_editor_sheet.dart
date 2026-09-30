import 'package:flutter/material.dart';

import 'card_deck.dart';
import 'card_style.dart';
import 'deck_card_view.dart';
import 'models.dart';
import 'launcher_bridge.dart';
import 'stack_layout.dart';
import 'widget_picker_screen.dart';
import 'color_picker_screen.dart';
import 'style_recents.dart';
import 'icon_picker_screen.dart';
import 'theme.dart';

/// What the editor hands back: the edited card, and where it should sit.
class CardEditResult {
  const CardEditResult({
    required this.card,
    required this.position,
    this.deleted = false,
  });

  final DeckCard card;

  /// Index among the folder cards. Unchanged unless the position controls were
  /// used, so the caller can skip the reorder entirely.
  final int position;

  /// The card should go. Its apps are not lost — they simply stop being filed
  /// and reappear under all apps.
  final bool deleted;
}

/// Name, colour, icon and position for one card.
///
/// The colour is the card's whole identity in the stack, so the sheet previews
/// the real thing at the top and updates it live as you pick — choosing from
/// swatches alone means guessing how a colour reads behind black text.
///
/// Reordering is not here: it is a drag on the cards themselves in arrange
/// mode, which is where a question about position belongs. The sheet still
/// carries the card's position through untouched so the caller has one result
/// shape either way.
Future<CardEditResult?> showCardEditor(
  BuildContext context,
  DeckCard card, {
  required int position,
  required int folderCount,
  List<LaunchableApp> apps = const [],
}) {
  return showModalBottomSheet<CardEditResult>(
    context: context,
    backgroundColor: DeckColors.strip,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _CardEditorSheet(
      card: card,
      position: position,
      folderCount: folderCount,
      apps: apps,
    ),
  );
}

class _CardEditorSheet extends StatefulWidget {
  const _CardEditorSheet({
    required this.card,
    required this.position,
    required this.folderCount,
    required this.apps,
  });

  final DeckCard card;
  final int position;
  final int folderCount;

  /// What is filed on the card, so the preview shows the real thing rather
  /// than an empty one.
  final List<LaunchableApp> apps;

  @override
  State<_CardEditorSheet> createState() => _CardEditorSheetState();
}

class _CardEditorSheetState extends State<_CardEditorSheet> {
  late DeckCard _draft = widget.card;
  final _recents = StyleRecents();
  String? _imagePath;
  bool _pickingImage = false;

  /// Progress text while a widget is being bound, and null otherwise. Doubles as
  /// the guard against a second pick starting while the system's permission
  /// prompt or the widget's own setup screen is still up.
  String? _binding;

  /// The chosen widget's name, for the line under the Change button.
  ///
  /// Only known for a widget picked in this session — a card reopened later has
  /// its id and nothing else, so the label is read back from the host.
  String? _widgetLabel;
  List<String> _recentColors = const [];
  List<String> _recentIcons = const [];
  late final TextEditingController _name = TextEditingController(
    text: widget.card.name,
  );

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _loadImage();
    _loadWidgetLabel();
  }

  /// Names the widget already on the card, and notices when it has gone.
  ///
  /// A card stores a widget id and nothing else, so reopening the editor has no
  /// idea what is on it. The same call answers both questions: a null means the
  /// id no longer resolves — the widget's app was uninstalled, or its data
  /// cleared — which is worth saying plainly, because the card will be drawing a
  /// blank and nothing else would explain why.
  Future<void> _loadWidgetLabel() async {
    if (!_draft.hasWidget) return;
    try {
      final info = await LauncherBridge.instance.widgetInfo(_draft.widgetId!);
      if (!mounted) return;
      setState(() => _widgetLabel = info == null
          ? 'That widget is gone — choose another'
          : info.label);
    } catch (e) {
      // Not worth surfacing: the label is a nicety, and the Change button works
      // without it.
    }
  }

  Future<void> _loadImage() async {
    final images = await LauncherBridge.instance.cardImages();
    if (!mounted) return;
    setState(() => _imagePath = images[widget.card.id]);
  }

  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    try {
      final path = await LauncherBridge.instance.pickCardImage(widget.card.id);
      if (!mounted) return;
      // Null can mean "cancelled" or "this activity was rebuilt while the
      // picker was up", so look on disk rather than trust it.
      if (path != null) {
        setState(() => _imagePath = path);
      } else {
        await _loadImage();
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _removeImage() async {
    await LauncherBridge.instance.removeCardImage(widget.card.id);
    if (mounted) setState(() => _imagePath = null);
  }

  Future<void> _loadRecents() async {
    final results = await Future.wait([_recents.colors(), _recents.icons()]);
    if (!mounted) return;
    setState(() {
      _recentColors = results[0];
      _recentIcons = results[1];
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _preview(),
            const SizedBox(height: 18),
            _label('Name'),
            const SizedBox(height: 6),
            TextField(
              controller: _name,
              style: const TextStyle(color: DeckColors.text, fontSize: 15),
              textCapitalization: TextCapitalization.none,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: DeckColors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(name: value)),
            ),
            const SizedBox(height: 18),
            // The all-apps card is the one card that cannot become a widget: it
            // is the way to reach everything installed, and there is only one of
            // it.
            if (!_draft.isAllApps) ...[
              _label('Holds'),
              const SizedBox(height: 8),
              _kindRow(),
              const SizedBox(height: 14),
            ],
            if (_draft.isWidget) ...[
              _label('Widget'),
              const SizedBox(height: 8),
              _widgetRow(),
              const SizedBox(height: 14),
            ] else ...[
              _label('App titles'),
              const SizedBox(height: 4),
              _labelsRow(),
              const SizedBox(height: 14),
              _label('Rows of icons'),
              const SizedBox(height: 8),
              _rowsRow(),
              const SizedBox(height: 14),
            ],
            _label('Picture'),
            const SizedBox(height: 8),
            _imageRow(),
            const SizedBox(height: 18),
            _label('Colour'),
            const SizedBox(height: 8),
            _swatches(),
            const SizedBox(height: 18),
            _label('Icon'),
            const SizedBox(height: 8),
            _icons(),
            const SizedBox(height: 20),
            Row(
              children: [
                // No delete for the all-apps card: it is the terminal card and
                // the stack, the knob and the folder screen all assume it is
                // there. The deck refuses to remove it anyway — this is so the
                // sheet does not offer a button that would do nothing.
                if (!_draft.isAllApps) ...[
                  _DeleteButton(onTap: _confirmDelete),
                  const SizedBox(width: 10),
                ],
                Expanded(child: _doneButton()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _save,
        style: FilledButton.styleFrom(
          backgroundColor: colorOf(_draft.colorKey),
          foregroundColor: onCardForKey(_draft.colorKey),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text(
          'Done',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DeckColors.strip,
        title: Text(
          'Delete ${widget.card.name}?',
          style: const TextStyle(color: DeckColors.text, fontSize: 17),
        ),
        content: const Text(
          'Its apps are not removed — they stop being filed and show up under '
          'all apps again.',
          style: TextStyle(color: DeckColors.textDim, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Keep',
              style: TextStyle(color: DeckColors.textDim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF6B5A)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(
      context,
      CardEditResult(
        card: widget.card,
        position: widget.position,
        deleted: true,
      ),
    );
  }

  /// The name this card would end up with. An unnamed card is an unreadable
  /// strip, so an emptied field falls back rather than being taken literally.
  String get _effectiveName =>
      _draft.name.trim().isEmpty ? widget.card.name : _draft.name;

  void _save() {
    final trimmed = _name.text.trim();
    // An unnamed card is an unreadable strip, so fall back rather than letting
    // the stack fill with blanks.
    Navigator.pop(
      context,
      CardEditResult(
        card: _draft.copyWith(
          name: trimmed.isEmpty ? widget.card.name : trimmed,
        ),
        position: widget.position,
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      color: DeckColors.textDim,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    ),
  );

  /// The card as it will actually look — the same widget the deck draws, at
  /// the height the deck draws it.
  ///
  /// It used to be a short strip that approximated one, which is the kind of
  /// preview that lies: a picture squashed into a band no card is ever that
  /// shape, so what you chose and what you got were different things.
  Widget _preview() {
    // Grows with the row count, for the reason above: a two-row card previewed
    // at one row's height is the same lie in a different direction — the rows
    // would be squeezed into a card the deck will never draw that short.
    final height = StackStyle.standard.preferredCardHeight +
        (_draft.rows - 1) * StackStyle.standard.rowHeight;
    // The same fallback save applies, so the preview shows what you would get
    // rather than the blank you are momentarily typing.
    final card = DeckCardView(
      card: _draft.copyWith(name: _effectiveName),
      height: height,
      focused: true,
      // A stand-in for the widget, not the widget: the real one is on the deck
      // behind this sheet, and the host would hand its registration to whichever
      // view was built last.
      preview: true,
      apps: widget.apps,
      totalInstalled: widget.apps.length,
      imagePath: _imagePath,
      imageOffset: _draft.imageOffset,
      onTap: () {},
      onAppTap: (_) {},
    );

    if (_imagePath == null) return card;

    return GestureDetector(
      // Vertical only: the card is far wider than it is tall, so a cover crop
      // throws away a photo's height and up-and-down is the whole choice.
      onVerticalDragUpdate: (details) {
        setState(() {
          _draft = _draft.copyWith(
            imageOffset: (_draft.imageOffset - details.delta.dy * 2 / height)
                .clamp(-1.0, 1.0),
          );
        });
      },
      child: Stack(
        children: [
          card,
          Positioned(
            top: 8,
            left: 12,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DeckColors.ground.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.drag_indicator_rounded,
                      size: 13,
                      color: DeckColors.text,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'drag to reposition',
                      style: deckText(size: 10, color: DeckColors.text),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelsRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _draft.showAppLabels
                ? 'Shown under each app'
                : 'Hidden, and the icons take the room',
            style: deckText(size: 11, color: DeckColors.textDim),
          ),
        ),
        Switch(
          value: _draft.showAppLabels,
          activeThumbColor: colorOf(_draft.colorKey),
          onChanged: (value) => setState(
            () => _draft = _draft.copyWith(showAppLabels: value),
          ),
        ),
      ],
    );
  }

  /// How many rows of icons the card shows when it is open.
  ///
  /// Whole numbers, so a segmented control rather than a slider: there are four
  /// of them and each is a different layout, not a value to find by feel.
  Widget _rowsRow() {
    final accent = colorOf(_draft.colorKey);
    return Row(
      children: [
        for (var rows = 1; rows <= maxAppRows; rows++) ...[
          if (rows > 1) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(
                () => _draft = _draft.copyWith(appRows: rows),
              ),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _draft.appRows == rows ? accent : DeckColors.surface,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: _draft.appRows == rows
                        ? accent
                        : DeckColors.surfaceEdge,
                  ),
                ),
                child: Text(
                  '$rows',
                  style: deckText(
                    size: 15,
                    weight: 700,
                    color: _draft.appRows == rows
                        ? onCardFor(accent)
                        : DeckColors.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Apps or a widget.
  ///
  /// Switching to a widget does not throw the card's apps away — they are kept
  /// on the card and come back if it is switched again, because the switch is
  /// easy to make by accident and a card of filed apps is tedious to rebuild.
  Widget _kindRow() {
    final accent = colorOf(_draft.colorKey);
    return Row(
      children: [
        for (final widgetKind in [false, true]) ...[
          if (widgetKind) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(
                () => _draft = _draft.copyWith(isWidget: widgetKind),
              ),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      _draft.isWidget == widgetKind ? accent : DeckColors.surface,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: _draft.isWidget == widgetKind
                        ? accent
                        : DeckColors.surfaceEdge,
                  ),
                ),
                child: Text(
                  widgetKind ? 'A widget' : 'Apps',
                  style: deckText(
                    size: 13,
                    weight: 700,
                    color: _draft.isWidget == widgetKind
                        ? onCardFor(accent)
                        : DeckColors.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Which widget is on the card, and the button to change it.
  Widget _widgetRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _binding ?? (_draft.hasWidget
                ? (_widgetLabel ?? 'A widget is on this card')
                : 'None yet — three rows tall, whichever you pick'),
            style: deckText(size: 11, color: DeckColors.textDim),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _binding == null ? _pickWidget : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: DeckColors.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: DeckColors.surfaceEdge),
            ),
            child: Text(
              _draft.hasWidget ? 'Change' : 'Choose',
              style: deckText(size: 12, weight: 700, color: DeckColors.text),
            ),
          ),
        ),
      ],
    );
  }

  /// Picks a widget, binds it, and puts it on the draft.
  ///
  /// The old widget is released only once the new one is bound. Releasing first
  /// would leave the card with nothing if the user then declined the permission
  /// prompt or backed out of the widget's setup.
  Future<void> _pickWidget() async {
    final provider = await pickWidget(context, _draft);
    if (provider == null || !mounted) return;

    setState(() => _binding = 'Adding ${provider.label}…');
    final binding = await LauncherBridge.instance.bindWidget(provider.provider);
    if (!mounted) return;

    if (!binding.ok || binding.widgetId == null) {
      setState(() => _binding = null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DeckColors.surface,
          content: Text(
            binding.reason ?? 'That widget could not be added',
            style: deckText(size: 12),
          ),
        ),
      );
      return;
    }

    final previous = _draft.widgetId;
    setState(() {
      _binding = null;
      _widgetLabel = provider.label;
      _draft = _draft.copyWith(isWidget: true, widgetId: binding.widgetId);
    });
    if (previous != null && previous != binding.widgetId) {
      await LauncherBridge.instance.releaseWidget(previous);
    }
  }

  Widget _imageRow() {
    return Row(
      children: [
        GestureDetector(
          onTap: _pickingImage ? null : _pickImage,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: DeckColors.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: DeckColors.surfaceEdge),
            ),
            child: _pickingImage
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DeckColors.textDim,
                    ),
                  )
                : const Icon(
                    Icons.image_outlined,
                    size: 20,
                    color: DeckColors.textDim,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _imagePath == null
                ? 'None — the card is its colour alone'
                : 'Drag the card above to reposition it',
            style: deckText(size: 11, color: DeckColors.textDim),
          ),
        ),
        if (_imagePath != null)
          GestureDetector(
            onTap: _removeImage,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.close_rounded,
                size: 18,
                color: DeckColors.textDim,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickColor() async {
    final picked = await showColorPicker(
      context,
      current: _draft.colorKey,
      cardName: _effectiveName,
      iconKey: _draft.iconKey,
    );
    if (picked == null) return;
    setState(() => _draft = _draft.copyWith(colorKey: picked));
    // Only a custom colour is worth keeping: a preset is already on the shelf.
    if (!isCustomColorKey(picked)) return;
    final updated = await _recents.addColor(picked, presets: starterColorKeys);
    if (mounted) setState(() => _recentColors = updated);
  }

  Widget _swatches() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        // Presets for the usual case, the picker for any other colour, and
        // whatever has been picked before so the second use is a tap.
        _PickerTile(
          icon: Icons.colorize_rounded,
          onTap: _pickColor,
          selected: isCustomColorKey(_draft.colorKey),
        ),
        for (final key in _recentColors)
          GestureDetector(
            onTap: () =>
                setState(() => _draft = _draft.copyWith(colorKey: key)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colorOf(key),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _draft.colorKey == key
                      ? DeckColors.text
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: _draft.colorKey == key
                  ? Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: onCardForKey(key),
                    )
                  : null,
            ),
          ),
        for (final color in cardPalette.take(starterColorKeys.length))
          GestureDetector(
            onTap: () =>
                setState(() => _draft = _draft.copyWith(colorKey: color.key)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Color(color.value),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _draft.colorKey == color.key
                      ? DeckColors.text
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: _draft.colorKey == color.key
                  ? Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: onCardFor(Color(color.value)),
                    )
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _pickIcon() async {
    final picked = await showIconPicker(
      context,
      current: _draft.iconKey,
      accent: colorOf(_draft.colorKey),
    );
    if (picked == null) return;
    setState(() => _draft = _draft.copyWith(iconKey: picked));
    final updated = await _recents.addIcon(picked, presets: starterIconKeys);
    if (mounted) setState(() => _recentIcons = updated);
  }

  Widget _icons() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        // The common ones are a tap; everything else is a search away. All
        // 2,200 laid out here would be a wall, not a choice. Same tile as the
        // colour picker's, so the two read as the same kind of door.
        _PickerTile(
          icon: Icons.search_rounded,
          onTap: _pickIcon,
          selected: !starterIconKeys.contains(_draft.iconKey),
        ),
        for (final key in [..._recentIcons, ...starterIconKeys])
          GestureDetector(
            onTap: () => setState(() => _draft = _draft.copyWith(iconKey: key)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _draft.iconKey == key
                    ? colorOf(_draft.colorKey)
                    : DeckColors.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: _draft.iconKey == key
                      ? Colors.transparent
                      : DeckColors.surfaceEdge,
                ),
              ),
              child: Icon(
                iconOf(key),
                size: 20,
                color: _draft.iconKey == key
                    ? onCardForKey(_draft.colorKey)
                    : DeckColors.textDim,
              ),
            ),
          ),
      ],
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: DeckColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: DeckColors.surfaceEdge),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          size: 20,
          color: Color(0xFFFF6B5A),
        ),
      ),
    );
  }
}

/// The tile that opens a full picker, for either colour or icon.
///
/// One widget so the two cannot drift apart: they do the same thing — leave
/// this shelf and go and find something — and the rainbow says so. The icon
/// search used to be a plain grey square, which read as just another choice
/// rather than a door out.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.onTap,
    required this.selected,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// Whether the card is currently wearing something that came from here, so
  /// the shelf still shows what is chosen even when it is not on it.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? DeckColors.text : DeckColors.surfaceEdge,
            width: selected ? 2.5 : 1,
          ),
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF2BB5),
              Color(0xFFFF9A0E),
              Color(0xFF2BE04B),
              Color(0xFF3FE3F0),
              Color(0xFF8E8CF8),
              Color(0xFFFF2BB5),
            ],
          ),
        ),
        child: Icon(icon, size: 18, color: DeckColors.onCard),
      ),
    );
  }
}
