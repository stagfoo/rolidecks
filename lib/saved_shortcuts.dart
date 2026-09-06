/// Every shortcut this launcher has accepted, kept by the launcher itself.
///
/// Both kinds are stored, for different reasons. The older "add to home screen"
/// hands over an intent, a name and a bitmap and then forgets — nothing in
/// Android knows it exists. A pinned shortcut *is* known to the system, but
/// asking for it back means being the shortcut host at the moment of asking and
/// trusting a query to return what was pinned; keeping what was accepted
/// instead means a shortcut appears because it was added, which is one fewer
/// thing that has to be true.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// One stored shortcut and the icon that came with it.
class StoredShortcut {
  const StoredShortcut({required this.app, this.icon});

  final LaunchableApp app;
  final Uint8List? icon;

  Map<String, dynamic> toJson() => {
        ...app.toJson(),
        if (icon != null) 'icon': base64Encode(icon!),
      };

  static StoredShortcut? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, dynamic>();
    // Either kind: an intent to replay, or a shortcut the system knows by id.
    final hasIntent = map['intentUri'] is String;
    final hasShortcutId = map['shortcutId'] is String;
    if (!hasIntent && !hasShortcutId) return null;
    final raw = map['icon'];
    Uint8List? icon;
    if (raw is String) {
      try {
        icon = base64Decode(raw);
      } on FormatException {
        icon = null;
      }
    }
    return StoredShortcut(app: LaunchableApp.fromJson(map), icon: icon);
  }
}

class SavedShortcutStore {
  static const _key = 'rolidecks.savedShortcuts.v2';

  Future<List<StoredShortcut>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded)
          if (StoredShortcut.fromJson(entry) case final shortcut?) shortcut,
      ];
    } on FormatException {
      // Unreadable is a miss, not a failure: better to lose the shortcuts than
      // to refuse to draw the launcher.
      return const [];
    }
  }

  Future<List<StoredShortcut>> add(StoredShortcut shortcut) async {
    final existing = await load();
    // Adding the same shortcut twice replaces it rather than duplicating —
    // the intent is the identity, so a second one is the same door.
    final updated = [
      ...existing.where((entry) => entry.app.id != shortcut.app.id),
      shortcut,
    ];
    await _save(updated);
    return updated;
  }

  /// Removes [id] and hands back what was removed, so the caller can offer to
  /// put it back — a shortcut built in another app is not always easy to make
  /// again, and a delete with no way back is a harsh thing to hang off a
  /// long-press.
  Future<StoredShortcut?> remove(String id) async {
    final existing = await load();
    StoredShortcut? removed;
    final kept = <StoredShortcut>[];
    for (final entry in existing) {
      if (entry.app.id == id && removed == null) {
        removed = entry;
      } else {
        kept.add(entry);
      }
    }
    if (removed != null) await _save(kept);
    return removed;
  }

  Future<void> _save(List<StoredShortcut> shortcuts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final entry in shortcuts) entry.toJson()]),
    );
  }
}
