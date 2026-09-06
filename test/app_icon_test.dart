
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolidecks/app_icon.dart';
import 'package:rolidecks/launcher_bridge.dart';
import 'package:rolidecks/models.dart';

const app = LaunchableApp(
  packageName: 'com.a',
  activityName: 'com.a.Main',
  label: 'Alpha',
);

/// A one-pixel PNG: what is under test is the shape it is drawn in, not the
/// decoding.
final onePixelPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rolidecks/launcher');

  setUp(() {
    LauncherBridge.instance.forgetIcon('com.a');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'appIcon') return onePixelPng;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    LauncherBridge.instance.forgetIcon('com.a');
  });

  Future<void> pump(WidgetTester tester, double size) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: AppIconImage(app: app, size: size))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the icon is a rounded square, not a circle or a bare bitmap',
      (tester) async {
    await pump(tester, 48);
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(48 * 0.24));
  });

  testWidgets('the rounding scales with the icon', (tester) async {
    await pump(tester, 24);
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(24 * 0.24));
  });

  testWidgets('the icon fills its square rather than sitting inside one',
      (tester) async {
    // It used to be inset inside a faded tile, which is what a flat-drawn
    // adaptive icon needs to look deliberate; cropped properly it can fill.
    await pump(tester, 48);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    expect(tester.getSize(find.byType(ClipRRect)), const Size(48, 48));
  });

  testWidgets('a missing icon falls back without a clip', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    await pump(tester, 48);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.android), findsOneWidget);
  });
}
