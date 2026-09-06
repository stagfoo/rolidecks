import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolidecks/card_deck.dart';
import 'package:rolidecks/saved_shortcuts.dart';
import 'package:rolidecks/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

final downloads = LaunchableApp.legacyShortcut(
  uri: 'intent:#Intent;action=android.intent.action.VIEW;'
      'S.path=/storage/Downloads;end',
  label: 'Downloads',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('identity', () {
    test('a legacy shortcut is identified by its intent', () {
      // The system remembers nothing about these, so the intent is all there
      // is to tell one from another.
      expect(downloads.id, startsWith('legacy:intent:'));
      expect(downloads.isShortcut, isTrue);
      expect(downloads.isLegacyShortcut, isTrue);
      expect(downloads.shortcutId, isNull);
    });

    test('it does not collide with a pinned shortcut', () {
      final pinned = LaunchableApp.shortcut(
        packageName: 'files.fileexplorer.filemanager',
        id: 'downloads',
        label: 'Downloads',
      );
      expect(pinned.id, isNot(downloads.id));
      expect(pinned.isLegacyShortcut, isFalse);
    });
  });

  group('storage', () {
    test('survives a save and load, icon and all', () async {
      final store = SavedShortcutStore();
      await store.add(StoredShortcut(
        app: downloads,
        icon: Uint8List.fromList([1, 2, 3]),
      ));

      final restored = (await SavedShortcutStore().load()).single;
      expect(restored.app.label, 'Downloads');
      expect(restored.app.intentUri, downloads.intentUri);
      expect(restored.icon, [1, 2, 3]);
    });

    test('one without an icon is still stored', () async {
      final store = SavedShortcutStore();
      await store.add(StoredShortcut(app: downloads));
      expect((await store.load()).single.icon, isNull);
    });

    test('adding the same shortcut twice replaces rather than duplicates',
        () async {
      final store = SavedShortcutStore();
      await store.add(StoredShortcut(app: downloads));
      await store.add(StoredShortcut(
        app: LaunchableApp.legacyShortcut(
          uri: downloads.intentUri!,
          label: 'Downloads (renamed)',
        ),
      ));
      final all = await store.load();
      expect(all, hasLength(1));
      expect(all.single.app.label, 'Downloads (renamed)');
    });

    test('two different intents are kept apart', () async {
      final store = SavedShortcutStore();
      await store.add(StoredShortcut(app: downloads));
      await store.add(StoredShortcut(
        app: LaunchableApp.legacyShortcut(uri: 'intent:#Intent;S.p=/b;end', label: 'B'),
      ));
      expect(await store.load(), hasLength(2));
    });

    test('remove takes one out and hands it back', () async {
      // Handed back so a delete can be undone: a shortcut built in another app
      // is not always easy to make again.
      final store = SavedShortcutStore();
      await store.add(StoredShortcut(
        app: downloads,
        icon: Uint8List.fromList([5]),
      ));

      final removed = await store.remove(downloads.id);
      expect(await store.load(), isEmpty);
      expect(removed, isNotNull);
      expect(removed!.app.id, downloads.id);
      expect(removed.icon, [5], reason: 'the icon must come back too');
    });

    test('putting a removed one back restores it whole', () async {
      final store = SavedShortcutStore();
      await store.add(StoredShortcut(
        app: downloads,
        icon: Uint8List.fromList([5]),
      ));
      final removed = await store.remove(downloads.id);
      await store.add(removed!);

      final restored = (await store.load()).single;
      expect(restored.app.id, downloads.id);
      expect(restored.icon, [5]);
    });

    test('removing something absent reports nothing removed', () async {
      final store = SavedShortcutStore();
      await store.add(StoredShortcut(app: downloads));
      expect(await store.remove('legacy:nothing'), isNull);
      expect(await store.load(), hasLength(1));
    });

    test('unreadable storage is a miss, not a crash', () async {
      SharedPreferences.setMockInitialValues({
        'rolidecks.savedShortcuts.v2': 'not json',
      });
      expect(await SavedShortcutStore().load(), isEmpty);
    });

    test('an entry with no intent is dropped rather than half-loaded', () async {
      SharedPreferences.setMockInitialValues({
        'rolidecks.savedShortcuts.v2':
            '[{"label":"Broken","kind":"shortcut"}]',
      });
      expect(await SavedShortcutStore().load(), isEmpty);
    });

    test('a corrupt icon does not take the shortcut down with it', () async {
      SharedPreferences.setMockInitialValues({
        'rolidecks.savedShortcuts.v2':
            '[{"label":"X","kind":"shortcut","intentUri":"intent:#Intent;end",'
            '"icon":"!!not base64!!"}]',
      });
      final restored = await SavedShortcutStore().load();
      expect(restored, hasLength(1));
      expect(restored.single.icon, isNull);
    });
  });

  group('a pinned shortcut is kept too', () {
    final pinned = LaunchableApp.shortcut(
      packageName: 'com.poweramp.player',
      id: 'playlist-42',
      label: 'Late nights',
    );

    test('stored and read back by its own identity', () async {
      // Kept at accept time rather than looked up afterwards, so it shows
      // because it was added rather than because a later query returned it.
      final store = SavedShortcutStore();
      await store.add(StoredShortcut(
        app: pinned,
        icon: Uint8List.fromList([9]),
      ));
      final restored = (await SavedShortcutStore().load()).single;
      expect(restored.app.id, pinned.id);
      expect(restored.app.shortcutId, 'playlist-42');
      expect(restored.app.isLegacyShortcut, isFalse);
      expect(restored.icon, [9]);
    });

    test('sits alongside a legacy one without colliding', () async {
      final store = SavedShortcutStore();
      await store.add(StoredShortcut(app: pinned));
      await store.add(StoredShortcut(app: downloads));
      expect(await store.load(), hasLength(2));
    });

    test('an entry with neither an intent nor an id is dropped', () async {
      SharedPreferences.setMockInitialValues({
        'rolidecks.savedShortcuts.v2': '[{"label":"Broken","kind":"shortcut"}]',
      });
      expect(await SavedShortcutStore().load(), isEmpty);
    });
  });

  group('cards treat it like anything else', () {
    test('it can be filed and resolved', () {
      var deck = CardDeck.seed();
      final id = deck.folders.first.id;
      deck = deck.assign(downloads.id, id);
      expect(
        deck.cards[deck.indexOfId(id)].resolve([downloads]).single.label,
        'Downloads',
      );
    });
  });
}
