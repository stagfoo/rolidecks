import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:ui';

import 'home_screen.dart';
import 'launcher_bridge.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // A build error in the deck would otherwise be a red screen on the home app,
  // relaunched into the same error. Reported and then passed on: the Android
  // side records it and the next launch comes up without widgets, which is the
  // part most likely to have thrown.
  final framework = FlutterError.onError;
  FlutterError.onError = (details) {
    LauncherBridge.instance.noteDartError('${details.exception}');
    framework?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    LauncherBridge.instance.noteDartError('$error');
    return false;
  };

  // A home app draws the whole panel; letting the system letterbox it around
  // the status and gesture bars wastes height this screen does not have.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const RolidecksApp());
}

class RolidecksApp extends StatelessWidget {
  const RolidecksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rolidecks',
      debugShowCheckedModeBanner: false,
      theme: buildDeckTheme(),
      home: const HomeScreen(),
    );
  }
}
