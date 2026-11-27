/// Wire protocol between the RingX phone controller and the PC receiver.
///
/// One JSON text frame per message. Both sides ignore unknown `t` types and
/// junk frames, so old and new builds interoperate — and the portable
/// Python edition speaks the same core subset (state / toggle / stat).
library;

import 'dart:convert';

/// Message kinds on the wire.
enum PhoneMsgKind { state, toggle, stat, hello, tpl }

/// One decoded controller frame.
sealed class PhoneMsg {
  const PhoneMsg();

  PhoneMsgKind get kind;

  Map<String, dynamic> toJson();

  String encode() => jsonEncode(toJson());

  /// Decodes one frame. Returns null for junk (mirrors the Python server:
  /// invalid JSON, non-objects and unknown types are dropped silently).
  static PhoneMsg? tryDecode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final json = Map<String, dynamic>.from(decoded);
    return switch (json['t']) {
      'state' => PhoneStateMsg.fromJson(json),
      'toggle' => const ToggleMsg(),
      'stat' => StatMsg.fromJson(json),
      'hello' => HelloMsg.fromJson(json),
      'tpl' => TemplateMsg.fromJson(json),
      _ => null,
    };
  }
}

double _clamp(num? v, double min, double max) {
  final d = (v ?? 0).toDouble();
  if (d.isNaN) return 0;
  return d < min ? min : (d > max ? max : d);
}

/// Phone -> PC, sent continuously (~20 Hz): live controller state.
final class PhoneStateMsg extends PhoneMsg {
  const PhoneStateMsg({
    required this.steer,
    required this.throttle,
    required this.brake,
    required this.buttons,
  });

  /// Steering: -1 full left .. +1 full right.
  final double steer;

  /// Throttle: 0 released .. 1 full.
  final double throttle;

  /// Brake: 0 released .. 1 full.
  final double brake;

  /// vJoy button numbers currently pressed (1..128).
  final Set<int> buttons;

  @override
  PhoneMsgKind get kind => PhoneMsgKind.state;

  @override
  Map<String, dynamic> toJson() => {
        't': 'state',
        's': steer,
        'th': throttle,
        'br': brake,
        'bt': buttons.toList()..sort(),
      };

  static PhoneStateMsg fromJson(Map<String, dynamic> json) {
    final raw = json['bt'];
    final buttons = <int>{
      if (raw is List)
        for (final b in raw)
          if (b is num && b.toInt() >= 1 && b.toInt() <= 128) b.toInt(),
    };
    return PhoneStateMsg(
      steer: _clamp(json['s'], -1.0, 1.0),
      throttle: _clamp(json['th'], 0.0, 1.0),
      brake: _clamp(json['br'], 0.0, 1.0),
      buttons: buttons,
    );
  }
}

/// Phone -> PC: toggle mapping on/off.
final class ToggleMsg extends PhoneMsg {
  const ToggleMsg();

  @override
  PhoneMsgKind get kind => PhoneMsgKind.toggle;

  @override
  Map<String, dynamic> toJson() => const {'t': 'toggle'};
}

/// PC -> Phone: mapping state push (sent whenever it flips).
final class StatMsg extends PhoneMsg {
  const StatMsg({required this.enabled});

  final bool enabled;

  @override
  PhoneMsgKind get kind => PhoneMsgKind.stat;

  @override
  Map<String, dynamic> toJson() => {'t': 'stat', 'enabled': enabled};

  static StatMsg? fromJson(Map<String, dynamic> json) =>
      json['enabled'] is bool ? StatMsg(enabled: json['enabled'] as bool) : null;
}

/// Phone -> PC right after connecting: who is calling.
final class HelloMsg extends PhoneMsg {
  const HelloMsg({required this.name, this.version = 1});

  /// Human label for the dashboard ('Redmi Note 12', 'Poco X5', ...).
  final String name;

  final int version;

  @override
  PhoneMsgKind get kind => PhoneMsgKind.hello;

  @override
  Map<String, dynamic> toJson() => {'t': 'hello', 'name': name, 'ver': version};

  static HelloMsg? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String) return null;
    return HelloMsg(
        name: name.length > 40 ? name.substring(0, 40) : name);
  }
}

/// Template sync, both directions: the raw template JSON travels inside.
/// The receiver validates it with [Template.tryParse] before using it.
final class TemplateMsg extends PhoneMsg {
  const TemplateMsg(this.template);

  final Map<String, dynamic> template;

  @override
  PhoneMsgKind get kind => PhoneMsgKind.tpl;

  @override
  Map<String, dynamic> toJson() => {'t': 'tpl', 'tpl': template};

  static TemplateMsg? fromJson(Map<String, dynamic> json) {
    final tpl = json['tpl'];
    if (tpl is! Map) return null;
    return TemplateMsg(Map<String, dynamic>.from(tpl));
  }
}
