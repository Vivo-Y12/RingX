/// RingX phone app (Android): the touch controller that pairs with the
/// Windows receiver over WiFi. Owns the WebSocket session, template
/// preferences and the app shell.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/phone_proto.dart';
import '../core/qr_payload.dart';
import '../core/templates.dart';
import 'connect_screen.dart';

/// One live connection per app run; screens share this.
final PhoneSession phoneSession = PhoneSession();

/// The phone's saved templates + active layout.
final TemplatePrefs templatePrefs = TemplatePrefs();

Future<void> runPhoneApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  await templatePrefs.load();
  runApp(const RingXPhoneApp());
}

class RingXPhoneApp extends StatelessWidget {
  const RingXPhoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFF5A524),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'RingX Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0E1116),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF12151B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const ConnectScreen(),
    );
  }
}

/// The controller's live link to the PC.
class PhoneSession extends ChangeNotifier {
  WebSocket? _ws;
  bool connecting = false;
  String? pcUrl;
  String? error;
  bool mappingEnabled = false;
  StreamSubscription? _sub;
  String phoneName = 'Android phone';

  bool get connected => _ws != null;

  /// Connects to a `ws://host:port` URL (validated first; the controller
  /// endpoint path is appended). Returns (ok, error).
  Future<(bool, String?)> connect(String rawUrl) async {
    final parsed = QrPayload.tryParse(rawUrl);
    if (parsed == null) {
      return (false, 'That code is not a RingX receiver URL.');
    }
    final hp = QrPayload.hostPort(parsed);
    final url = 'ws://${hp!.$1}:${hp.$2}/ws';
    if (connected && url == pcUrl) return (true, null);
    if (connected) disconnect();
    connecting = true;
    error = null;
    notifyListeners();
    try {
      final ws = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 6));
      _ws = ws;
      pcUrl = url;
      connecting = false;
      _sub = ws.listen(
        (data) {
          if (data is! String) return;
          final msg = PhoneMsg.tryDecode(data);
          if (msg == null) return;
          switch (msg) {
            case StatMsg(:final enabled):
              mappingEnabled = enabled;
              notifyListeners();
            case TemplateMsg(:final template):
              final t = Template.tryParse(template);
              if (t != null) templatePrefs.addFromPc(t);
            case HelloMsg():
              break; // receiver-bound
            case PhoneStateMsg():
              break; // receiver-bound
            case ToggleMsg():
              break; // receiver-bound
          }
        },
        onDone: _closed,
        onError: (Object e) => _closed(),
        cancelOnError: true,
      );
      send(HelloMsg(name: phoneName));
      await _remember(url);
      notifyListeners();
      return (true, null);
    } catch (_) {
      connecting = false;
      error = 'Could not reach the receiver. Is the PC app running with '
          'the phone link on?';
      _ws = null;
      notifyListeners();
      return (false, error);
    }
  }

  void _closed() {
    _sub?.cancel();
    _sub = null;
    _ws = null;
    mappingEnabled = false;
    notifyListeners();
  }

  void send(PhoneMsg msg) {
    final ws = _ws;
    if (ws == null) return;
    try {
      ws.add(msg.encode());
    } on StateError catch (_) {
      // just closed; onDone fires next
    }
  }

  /// Controller state push, ~20 Hz while driving.
  void sendState(double steer, double throttle, double brake,
      Set<int> buttons) {
    send(PhoneStateMsg(
        steer: steer, throttle: throttle, brake: brake, buttons: buttons));
  }

  void toggleMapping() => send(const ToggleMsg());

  void disconnect() {
    final ws = _ws;
    _closed();
    try {
      ws?.close(1000);
    } on StateError catch (_) {}
    notifyListeners();
  }

  Future<void> _remember(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ringx.lastUrl', url);
    await prefs.setString('ringx.phoneName', phoneName);
  }

  static Future<String?> lastUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ringx.lastUrl');
  }
}

/// Saved templates (presets seeded on first run, edits, and any layout the
/// PC pushes back).
class TemplatePrefs extends ChangeNotifier {
  List<Template> _templates = [];
  String _activeName = '';

  List<Template> get templates => List.unmodifiable(_templates);

  Template? get active {
    for (final t in _templates) {
      if (t.name == _activeName) return t;
    }
    return _templates.isEmpty ? null : _templates.first;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('ringx.templates');
    if (raw == null) {
      _templates = Template.presets();
      _activeName = _templates.first.name;
      await _persist();
      return;
    }
    try {
      _templates = [for (final m in _decodeList(raw)) Template.fromJson(m)];
    } on FormatException {
      _templates = Template.presets();
    }
    if (_templates.isEmpty) _templates = Template.presets();
    _activeName = prefs.getString('ringx.templates.active') ??
        _templates.first.name;
    notifyListeners();
  }

  static List<Map<String, dynamic>> _decodeList(String raw) {
    final v = jsonDecode(raw);
    if (v is! List) throw const FormatException('not a template list');
    return [
      for (final m in v)
        if (m is Map) Map<String, dynamic>.from(m),
    ];
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ringx.templates', jsonEncode([
      for (final t in _templates) t.toJson(),
    ]));
    await prefs.setString('ringx.templates.active', _activeName);
  }

  Future<void> setActive(String name) async {
    if (_templates.any((t) => t.name == name)) {
      _activeName = name;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> saveAll(List<Template> templates) async {
    _templates = templates;
    if (!_templates.any((t) => t.name == _activeName) &&
        _templates.isNotEmpty) {
      _activeName = _templates.first.name;
    }
    await _persist();
    notifyListeners();
  }

  /// A layout pushed by the PC (replaces same-name, becomes active).
  Future<void> addFromPc(Template t) async {
    final name = t.name.startsWith('From PC') ? t.name : 'From PC · ${t.name}';
    final renamed = t.name == name ? t : t.copyWith(name: name);
    _templates = [
      renamed,
      ..._templates.where((x) => x.name != name),
    ];
    _activeName = name;
    await _persist();
    notifyListeners();
  }
}
