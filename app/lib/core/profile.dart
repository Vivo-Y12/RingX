/// Profile model (bindings + axis tuning + engine settings) and its JSON
/// store under %APPDATA%\Ringx. Everything loaded from disk is validated and
/// clamped before use — the file may be hand-edited or corrupt.
library;

import 'dart:convert';
import 'dart:io';

import 'shaper.dart';

/// What a key does.
enum Act {
  steerLeft('Steer Left'),
  steerRight('Steer Right'),
  throttle('Throttle'),
  brake('Brake'),
  button('Gamepad Button');

  const Act(this.label);
  final String label;
}

/// The three analog axes Ringx feeds to vJoy.
enum AxisId { steer, throttle, brake }

class Binding {
  const Binding({required this.vk, required this.act, this.button = 1});

  /// Windows virtual-key code.
  final int vk;
  final Act act;

  /// vJoy button number 1..128 when [act] is [Act.button].
  final int button;

  Map<String, dynamic> toJson() =>
      {'vk': vk, 'act': act.name, 'button': button};

  static Binding fromJson(Map<String, dynamic> json) {
    final vk = _clampInt(json['vk'], 0x01, 0xFE, 0);
    final act = Act.values.firstWhere(
      (a) => a.name == json['act'],
      orElse: () => Act.button,
    );
    return Binding(
        vk: vk, act: act, button: _clampInt(json['button'], 1, 128, 1));
  }
}

class Profile {
  const Profile({
    this.name = 'Default Racing',
    this.deviceId = 1,
    this.tickMs = 10,
    this.toggleVk = 0x77, // F8
    this.axes = const {
      AxisId.steer: AxisConfig(attackMs: 350, decayMs: 180),
      AxisId.throttle: AxisConfig(attackMs: 250, decayMs: 120),
      AxisId.brake: AxisConfig(attackMs: 150, decayMs: 90),
    },
    this.bindings = const [],
  });

  final String name;
  final int deviceId;
  final int tickMs;
  final int toggleVk;
  final Map<AxisId, AxisConfig> axes;
  final List<Binding> bindings;

  Profile copyWith({
    String? name,
    int? deviceId,
    int? tickMs,
    int? toggleVk,
    Map<AxisId, AxisConfig>? axes,
    List<Binding>? bindings,
  }) =>
      Profile(
        name: name ?? this.name,
        deviceId: deviceId ?? this.deviceId,
        tickMs: tickMs ?? this.tickMs,
        toggleVk: toggleVk ?? this.toggleVk,
        axes: axes ?? this.axes,
        bindings: bindings ?? this.bindings,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'deviceId': deviceId,
        'tickMs': tickMs,
        'toggleVk': toggleVk,
        'axes': {
          'steer': axes[AxisId.steer]?.toJson(),
          'throttle': axes[AxisId.throttle]?.toJson(),
          'brake': axes[AxisId.brake]?.toJson(),
        },
        'bindings': bindings.map((b) => b.toJson()).toList(),
      };

  static Profile fromJson(Map<String, dynamic> json) {
    final rawBindings = json['bindings'];
    final rawAxes = json['axes'];
    final rawName = json['name'] as String? ?? 'Default Racing';
    return Profile(
      name: rawName.length > 40 ? rawName.substring(0, 40) : rawName,
      deviceId: _clampInt(json['deviceId'], 1, 16, 1),
      tickMs: _clampInt(json['tickMs'], 5, 50, 10),
      toggleVk: _clampInt(json['toggleVk'], 0x01, 0xFE, 0x77),
      axes: {
        AxisId.steer: rawAxes is Map
            ? AxisConfig.fromJson(rawAxes['steer'] ?? const {})
            : const AxisConfig(attackMs: 350, decayMs: 180),
        AxisId.throttle: rawAxes is Map
            ? AxisConfig.fromJson(rawAxes['throttle'] ?? const {})
            : const AxisConfig(attackMs: 250, decayMs: 120),
        AxisId.brake: rawAxes is Map
            ? AxisConfig.fromJson(rawAxes['brake'] ?? const {})
            : const AxisConfig(attackMs: 150, decayMs: 90),
      },
      bindings: rawBindings is List
          ? [
              for (final b in rawBindings)
                if (b is Map) Binding.fromJson(b),
            ]
          : const [],
    );
  }

  /// Sensible racing defaults: WASD steering/pedals, Space as button 1.
  static Profile defaults() => const Profile(bindings: [
        Binding(vk: 0x41, act: Act.steerLeft),  // A
        Binding(vk: 0x44, act: Act.steerRight), // D
        Binding(vk: 0x57, act: Act.throttle),   // W
        Binding(vk: 0x53, act: Act.brake),      // S
        Binding(vk: 0x20, act: Act.button, button: 1), // Space
      ]);
}

class ProfileStore {
  ProfileStore();

  late final Directory _dir = _resolveDir();
  File? _file;

  String get dirPath => _dir.path;

  Directory _resolveDir() {
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    final dir = Directory('$appData\\Ringx');
    try {
      dir.createSync(recursive: true);
    } on FileSystemException {
      // Read-only home: fall back to temp so saving still works.
    }
    return dir;
  }

  /// Loads the saved profile, or defaults when missing/corrupt.
  /// Returns the profile plus a human-readable error when load failed.
  (Profile, String?) load() {
    final file = File('${_dir.path}\\default-profile.json');
    if (!file.existsSync()) return (Profile.defaults(), null);
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, dynamic>) {
        return (Profile.defaults(), 'Profile file was not an object.');
      }
      return (Profile.fromJson(json), null);
    } on FormatException catch (e) {
      return (Profile.defaults(), 'Profile file is corrupt: ${e.message}');
    } on FileSystemException catch (e) {
      return (Profile.defaults(), 'Profile file unreadable: ${e.message}');
    }
  }

  /// Writes the profile atomically (temp file + rename).
  (bool, String?) save(Profile profile) {
    final file = _file ??= File('${_dir.path}\\default-profile.json');
    final tmp = File('${file.path}.tmp');
    try {
      tmp.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(profile.toJson()),
        flush: true,
      );
      tmp.renameSync(file.path);
      return (true, null);
    } on FileSystemException catch (e) {
      try {
        tmp.deleteSync();
      } on FileSystemException {
        // temp file already gone
      }
      return (false, 'Could not save profile: ${e.message}');
    }
  }
}

int _clampInt(dynamic v, int min, int max, int fallback) {
  final i = v is num ? v.toInt() : fallback;
  return i < min ? min : (i > max ? max : i);
}
