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
      ]);
      if (!mounted) return;
      setState(() {
        _shortcuts = results[0] as Map<String, Object?>;
        _metrics = results[1] as ScreenMetrics;
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
