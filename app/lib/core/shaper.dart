/// Analog shaping for keyboard-driven axes: turns on/off key state into a
/// ramped, curved, deadzone-safe output value. Pure logic — unit tested in
/// test/shaper_test.dart.
library;

/// Response curve applied to the ramp magnitude.
enum ResponseCurve {
  linear('Linear'),
  smooth('Smooth (S-curve)'),
  aggressive('Aggressive (fast start)');

  const ResponseCurve(this.label);
  final String label;
}

/// Tuning for one virtual axis.
class AxisConfig {
  const AxisConfig({
    this.attackMs = 350,
    this.decayMs = 180,
    this.curve = ResponseCurve.smooth,
    this.antiDeadzone = 0.05,
  });

  /// Milliseconds from neutral to full lock (press direction).
  final int attackMs;

  /// Milliseconds from full lock back to neutral (release direction).
  final int decayMs;

  /// Output response curve.
  final ResponseCurve curve;

  /// Minimum non-zero output (0.0–0.25). Keeps the game's inner steering
  /// deadzone engaged at all times so tiny inputs still steer.
  final double antiDeadzone;

  AxisConfig copyWith({
    int? attackMs,
    int? decayMs,
    ResponseCurve? curve,
    double? antiDeadzone,
  }) =>
      AxisConfig(
        attackMs: attackMs ?? this.attackMs,
        decayMs: decayMs ?? this.decayMs,
        curve: curve ?? this.curve,
        antiDeadzone: antiDeadzone ?? this.antiDeadzone,
      );

  Map<String, dynamic> toJson() => {
        'attackMs': attackMs,
        'decayMs': decayMs,
        'curve': curve.name,
        'antiDeadzone': antiDeadzone,
      };

  static AxisConfig fromJson(Map<String, dynamic> json) => AxisConfig(
        attackMs: _clampInt(json['attackMs'], 10, 5000, 350),
        decayMs: _clampInt(json['decayMs'], 10, 5000, 180),
        curve: ResponseCurve.values.firstWhere(
          (c) => c.name == json['curve'],
          orElse: () => ResponseCurve.smooth,
        ),
        antiDeadzone: _clampDouble(
            (json['antiDeadzone'] as num?)?.toDouble(), 0.0, 0.25, 0.05),
      );
}

int _clampInt(dynamic v, int min, int max, int fallback) {
  final i = v is num ? v.toInt() : fallback;
  return i < min ? min : (i > max ? max : i);
}

double _clampDouble(num? v, double min, double max, double fallback) {
  final d = (v ?? fallback).toDouble();
  return d < min ? min : (d > max ? max : d);
}

/// Integrates one axis toward a signed target (-1.0 .. 1.0).
class AxisShaper {
  /// Current raw ramp value. Steering: -1 full left .. +1 full right.
  /// Pedals: 0 released .. 1 full.
  double value = 0;

  /// Advances the ramp by [dtMs] milliseconds and returns the shaped output.
  ///
  /// The ramp rate depends on direction: pressing (target non-zero) uses
  /// [AxisConfig.attackMs]; easing back to neutral (target 0) uses
  /// [AxisConfig.decayMs]. Switching sides (e.g. full left to right) ramps
  /// through neutral at the attack rate, like a real wheel being spun.
  double step(double dtMs, double target, AxisConfig cfg) {
    if (dtMs > 0) {
      final rate = target == 0 ? dtMs / cfg.decayMs : dtMs / cfg.attackMs;
      if (value < target) {
        value = (value + rate) < target ? value + rate : target;
      } else if (value > target) {
        value = (value - rate) > target ? value - rate : target;
      }
      if (value > 1) value = 1;
      if (value < -1) value = -1;
    }
    return shape(value, cfg);
  }

  /// Maps a raw ramp magnitude through the curve and anti-deadzone floor.
  static double shape(double v, AxisConfig cfg) {
    final m = v.abs().clamp(0.0, 1.0);
    double out = switch (cfg.curve) {
      ResponseCurve.linear => m,
      ResponseCurve.smooth => m * m * (3 - 2 * m), // smoothstep
      ResponseCurve.aggressive => m <= 0 ? 0.0 : 1 - (1 - m) * (1 - m),
    };
    if (out > 0 && out < cfg.antiDeadzone) out = cfg.antiDeadzone;
    return v < 0 ? -out : out;
  }

  /// Snaps to neutral (used when mapping is disabled).
  void reset() => value = 0;
}
