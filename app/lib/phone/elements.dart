/// Touch controls rendered from template elements: steering wheel, pedals,
/// round buttons, thumbsticks, PRND selector and paddle shifters. All state
/// lives in the parent (controller screen or editor); these widgets report
/// gestures and paint themselves.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/templates.dart';

const Color _bg = Color(0xFF12151B);
const Color _bgRaised = Color(0xFF1A1D23);
const Color _line = Color(0xFF2A2E36);
const Color amber = Color(0xFFF5A524);
const Color green = Color(0xFF46A758);
const Color red = Color(0xFFE5484D);

/// Steer -1..1 from finger rotation around the wheel center.
class WheelWidget extends StatefulWidget {
  const WheelWidget({
    super.key,
    required this.value,
    required this.onSteer,
    this.enabled = true,
  });

  /// Current steering value, used for the painted rotation.
  final double value;

  /// New absolute steering value (already clamped by the widget).
  final ValueChanged<double> onSteer;

  final bool enabled;

  @override
  State<WheelWidget> createState() => _WheelWidgetState();
}

class _WheelWidgetState extends State<WheelWidget> {
  /// Radians of finger rotation for full lock.
  static const double _maxRot = 2.4;

  Offset? _lastPos;
  double _steer = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: widget.enabled ? _panStart : null,
      onPanUpdate: widget.enabled ? _panUpdate : null,
      child: CustomPaint(
        painter:
            _TouchWheelPainter(value: widget.value, enabled: widget.enabled),
        size: Size.infinite,
      ),
    );
  }

  void _panStart(DragStartDetails d) {
    _lastPos = d.localPosition;
    _steer = widget.value;
  }

  void _panUpdate(DragUpdateDetails d) {
    final last = _lastPos;
    _lastPos = d.localPosition;
    if (last == null) return;
    final size = context.size;
    if (size == null) return;
    final c = Offset(size.width / 2, size.height / 2);
    final a0 = _angle(last - c);
    final a1 = _angle(d.localPosition - c);
    var delta = a1 - a0;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _steer = (_steer + delta / _maxRot).clamp(-1.0, 1.0);
    widget.onSteer(_steer);
  }

  static double _angle(Offset o) => math.atan2(o.dy, o.dx);
}

class _TouchWheelPainter extends CustomPainter {
  _TouchWheelPainter({required this.value, required this.enabled});

  final double value;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 3;
    if (r <= 0) return;

    // Plate.
    canvas.drawCircle(c, r, Paint()..color = _bg);
    canvas.drawCircle(
        c, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = _line);

    // Wheel rotated by the live value.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(value * 3.93); // ~225° at full lock, like the receiver gauge
    final rim = Paint()
      ..color = enabled ? const Color(0xFF39404D) : const Color(0xFF2C313B)
      ..strokeWidth = math.max(10, r * 0.16)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset.zero, r * 0.78, rim);
    final spoke = Paint()
      ..color = enabled ? const Color(0xFF2C313B) : const Color(0xFF242830)
      ..strokeWidth = math.max(7, r * 0.11)
      ..strokeCap = StrokeCap.round;
    for (final a in <double>[
      math.pi / 2,
      math.pi * 7 / 6,
      math.pi * 11 / 6,
    ]) {
      canvas.drawLine(Offset.zero,
          Offset(math.cos(a) * r * 0.78, math.sin(a) * r * 0.78), spoke);
    }
    // Amber top marker so the rotation reads at a glance.
    final marker = Paint()
      ..color = enabled ? amber : const Color(0xFF565B66)
      ..strokeWidth = math.max(5, r * 0.08)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, -r * 0.78), Offset(0, -r * 0.52), marker);
    canvas.drawCircle(
        Offset.zero,
        math.max(10, r * 0.22),
        Paint()..color = enabled ? amber.withValues(alpha: 0.9) : _line);
    canvas.restore();

    // Progress arc on the plate's edge.
    final sweep = value.abs() * 4.7;
    final arc = Paint()
      ..color = amber.withValues(alpha: 0.9)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
        -math.pi / 2, value < 0 ? -sweep : sweep, false, arc);
  }

  @override
  bool shouldRepaint(_TouchWheelPainter old) =>
      old.value != value || old.enabled != enabled;
}

