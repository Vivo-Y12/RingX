/// RingX — keyboard + phone to virtual racing controller (vJoy feeder).
///
/// One codebase, two faces: on Windows this boots the receiver (engine +
/// mapping UI + phone link); on Android it boots the touch controller that
/// pairs with the receiver over WiFi.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'app.dart';
import 'core/engine.dart';
import 'core/profile.dart';
import 'phone/phone_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The Android build is the phone controller, not the receiver.
  if (Platform.isAndroid) {
    runPhoneApp();
    return;
  }

  final store = ProfileStore();
  final (profile, loadError) = store.load();

  final engine = MapperEngine(store: store, phonePageLoader: () async {
    try {
      final data = await rootBundle.load('assets/phone.html');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on Exception catch (_) {
      return null; // fall back to the plain-text notice
    }
  });
  // One-time init: swap in the loaded profile before devices are acquired.
  engine.profile = loadError == null ? profile : Profile.defaults();
  engine.start();

  runApp(RingxApp(engine: engine, profileLoadError: loadError));
}
