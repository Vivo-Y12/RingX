/// Ringx — keyboard to virtual racing controller (vJoy feeder).
///
/// Boots the profile store + mapping engine and runs the app. The keyboard
/// hook and vJoy device are both optional at runtime; the dashboard shows
/// whatever is missing.
library;

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/engine.dart';
import 'core/profile.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final store = ProfileStore();
  final (profile, loadError) = store.load();

  final engine = MapperEngine(store: store);
  // One-time init: swap in the loaded profile before devices are acquired.
  engine.profile = loadError == null ? profile : Profile.defaults();
  engine.start();

  runApp(RingxApp(engine: engine));
}