/// Analog pedal pad: drag up/down for 0..1 (tap = full press).
class PedalWidget extends StatefulWidget {
  const PedalWidget({
    super.key,
    required this.value,
    required this.onPedal,
    required this.label,
    required this.color,
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onPedal;
  final String label;
  final Color color;
  final bool enabled;

  @override
  State<PedalWidget> createState() => _PedalWidgetState();
}

class _PedalWidgetState extends State<PedalWidget> {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => _setFrom(d.localPosition),
        onPanUpdate: (d) => _setFrom(d.localPosition),
        onPanEnd: (_) => widget.onPedal(0),
        onPanCancel: () => widget.onPedal(0),
        child: CustomPaint(
          painter: _PedalPainter(
              value: widget.value,
              label: widget.label,
              color: widget.color),
          size: Size.infinite,
        ),
      ),
    );
  }

  void _setFrom(Offset p) {
    final size = context.size;
    if (size == null || size.height <= 0) return;
    widget.onPedal((1 - p.dy / size.height).clamp(0.0, 1.0));
  }
}

class _PedalPainter extends CustomPainter {
  _PedalPainter({required this.value, required this.label, required this.color});

  final double value;
  final String label;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(14));
    canvas.drawRRect(rrect, Paint()..color = _bgRaised);
    canvas.drawRRect(
        rrect, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = _line);

    // Fill from the bottom by value.
    final h = size.height * value.clamp(0.0, 1.0);
    if (h > 1) {
      final fill = RRect.fromRectAndRadius(
          Rect.fromLTWH(0, size.height - h, size.width, h),
          const Radius.circular(12));
      canvas.drawRRect(fill, Paint()..color = color.withValues(alpha: 0.75));
    }
    _text(canvas, label, Offset(size.width / 2, 14));
    _text(
        canvas,
        value > 0.005 ? '${(value * 100).round()}%' : '',
        Offset(size.width / 2, size.height - 16));
  }

  void _text(Canvas canvas, String s, Offset at) {
    if (s.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PedalPainter old) =>
      old.value != value || old.label != label || old.color != color;
}

/// Round momentary button.
class TouchButtonWidget extends StatelessWidget {
  const TouchButtonWidget({
    super.key,
    required this.pressed,
    required this.label,
    required this.onPressed,
    this.color,
    this.enabled = true,
  });

  final bool pressed;
  final String label;
  final ValueChanged<bool> onPressed;
  final Color? color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onPressed(true),
        onTapUp: (_) => onPressed(false),
        onTapCancel: () => onPressed(false),
        child: CustomPaint(
          painter: _RoundButtonPainter(
              pressed: pressed, label: label, color: color ?? amber),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _RoundButtonPainter extends CustomPainter {
  _RoundButtonPainter(
      {required this.pressed, required this.label, required this.color});

  final bool pressed;
  final String label;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 3;
    if (r <= 0) return;
    canvas.drawCircle(c, r,
        Paint()..color = pressed ? color.withValues(alpha: 0.55) : _bgRaised);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = pressed ? color : color.withValues(alpha: 0.55));
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              color: pressed ? Colors.white : Colors.white70,
              fontSize: r * 0.34,
              fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_RoundButtonPainter old) =>
      old.pressed != pressed || old.label != label || old.color != color;
}

/// Analog thumbstick with a spring knob.
class StickWidget extends StatefulWidget {
  const StickWidget({
    super.key,
    required this.offset,
    required this.onStick,
    this.enabled = true,
  });

  /// Knob offset, dx/dy in -1..1.
  final Offset offset;

  /// New normalized (dx, dy).
  final ValueChanged<Offset> onStick;

  final bool enabled;

  @override
  State<StickWidget> createState() => _StickWidgetState();
}

class _StickWidgetState extends State<StickWidget> {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => _setFrom(d.localPosition),
        onPanUpdate: (d) => _setFrom(d.localPosition),
        onPanEnd: (_) => widget.onStick(Offset.zero),
        onPanCancel: () => widget.onStick(Offset.zero),
        child: CustomPaint(
          painter:
              _StickPainter(offset: widget.offset, enabled: widget.enabled),
          size: Size.infinite,
        ),
      ),
    );
  }

  void _setFrom(Offset p) {
    final size = context.size;
    if (size == null) return;
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;
    if (r <= 0) return;
    var v = (p - c) / r;
    final len = v.distance;
    if (len > 1) v = v / len;
    widget.onStick(Offset(v.dx.clamp(-1.0, 1.0), v.dy.clamp(-1.0, 1.0)));
  }
}

class _StickPainter extends CustomPainter {
  _StickPainter({required this.offset, required this.enabled});

