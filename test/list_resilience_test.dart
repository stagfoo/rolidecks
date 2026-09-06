import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolidecks/launcher_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('rolidecks/launcher');

  void answer({required bool shortcutsFail}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'listApps':
          return [
            {
              'packageName': 'com.a',
              'activityName': 'com.a.Main',
              'label': 'Alpha',
              'isSystem': false,
            },
          ];
        case 'listShortcuts':
          if (shortcutsFail) {
            // What a locked work or clone profile actually produces.
            throw PlatformException(
              code: 'failed',
              message: 'User 10 is locked or not running',
            );
          }
          return [
            {
              'packageName': 'com.b',
              'shortcutId': 'one',
              'label': 'Shortcut',
            },
          ];
        default:
          return null;
      }
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a shortcut failure does not take the app list with it', () async {
    // This is what a locked profile did: listShortcuts threw, both futures
    // were awaited together, and the launcher was left running on its cache
    // with no new app ever appearing.
    answer(shortcutsFail: true);
    final everything = await LauncherBridge.instance.listEverything();
    expect(everything.map((a) => a.label), ['Alpha']);
  });

  test('listShortcuts reports empty rather than throwing', () async {
    answer(shortcutsFail: true);
    expect(await LauncherBridge.instance.listShortcuts(), isEmpty);
  });

  test('both are returned when the platform is healthy', () async {
    answer(shortcutsFail: false);
    final everything = await LauncherBridge.instance.listEverything();
    expect(everything.map((a) => a.label), ['Alpha', 'Shortcut']);
    expect(everything.last.isShortcut, isTrue);
  });
}
