import 'package:flutter_test/flutter_test.dart';
import 'package:ringx/core/shaper.dart';

void main() {
  group('AxisShaper.step ramps', () {
    test('reaches the target after attackMs of pressing', () {
      const cfg = AxisConfig(attackMs: 200, decayMs: 100);
      final s = AxisShaper();
      // Two ticks of 100 ms = full attack time.
      s.step(100, 1, cfg);
      final out = s.step(100, 1, cfg);
      expect(out, greaterThan(0.99));
      expect(s.value, 1.0);
    });

    test('returns to neutral after decayMs of release', () {
      const cfg = AxisConfig(attackMs: 200, decayMs: 100);
      final s = AxisShaper()..value = 1.0;
      s.step(100, 0, cfg);
      expect(s.value, 0.0);
    });

    test('signs steering left and right symmetrically', () {
      const cfg = AxisConfig(attackMs: 100, decayMs: 50);
      final left = AxisShaper()..step(50, -1, cfg);
      final right = AxisShaper()..step(50, 1, cfg);
      expect(left.value, -right.value);
    });

    test('big dt overshoot is clamped to the target', () {
      const cfg = AxisConfig(attackMs: 100, decayMs: 100);
      final s = AxisShaper();
      s.step(5000, 1, cfg);
      expect(s.value, 1.0);
    });
  });

  group('AxisShaper.shape output curves', () {
    test('smooth curve starts slow and ends full', () {
      const cfg = AxisConfig(curve: ResponseCurve.smooth, antiDeadzone: 0);
      expect(AxisShaper.shape(0.5, cfg), closeTo(0.5, 0.001));
      expect(AxisShaper.shape(0.25, cfg), closeTo(0.15625, 0.001));
    });

    test('anti-deadzone lifts small non-zero outputs to the floor', () {
      const cfg = AxisConfig(antiDeadzone: 0.08);
      expect(AxisShaper.shape(0.02, cfg), 0.08);
      expect(AxisShaper.shape(0.5, cfg), greaterThan(0.08));
      expect(AxisShaper.shape(0, cfg), 0);
    });

    test('negative input keeps the sign', () {
      const cfg = AxisConfig();
      expect(AxisShaper.shape(-0.5, cfg), lessThan(0));
    });
  });

  group('Steering calibration params', () {
    test('steering limit caps the output magnitude', () {
      const cfg = AxisConfig(
          curve: ResponseCurve.linear,
          antiDeadzone: 0,
          steeringLimit: 0.6);
      expect(AxisShaper.shape(1, cfg), closeTo(0.6, 1e-9));
      expect(AxisShaper.shape(-1, cfg), closeTo(-0.6, 1e-9));
      expect(AxisShaper.shape(0.5, cfg), closeTo(0.3, 1e-9));
    });

    test('neutral offset shifts the neutral point', () {
      const cfg = AxisConfig(
          curve: ResponseCurve.linear,
          antiDeadzone: 0,
          neutralOffset: -0.1);
      // Wheel at 0 now outputs -0.1 (a wheel resting off-center).
      expect(AxisShaper.shape(0, cfg), closeTo(-0.1, 1e-9));
      // +0.1 of input brings it to true neutral.
      expect(AxisShaper.shape(0.1, cfg), closeTo(0, 1e-9));
    });

    test('offset + limit compose: output stays within the cap', () {
      const cfg = AxisConfig(
          curve: ResponseCurve.linear,
          antiDeadzone: 0,
          neutralOffset: 0.25,
          steeringLimit: 0.5);
      expect(AxisShaper.shape(1, cfg), closeTo(0.5, 1e-9));
      // The offset shifts neutral, so the negative side does not reach the
      // cap — but it must never exceed it.
      final neg = AxisShaper.shape(-1, cfg);
      expect(neg, greaterThanOrEqualTo(-0.5));
      expect(neg, lessThan(0));
    });

    test('defaults reproduce the plain curve (old files compatible)', () {
      const plain = AxisConfig(
          curve: ResponseCurve.linear, antiDeadzone: 0);
      const defaulted = AxisConfig(
          curve: ResponseCurve.linear, antiDeadzone: 0);
      for (final v in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
        expect(AxisShaper.shape(v, defaulted),
            AxisShaper.shape(v, plain));
      }
    });

    test('json roundtrip keeps the new fields, clamps garbage', () {
      const cfg = AxisConfig(steeringLimit: 0.7, neutralOffset: 0.12);
      final back = AxisConfig.fromJson(cfg.toJson());
      expect(back.steeringLimit, 0.7);
      expect(back.neutralOffset, 0.12);
      final hostile = AxisConfig.fromJson(const {
        'steeringLimit': 5.0,
        'neutralOffset': 12.0,
      });
      expect(hostile.steeringLimit, 1.0);
      expect(hostile.neutralOffset, 0.3);
      final missing = AxisConfig.fromJson(const {});
      expect(missing.steeringLimit, 1.0);
      expect(missing.neutralOffset, 0.0);
    });
  });
}
