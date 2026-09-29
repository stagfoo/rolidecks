import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'launcher_bridge.dart';
import 'models.dart';
import 'theme.dart';

/// What the launcher can and cannot see.
///
/// A screen rather than a snackbar. Every shortcut API is gated on holding the
/// home role, and the answer to "why did nothing happen" is one of a handful of
/// flags — which is no use flashing past for six seconds at the bottom of the
/// screen, and was no use at all when the long-press quietly did nothing.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  Map<String, Object?>? _shortcuts;
  Map<String, Object?>? _widgets;
  ScreenMetrics? _metrics;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Read fresh rather than handed in: the panel changes shape when the
      // phone is rotated, and a figure captured at startup would be wrong.
      final results = await Future.wait([
        LauncherBridge.instance.shortcutDiagnostics(),
        LauncherBridge.instance.screenMetrics(),
        LauncherBridge.instance.widgetDiagnostics(),
      ]);
      if (!mounted) return;
      setState(() {
        _shortcuts = results[0] as Map<String, Object?>;
        _metrics = results[1] as ScreenMetrics;
        _widgets = results[2] as Map<String, Object?>;
        _error = null;
      });
    } catch (e) {
      // Reported rather than swallowed: a diagnostics screen that fails
      // silently is the exact problem it exists to solve.
      if (mounted) setState(() => _error = e);
    }
  }

  String get _report {
    final buffer = StringBuffer()..writeln('Rolidecks diagnostics');
    if (_metrics != null) buffer.writeln('screen: $_metrics');
    if (_error != null) buffer.writeln('error: $_error');
    for (final entry in (_shortcuts ?? const {}).entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    // Lists one per line rather than as a Dart list literal: the widget log is
    // the part most likely to be pasted back to someone, and a single 400-column
    // line of it is unreadable.
    for (final entry in (_widgets ?? const {}).entries) {
      final value = entry.value;
      if (value is List) {
        buffer.writeln('${entry.key}:');
        for (final line in value) {
          buffer.writeln('  $line');
        }
      } else {
        buffer.writeln('${entry.key}: $value');
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = _shortcuts;
    final isHome = shortcuts?['isDefaultLauncher'] == true;
    final pinSupported = shortcuts?['isRequestPinShortcutSupported'] == true;

    return Scaffold(
      backgroundColor: DeckColors.ground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.arrow_back_rounded,
                        size: 22, color: DeckColors.text),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child:
                      Text('Diagnostics', style: deckText(size: 16, weight: 600)),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _report));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: DeckColors.surface,
                          content:
                              Text('Copied', style: deckText(size: 12)),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_rounded,
                      size: 18, color: DeckColors.textDim),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded,
                      size: 18, color: DeckColors.textDim),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_error != null)
              _Line(name: 'error', value: '$_error', bad: true)
            else if (shortcuts == null)
              Text('Reading…', style: deckText(size: 13, color: DeckColors.textDim))
            else ...[
              // The two that decide everything else, first and in plain words.
              _Line(
                name: 'Rolidecks is the home app',
                value: isHome ? 'yes' : 'no',
                bad: !isHome,
                note: isHome
                    ? null
                    : 'Android sends shortcuts only to the home app. Nothing '
                        'below can work until this is yes.',
              ),
              _Line(
                name: 'Android offers apps "add to home screen"',
                value: pinSupported ? 'yes' : 'no',
                bad: !pinSupported,
                note: pinSupported
                    ? null
                    : 'Apps check this before offering the option. When it is '
                        'no, Chrome and DuckDuckGo quietly do something else '
                        'instead of asking this launcher.',
              ),
              const Divider(height: 24, color: DeckColors.surfaceEdge),
              for (final entry in shortcuts.entries)
                if (entry.key != 'isDefaultLauncher' &&
                    entry.key != 'isRequestPinShortcutSupported')
                  _Line(name: entry.key, value: '${entry.value}'),
              if (_metrics != null)
                _Line(name: 'screen', value: '$_metrics'),
              ..._widgetSection(),
            ],
            const SizedBox(height: 16),
            if (shortcuts != null && !isHome)
              FilledButton(
                onPressed: LauncherBridge.instance.openHomeSettings,
                child: const Text('Set Rolidecks as the home app'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Everything about widget cards, or nothing at all when there are none.
///
/// Its own section rather than more lines in the shortcut list, because the
/// order matters here: whether the host is listening and whether an id is bound
/// decide what the log below them means, and reading the log first only invites
/// chasing a line that was never the cause.
extension on _DiagnosticsScreenState {
  List<Widget> _widgetSection() {
    final widgets = _widgets;
    if (widgets == null) return const [];

    final held = (widgets['heldWidgetIds'] as num?)?.toInt() ?? 0;
    final listening = widgets['hostListening'] == true;
    final providers = (widgets['installedWidgetProviders'] as num?)?.toInt() ?? 0;
    final bound = (widgets['boundWidgets'] as List?) ?? const [];
    final log = (widgets['widgetLog'] as List?) ?? const [];

    return [
      const Divider(height: 24, color: DeckColors.surfaceEdge),
      Text('Widgets', style: deckText(size: 14, weight: 700)),
      const SizedBox(height: 4),
      _Line(
        name: 'widgets installed on this phone',
        value: '$providers',
        bad: providers <= 0,
        note: providers <= 0
            ? 'Nothing to put on a widget card until an app that provides one '
                'is installed.'
            : null,
      ),
      _Line(
        name: 'the host is listening',
        value: listening ? 'yes' : 'no',
        bad: !listening,
        note: listening
            ? null
            : 'A host that is not listening receives no updates, so a widget '
                'stays blank however well it is bound.',
      ),
      _Line(
        name: 'widget ids this launcher holds',
        value: '$held',
        bad: held == 0,
        note: held == 0
            ? 'No widget is bound. A widget card with nothing bound draws '
                'nothing — choose a widget on the card.'
            : null,
      ),
      for (final entry in bound) _Line(name: 'bound', value: '$entry'),
      if (log.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          'What happened, oldest first',
          style: deckText(size: 12, weight: 600, color: DeckColors.textDim),
        ),
        const SizedBox(height: 4),
        for (final line in log)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '$line',
              style: deckText(size: 11, color: DeckColors.textDim, height: 1.3),
            ),
          ),
      ],
    ];
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.name,
    required this.value,
    this.bad = false,
    this.note,
  });

  final String name;
  final String value;
  final bool bad;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(name,
                    style: deckText(size: 13, color: DeckColors.textDim)),
              ),
              const SizedBox(width: 10),
              Text(
                value,
                style: deckText(
                  size: 13,
                  weight: 600,
                  color: bad ? const Color(0xFFFF6B5A) : DeckColors.text,
                ),
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(note!,
                  style: deckText(size: 11, color: DeckColors.textDim)),
            ),
        ],
      ),
    );
  }
}
