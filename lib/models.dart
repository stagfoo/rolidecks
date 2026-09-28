/// What the launcher knows about one thing it can launch.
library;

/// An entry is either an installed app or a shortcut another app has pinned
/// here — a folder from a file manager, a conversation from a chat app. They
/// sit in the same list so cards, search and filing do not have to know the
/// difference; only launching and drawing an icon do.
enum LaunchKind { app, shortcut }

class LaunchableApp {
  const LaunchableApp({
    required this.packageName,
    required this.activityName,
    required this.label,
    this.isSystem = false,
    this.kind = LaunchKind.app,
    this.shortcutId,
    this.intentUri,
  });

  /// A shortcut pinned by another app, which the system remembers.
  const LaunchableApp.shortcut({
    required this.packageName,
    required String id,
    required this.label,
  })  : shortcutId = id,
        intentUri = null,
        kind = LaunchKind.shortcut,
        activityName = '',
        isSystem = false;

  /// A shortcut built the older way, as a bare intent.
  ///
  /// The system does not remember these — it hands the launcher an intent and a
  /// name and forgets them — so the URI is the whole identity and the launcher
  /// has to store it itself.
  const LaunchableApp.legacyShortcut({
    required String uri,
    required this.label,
    this.packageName = '',
  })  : intentUri = uri,
        shortcutId = null,
        kind = LaunchKind.shortcut,
        activityName = '',
        isSystem = false;

  final String packageName;

  /// The launcher activity behind this entry. A package can expose more than
  /// one, which is why the list is keyed on the pair rather than the package.
  final String activityName;

  final String label;
  final bool isSystem;

  final LaunchKind kind;

  /// Set for a shortcut the system remembers.
  final String? shortcutId;

  /// Set for a shortcut only this launcher remembers.
  final String? intentUri;

  bool get isLegacyShortcut => intentUri != null;

  bool get isShortcut => kind == LaunchKind.shortcut;

  /// Stable identity for ordering and filing.
  ///
  /// Shortcuts are prefixed so they can never collide with an app whose
  /// activity happens to share the name, and so an id read back from an old
  /// deck still says which kind it was.
  String get id {
    if (isLegacyShortcut) return 'legacy:$intentUri';
    if (isShortcut) return 'shortcut:$packageName/$shortcutId';
    return '$packageName/$activityName';
  }

  Map<String, dynamic> toJson() => {
        'packageName': packageName,
        'activityName': activityName,
        'label': label,
        'isSystem': isSystem,
        if (isShortcut) 'kind': 'shortcut',
        if (shortcutId != null) 'shortcutId': shortcutId,
        if (intentUri != null) 'intentUri': intentUri,
      };

  static LaunchableApp fromJson(Map<String, dynamic> json) {
    final shortcutId = json['shortcutId'] as String?;
    final intentUri = json['intentUri'] as String?;
    final isShortcut =
        json['kind'] == 'shortcut' && (shortcutId != null || intentUri != null);
    return LaunchableApp(
      packageName: (json['packageName'] as String?) ?? '',
      activityName: (json['activityName'] as String?) ?? '',
      label: (json['label'] as String?) ??
          (json['packageName'] as String?) ??
          'Shortcut',
      isSystem: json['isSystem'] as bool? ?? false,
      kind: isShortcut ? LaunchKind.shortcut : LaunchKind.app,
      shortcutId: shortcutId,
      intentUri: intentUri,
    );
  }

  static LaunchableApp shortcutFromPlatform(Map<Object?, Object?> map) =>
      LaunchableApp.shortcut(
        packageName: map['packageName'] as String,
        id: map['shortcutId'] as String,
        label: (map['label'] as String?) ?? map['shortcutId'] as String,
      );

  static LaunchableApp fromPlatform(Map<Object?, Object?> map) => LaunchableApp(
        packageName: map['packageName'] as String,
        activityName: (map['activityName'] as String?) ?? '',
        label: (map['label'] as String?) ?? map['packageName'] as String,
        isSystem: map['isSystem'] as bool? ?? false,
      );
}

/// The panel, as measured rather than assumed.
class ScreenMetrics {
  const ScreenMetrics({
    required this.widthPx,
    required this.heightPx,
    required this.density,
    required this.densityDpi,
  });

  final int widthPx;
  final int heightPx;
  final double density;
  final int densityDpi;

  double get widthDp => widthPx / density;

  double get heightDp => heightPx / density;

  /// The Mind One's panel is 1240 × 1080 in landscape — about 1.15:1, far
  /// closer to square than the 16:9 a Switch-style layout normally assumes.
  double get aspectRatio => widthPx / heightPx;

  static ScreenMetrics fromPlatform(Map<Object?, Object?> map) => ScreenMetrics(
        widthPx: (map['widthPx'] as num?)?.toInt() ?? 0,
        heightPx: (map['heightPx'] as num?)?.toInt() ?? 0,
        density: (map['density'] as num?)?.toDouble() ?? 1,
        densityDpi: (map['densityDpi'] as num?)?.toInt() ?? 0,
      );

  @override
  String toString() =>
      '${widthPx}x$heightPx @${density}x (${widthDp.round()}x${heightDp.round()} dp)';
}

/// An app widget the phone has installed, as offered by the picker.
class WidgetProvider {
  const WidgetProvider({
    required this.provider,
    required this.packageName,
    required this.label,
    this.minWidth = 0,
    this.minHeight = 0,
    this.resizable = true,
    this.needsConfigure = false,
  });

  /// The flattened ComponentName. This is the widget's identity to the system
  /// and the only thing [LauncherBridge.bindWidget] needs.
  final String provider;

  final String packageName;
  final String label;

  /// The size the widget asks for, in dp. Advisory: a resizable widget will lay
  /// itself out smaller, and the picker uses these only to say when a widget is
  /// being put somewhere it will be cramped.
  final int minWidth;
  final int minHeight;

  final bool resizable;

  /// Whether the widget runs its own setup screen before it can draw anything.
  final bool needsConfigure;

  static WidgetProvider fromPlatform(Map<Object?, Object?> map) => WidgetProvider(
        provider: (map['provider'] as String?) ?? '',
        packageName: (map['packageName'] as String?) ?? '',
        label: (map['label'] as String?) ?? 'Widget',
        minWidth: (map['minWidth'] as num?)?.toInt() ?? 0,
        minHeight: (map['minHeight'] as num?)?.toInt() ?? 0,
        resizable: map['resizable'] as bool? ?? true,
        needsConfigure: map['needsConfigure'] as bool? ?? false,
      );
}

/// The outcome of trying to put a widget on a card.
///
/// A failure here is nearly always the user declining something rather than
/// anything being broken — permission to add widgets, or the widget's own setup
/// screen — so it carries a reason worth showing rather than just a false.
class WidgetBinding {
  const WidgetBinding({required this.ok, this.widgetId, this.reason});

  final bool ok;
  final int? widgetId;
  final String? reason;

  static WidgetBinding fromPlatform(Map<Object?, Object?> map) => WidgetBinding(
        ok: map['ok'] as bool? ?? false,
        widgetId: (map['widgetId'] as num?)?.toInt(),
        reason: map['reason'] as String?,
      );
}