  final Offset offset;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2 - 3;
    if (r <= 0) return;
    canvas.drawCircle(c, r, Paint()..color = _bg);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _line);
    // Crosshair.
    final hair = Paint()
      ..color = const Color(0xFF23262E)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx - r * .6, c.dy), Offset(c.dx + r * .6, c.dy), hair);
    canvas.drawLine(Offset(c.dx, c.dy - r * .6), Offset(c.dx, c.dy + r * .6), hair);
    // Knob.
    final kr = r * 0.34;
    final k = Offset(c.dx + offset.dx * (r - kr), c.dy + offset.dy * (r - kr));
    canvas.drawCircle(
        k,
        kr,
        Paint()
          ..color = enabled
              ? amber.withValues(alpha: offset == Offset.zero ? 0.85 : 1)
              : const Color(0xFF565B66));
    canvas.drawCircle(
        k, kr, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = _bg);
  }

  @override
  bool shouldRepaint(_StickPainter old) =>
      old.offset != offset || old.enabled != enabled;
}

/// PRND gear selector — momentary press (150 ms) per RojX, so games that
/// expect single inputs work.
class PrndWidget extends StatelessWidget {
  const PrndWidget({
    super.key,
    required this.baseButton,
    required this.onButton,
    required this.activeGear,
    this.enabled = true,
  });

  /// P = [baseButton], R = +1, N = +2, D = +3.
  final int baseButton;
  final ValueChanged<(int, bool)> onButton;
  final int activeGear; // 0..3, -1 none

  final bool enabled;

  static const _labels = ['P', 'R', 'N', 'D'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: _GearChip(
              label: _labels[i],
              highlight: i == activeGear,
              enabled: enabled,
              onTap: () {
                onButton((baseButton + i, true));
                Future.delayed(const Duration(milliseconds: 150), () {
                  onButton((baseButton + i, false));
                });
              },
            ),
          ),
      ],
    );
  }
}

class _GearChip extends StatelessWidget {
  const _GearChip({
    required this.label,
    required this.onTap,
    this.highlight = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool highlight;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !enabled,
      child: GestureDetector(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1.25,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            decoration: BoxDecoration(
              color: highlight ? amber.withValues(alpha: 0.28) : _bgRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: highlight ? amber : _line, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: highlight ? amber : Colors.white70,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paddle shifters: hold + / −.
class ShiftWidget extends StatelessWidget {
  const ShiftWidget({
    super.key,
    required this.baseButton,
    required this.onButton,
    this.enabled = true,
  });

  /// Up = [baseButton], down = +1.
  final int baseButton;
  final ValueChanged<(int, bool)> onButton;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Paddle(
          label: '−',
          enabled: enabled,
          onHold: (down) => onButton((baseButton + 1, down)),
        ),
        _Paddle(
          label: '+',
          enabled: enabled,
          onHold: (down) => onButton((baseButton, down)),
        ),
      ],
    );
  }
}

class _Paddle extends StatelessWidget {
  const _Paddle({
    required this.label,
    required this.onHold,
    this.enabled = true,
  });

  final String label;
  final ValueChanged<bool> onHold;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: IgnorePointer(
        ignoring: !enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => onHold(true),
          onTapUp: (_) => onHold(false),
          onTapCancel: () => onHold(false),
          child: AspectRatio(
            aspectRatio: 0.62,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: _bgRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _line, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: const TextStyle(
                      color: amber,
                      fontSize: 26,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Static mini-preview used by the editor canvas (non-interactive).
class ElementPreview extends StatelessWidget {
  const ElementPreview({super.key, required this.element, this.selected = false});

  final TplElement element;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: selected ? amber : _line, width: selected ? 2 : 1),
        color: _bgRaised.withValues(alpha: 0.6),
      ),
      alignment: Alignment.center,
      child: _icon(),
    );
  }

  Widget _icon() {
    final s = switch (element.kind) {
      ElKind.wheel => Icons.radio_button_checked,
      ElKind.pedalGas => Icons.keyboard_double_arrow_up,
      ElKind.pedalBrake => Icons.keyboard_double_arrow_down,
      ElKind.button => Icons.circle_outlined,
      ElKind.stick => Icons.gamepad_outlined,
      ElKind.prnd => Icons.view_module_outlined,
      ElKind.shift => Icons.unfold_more,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(s, size: 16, color: amber),
        if (element.label.isNotEmpty)
          Text(element.label,
              style: const TextStyle(
                  fontSize: 8, color: Colors.white70,
                  fontWeight: FontWeight.w700)),
      ],
    );
  }
}
