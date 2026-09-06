/// Thin wrapper over the `rolidecks/launcher` channel. Marshalling only —
/// every decision about what to show lives in the pure modules beside it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// One shortcut the Android side recorded, before it becomes a [LaunchableApp].
class StoredShortcutRecord {
  const StoredShortcutRecord({
    required this.label,
    required this.packageName,
    this.shortcutId,
    this.intentUri,
    this.icon,
  });

  final String label;
  final String packageName;
  final String? shortcutId;
  final String? intentUri;
  final Uint8List? icon;

  /// Null when the record carries nothing launchable.
  LaunchableApp? toApp() {
    if (intentUri != null && intentUri!.isNotEmpty) {
      return LaunchableApp.legacyShortcut(uri: intentUri!, label: label);
    }
    if (shortcutId != null && shortcutId!.isNotEmpty) {
      return LaunchableApp.shortcut(
        packageName: packageName,
        id: shortcutId!,
        label: label,
      );
    }
    return null;
  }
}

class LauncherBridge {
  LauncherBridge._();

  static final LauncherBridge instance = LauncherBridge._();

  static const MethodChannel _channel = MethodChannel('rolidecks/launcher');
  static const EventChannel _packageEvents = EventChannel('rolidecks/packages');

  /// Completed icons, for a synchronous hit that paints in the same frame.
  final Map<String, Uint8List?> _iconCache = {};

  /// Icons still in flight, keyed by package.
  ///
  /// Without this the cache only holds *finished* work, so every rebuild while
  /// an icon is loading starts another platform call for the same package —
  /// and the icon widgets ask for their icon from build(). Scrolling all apps
  /// turned that into a flood of duplicate round-trips across a single-threaded
  /// worker, which is what made the page crawl.
  final Map<String, Future<Uint8List?>> _iconRequests = {};

  /// Fires whenever a package is installed, removed, replaced or changed, so
  /// the deck can redraw. A home screen still showing a tile for an app that
  /// no longer exists is the most obvious way for a launcher to feel broken.
  Stream<String> get packageChanges =>
      _packageEvents.receiveBroadcastStream().map((event) => '$event');

  Future<List<LaunchableApp>> listApps() async {
    final raw = await _channel.invokeListMethod<Object?>('listApps') ?? const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(LaunchableApp.fromPlatform)
        .toList();
  }

  /// Shortcuts other apps have pinned here. Empty until Rolidecks is the
  /// default launcher — only the host launcher may read them, which is a
  /// legitimate state rather than a failure.
  ///
  /// Empty rather than throwing when the platform cannot answer either. A
  /// phone can carry a locked work or clone profile that makes this fail
  /// outright, and no shortcut is worth losing the app list over.
  Future<List<LaunchableApp>> listShortcuts() async {
    try {
      final raw =
          await _channel.invokeListMethod<Object?>('listShortcuts') ?? const [];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map(LaunchableApp.shortcutFromPlatform)
          .toList();
    } catch (e) {
      return const [];
    }
  }

  /// Everything launchable, apps and pinned shortcuts together, so cards and
  /// search never have to ask which is which.
  ///
  /// The apps are fetched first and on their own. Waiting on both together
  /// meant a shortcut failure discarded the app list as well, so the launcher
  /// quietly ran on nothing but its cache — a new app would never appear, and
  /// the cause was three method calls away from the symptom.
  Future<List<LaunchableApp>> listEverything() async {
    final apps = await listApps();
    return [...apps, ...await listShortcuts()];
  }

  /// The icon if it has already been fetched, without touching the channel.
  ///
  /// Lets a widget paint a known icon in the frame it builds, instead of
  /// showing a placeholder for one frame while a Future that is already
  /// complete gets resolved.
  Uint8List? cachedIcon(String key) => _iconCache[key];

  bool hasIcon(String key) => _iconCache.containsKey(key);

  /// The one cache key for [app].
  ///
  /// An app is keyed by package — every launcher entry of a package shares its
  /// icon — and a shortcut by its full id, since it has its own. There is
  /// exactly one key per item on purpose: writing the icon under one key and
  /// reading it under another cached a null against the read key and every app
  /// icon fell back to the placeholder for good.
  static String iconKeyFor(LaunchableApp app) =>
      app.isShortcut ? app.id : app.packageName;

  Uint8List? cachedIconFor(LaunchableApp app) => _iconCache[iconKeyFor(app)];

  bool hasIconFor(LaunchableApp app) =>
      _iconCache.containsKey(iconKeyFor(app));

  /// The icon for [app], whichever kind it is.
  Future<Uint8List?> iconFor(LaunchableApp app, {int size = 144}) {
    if (!app.isShortcut) return appIcon(app.packageName, size: size);

    final key = app.id;
    if (_iconCache.containsKey(key)) {
      return SynchronousFuture(_iconCache[key]);
    }
    final inFlight = _iconRequests[key];
    if (inFlight != null) return inFlight;

    final request = _channel.invokeMethod<Uint8List>(
      'shortcutIcon',
      {'packageName': app.packageName, 'shortcutId': app.shortcutId},
    ).then((bytes) {
      _iconCache[key] = bytes;
      _iconRequests.remove(key);
      return bytes;
    }, onError: (Object error) {
      _iconRequests.remove(key);
      return null;
    });

    _iconRequests[key] = request;
    return request;
  }

