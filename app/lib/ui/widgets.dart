/// Reusable Ringx widgets: the steering wheel gauge, pedal bars, status
/// chips, key badges and the press-to-capture key field.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide RawKeyEvent;

import '../core/engine.dart';
import '../core/keyhook.dart';
import '../core/vk_names.dart';

/// Big steering wheel visual: outer ring with a progress arc plus a wheel
/// that rotates with the live steering value.
class WheelGauge extends StatelessWidget {
  const WheelGauge({super.key, required this.steer});

  /// -1.0 (full left) .. 1.0 (full right).
  final double steer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 300,
      height: 300,
      child: CustomPaint(
        painter: _WheelPainter(steer: steer, accent: cs.primary),
        child: Center(
          child: Text(
            _label(),
            style: TextStyle(
              color: cs.primary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  String _label() {
    final pct = (steer.abs() * 100).round();
    return steer.abs() < 0.005
        ? 'CENTER'
        : '${steer < 0 ? 'L' : 'R'} $pct%';
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.steer, required this.accent});

  final double steer;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2 - 6;
    final wheelR = outer - 22;

    // Fixed outer ring.
    canvas.drawCircle(
        c, outer, Paint()..color = const Color(0xFF23262E)..strokeWidth = 8..style = PaintingStyle.stroke);

    // Progress arc from 12 o'clock, direction by sign.
    final sweep = steer.abs() * 4.7; // ~270 degrees at full lock
    final arc = Paint()
      ..color = accent.withValues(alpha: 0.9)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: outer),
        -3.14159 / 2, steer < 0 ? -sweep : sweep, false, arc);

    // Rotating wheel: rim + three spokes + hub.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(steer * 3.93); // ~225 degrees at full lock
    final rim = Paint()
      ..color = const Color(0xFF39404D)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset.zero, wheelR, rim);
    final spoke = Paint()
      ..color = const Color(0xFF2C313B)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    for (final a in <double>[
      math.pi / 2,
      math.pi * 7 / 6,
      math.pi * 11 / 6,
    ]) {
      canvas.drawLine(Offset.zero,
          Offset(math.cos(a) * wheelR, math.sin(a) * wheelR), spoke);
    }
    canvas.drawCircle(Offset.zero, 18, Paint()..color = accent.withValues(alpha: 0.85));
    canvas.drawCircle(
        Offset.zero, 18, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFF12141A));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.steer != steer || old.accent != accent;
}

/// Vertical pedal bar with live fill.
class PedalBar extends StatelessWidget {
  const PedalBar({
    super.key,
    required this.value,
    required this.label,
    required this.color,
  });

  final double value; // 0..1
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${(value * 100).round()}%',
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 6),
        Container(
          width: 56,
          height: 210,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1D23),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2E36)),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 1,
              heightFactor: value.clamp(0.0, 1.0),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }
}

/// Small dot + label status line.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.ok = true, this.error = false});

  final String label;
  final bool ok;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final dot = error
        ? const Color(0xFFE5484D)
        : ok
            ? const Color(0xFF46A758)
            : const Color(0xFFE5A13D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D23),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2A2E36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Key name chip, highlighted while held.
class KeyBadge extends StatelessWidget {
  const KeyBadge(this.vk, {super.key, this.held = false});

  final int vk;
  final bool held;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: held ? cs.primary.withValues(alpha: 0.25) : const Color(0xFF1A1D23),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
            color: held ? cs.primary : const Color(0xFF2A2E36)),
      ),
      child: Text(
        vkName(vk),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: held ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A field that captures the next physical key press. Tapping starts capture;
/// Esc cancels. Shows the current key otherwise.
class KeyCaptureField extends StatefulWidget {
  const KeyCaptureField({
    super.key,
    required this.engine,
    required this.current,
    required this.onCaptured,
    this.hint = 'Press a key…',
  });

  final MapperEngine engine;
  final int current;
  final ValueChanged<int> onCaptured;
  final String hint;

  @override
  State<KeyCaptureField> createState() => _KeyCaptureFieldState();
}

class _KeyCaptureFieldState extends State<KeyCaptureField> {
  StreamSubscription<RawKeyEvent>? _sub;
  bool _capturing = false;

  void _startCapture() {
    setState(() => _capturing = true);
    _sub = widget.engine.keyEvents.listen((ev) {
      if (!ev.down) return;
      _sub?.cancel();
      _sub = null;
      if (mounted) {
        setState(() => _capturing = false);
        if (ev.vk != 0x1B) widget.onCaptured(ev.vk); // Esc cancels
      }
    });
  }

  void _cancelCapture() {
    _sub?.cancel();
    _sub = null;
    if (mounted) setState(() => _capturing = false);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: _capturing ? _cancelCapture : _startCapture,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: _capturing ? cs.primary : const Color(0xFF2A2E36)),
        backgroundColor: _capturing ? cs.primary.withValues(alpha: 0.12) : null,
        minimumSize: const Size(140, 44),
      ),
      icon: Icon(_capturing ? Icons.keyboard_alt : Icons.keyboard,
          size: 18, color: _capturing ? cs.primary : cs.onSurfaceVariant),
      label: Text(
        _capturing
            ? 'press a key… (Esc cancels)'
            : vkName(widget.current),
        style: TextStyle(
            fontSize: 13, color: _capturing ? cs.primary : cs.onSurface),
      ),
    );
  }
}
