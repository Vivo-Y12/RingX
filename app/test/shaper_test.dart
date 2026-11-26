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
}