  Future<Uint8List?> appIcon(String packageName, {int size = 144}) {
    if (_iconCache.containsKey(packageName)) {
      return SynchronousFuture(_iconCache[packageName]);
    }
    final inFlight = _iconRequests[packageName];
    if (inFlight != null) return inFlight;

    final request = _channel.invokeMethod<Uint8List>(
      'appIcon',
      {'packageName': packageName, 'size': size},
    ).then((bytes) {
      _iconCache[packageName] = bytes;
      _iconRequests.remove(packageName);
      return bytes;
    }, onError: (Object error) {
      _iconRequests.remove(packageName);
      return null;
    });

    _iconRequests[packageName] = request;
    return request;
  }

  void forgetIcon(String packageName) {
    _iconCache.remove(packageName);
    _iconRequests.remove(packageName);
  }

  Future<bool> launch(String packageName) async =>
      await _channel.invokeMethod<bool>('launch', {'packageName': packageName}) ??
      false;

  /// Launches [app], dispatching on its kind: an app by launch intent, a
  /// pinned shortcut through LauncherApps, and a legacy one by replaying the
  /// intent it was created from.
  Future<bool> open(LaunchableApp app) async {
    if (app.isLegacyShortcut) {
      return await _channel.invokeMethod<bool>(
            'launchIntentUri',
            {'uri': app.intentUri},
          ) ??
          false;
    }
    if (!app.isShortcut) return launch(app.packageName);
    return await _channel.invokeMethod<bool>('launchShortcut', {
          'packageName': app.packageName,
          'shortcutId': app.shortcutId,
        }) ??
        false;
  }

  /// Collects shortcuts recorded since the last ask, and clears them.
  ///
  /// The launcher can be destroyed while another app's shortcut picker is on
  /// screen, so a result announced down the channel can arrive with nobody
  /// listening. The Android side writes each one down; this is how they are
  /// collected however long that took.
  Future<List<StoredShortcutRecord>> takePendingShortcuts() async {
    final raw =
        await _channel.invokeListMethod<Object?>('takePendingShortcuts') ??
            const [];
    return [
      for (final entry in raw.whereType<Map<Object?, Object?>>())
        StoredShortcutRecord(
          label: (entry['label'] as String?) ?? 'Shortcut',
          packageName: (entry['packageName'] as String?) ?? '',
          shortcutId: entry['shortcutId'] as String?,
          intentUri: entry['intentUri'] as String?,
          icon: entry['icon'] as Uint8List?,
        ),
    ];
  }

  /// Opens the system picker so a card can be given a picture. Null when the
  /// user backed out — or when this activity was rebuilt while the picker was
  /// up, in which case [cardImages] still finds the file.
  Future<String?> pickCardImage(String cardId) =>
      _channel.invokeMethod<String>('pickCardImage', {'cardId': cardId});

  /// The picture each card is wearing, by card id, read off disk.
  Future<Map<String, String>> cardImages() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('cardImages');
    return {
      for (final entry in (map ?? const {}).entries)
        '${entry.key}': '${entry.value}',
    };
  }

  Future<void> removeCardImage(String cardId) =>
      _channel.invokeMethod<void>('removeCardImage', {'cardId': cardId});

  /// Seeds the icon cache for a shortcut whose icon came with it rather than
  /// from the platform.
  void primeIcon(String key, Uint8List? bytes) => _iconCache[key] = bytes;

  Future<void> openAppInfo(String packageName) =>
      _channel.invokeMethod<void>('openAppInfo', {'packageName': packageName});

  Future<void> requestUninstall(String packageName) => _channel
      .invokeMethod<void>('requestUninstall', {'packageName': packageName});

  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  /// Opens the system picker for the default home app. There is no API to set
  /// it directly, by design — this is the whole of "make me the launcher".
  Future<void> openHomeSettings() =>
      _channel.invokeMethod<void>('openHomeSettings');

  Future<bool> isDefaultLauncher() async =>
      await _channel.invokeMethod<bool>('isDefaultLauncher') ?? false;

  /// Whether shortcuts can be read at all, and how many are pinned. Pinning
  /// happens in another app, so when nothing appears this is the only way to
  /// tell a request that never arrived from one that was never read.
  Future<Map<String, Object?>> shortcutDiagnostics() async {
    final map =
        await _channel.invokeMapMethod<Object?, Object?>('shortcutDiagnostics');
    return {
      for (final entry in (map ?? const {}).entries)
        '${entry.key}': entry.value,
    };
  }

  Future<ScreenMetrics> screenMetrics() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('screenMetrics');
    return ScreenMetrics.fromPlatform(map ?? const {});
  }

  /// Wires up the calls Kotlin makes on its own.
  ///
  /// Shortcut results are not among them: those are written down on the Android
  /// side and collected with [takePendingShortcuts], because the launcher can
  /// be destroyed while another app builds one. `shortcutsChanged` is only a
  /// nudge to go and look.
  void onPlatformCalls({
    required void Function() onHomePressed,
    required void Function() onShortcutsChanged,
    required void Function() onShortcutFailed,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'homePressed':
          onHomePressed();
        case 'shortcutsChanged':
          onShortcutsChanged();
        case 'shortcutFailed':
          onShortcutFailed();
      }
      return null;
    });
  }
}
