/// Engine settings: vJoy device, tick rate, toggle hotkey, reset defaults.
library;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/profile.dart';
import '../core/shaper.dart';
import 'widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.engine});

  final MapperEngine engine;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Profile _draft = widget.engine.profile;

  void _apply() {
    final (ok, err) = widget.engine.applyProfile(_draft);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'Could not save profile.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Device & engine', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          color: const Color(0xFF16181D),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _draft.deviceId,
                  decoration: const InputDecoration(
                      labelText: 'vJoy device (configure axes in vJoyConf)'),
                  items: [
                    for (var n = 1; n <= 16; n++)
                      DropdownMenuItem(value: n, child: Text('Device $n')),
                  ],
                  onChanged: (n) => setState(() {
                    _draft = _draft.copyWith(deviceId: n);
                    _apply();
                  }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _draft.tickMs,
                  decoration: const InputDecoration(
                      labelText: 'Update rate (smaller = smoother)'),
                  items: const [
                    DropdownMenuItem(value: 5, child: Text('200 Hz (5 ms)')),
                    DropdownMenuItem(value: 10, child: Text('100 Hz (10 ms)')),
                    DropdownMenuItem(value: 20, child: Text('50 Hz (20 ms)')),
                  ],
                  onChanged: (v) => setState(() {
                    _draft = _draft.copyWith(tickMs: v!);
                    _apply();
                  }),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('Enable/disable hotkey',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const Spacer(),
                    KeyCaptureField(
                      engine: widget.engine,
                      current: _draft.toggleVk,
                      onCaptured: (vk) => setState(() {
                        _draft = _draft.copyWith(toggleVk: vk);
                        _apply();
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _draft.phonePort,
                  decoration: const InputDecoration(
                    labelText: 'Phone-link port (QR + browser page)',
                  ),
                  items: const [
                    DropdownMenuItem(value: 9870, child: Text('9870 (default)')),
                    DropdownMenuItem(value: 8765, child: Text('8765')),
                    DropdownMenuItem(value: 5555, child: Text('5555 (RojX-style)')),
                  ],
                  onChanged: (v) => setState(() {
                    _draft = _draft.copyWith(phonePort: v!);
                    _apply();
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Steering Calibration',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          color: const Color(0xFF16181D),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _CalibrationPanel(
              draft: _draft,
              onChanged: (next) => setState(() {
                _draft = next;
                _apply();
              }),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Profile', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          color: const Color(0xFF16181D),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stored at: ${widget.engine.store.dirPath}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF7A8089))),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _draft = Profile.defaults());
                    _apply();
                  },
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reset to racing defaults'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('About', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'RingX 0.2.0 — free, offline, no account. Turns your keyboard and '
          'phone into a smooth virtual racing controller through vJoy. '
          'Original clean-room implementation; not affiliated with any other '
          'product.',
          style: TextStyle(color: Color(0xFF7A8089), fontSize: 12),
        ),
      ],
    );
  }
}

/// Per-axis tuning with the racing-style labels: linearity, anti-deadzone,
/// steering limit, neutral offset, auto-center speed.
class _CalibrationPanel extends StatefulWidget {
  const _CalibrationPanel({required this.draft, required this.onChanged});

  final Profile draft;
  final ValueChanged<Profile> onChanged;

  @override
  State<_CalibrationPanel> createState() => _CalibrationPanelState();
}

class _CalibrationPanelState extends State<_CalibrationPanel> {
  AxisId _axis = AxisId.steer;

  AxisConfig get _cfg =>
      widget.draft.axes[_axis] ?? const AxisConfig();

  void _update(AxisConfig next) {
    final axes = Map<AxisId, AxisConfig>.of(widget.draft.axes)
      ..[_axis] = next;
    widget.onChanged(widget.draft.copyWith(axes: axes));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Axis chips.
        Wrap(
          spacing: 8,
          children: [
            for (final a in AxisId.values)
              ChoiceChip(
                label: Text(switch (a) {
                  AxisId.steer => 'Steering',
                  AxisId.throttle => 'Throttle',
                  AxisId.brake => 'Brake',
                }),
                selected: _axis == a,
                onSelected: (_) => setState(() => _axis = a),
                selectedColor: cs.primary.withValues(alpha: 0.25),
              ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ResponseCurve>(
          initialValue: _cfg.curve,
          decoration: const InputDecoration(
              labelText: 'Linearity (Curve Power)'),
          items: [
            for (final c in ResponseCurve.values)
              DropdownMenuItem(value: c, child: Text(c.label)),
          ],
          onChanged: (c) => _update(_cfg.copyWith(curve: c)),
        ),
        _Slider(
          label: _axis == AxisId.steer
              ? 'Steering speed (attack)'
              : 'Attack speed',
          value: _cfg.attackMs.toDouble(),
          min: 50,
          max: 2000,
          fmt: (v) => '${v.round()} ms',
          onChanged: (v) => _update(_cfg.copyWith(attackMs: v.round())),
        ),
        _Slider(
          label: 'Auto Center Wheel (return speed)',
          value: _cfg.decayMs.toDouble(),
          min: 40,
          max: 2000,
          fmt: (v) => '${v.round()} ms',
          onChanged: (v) => _update(_cfg.copyWith(decayMs: v.round())),
        ),
        _Slider(
          label: 'Anti-Deadzone (Game Bypass)',
          value: _cfg.antiDeadzone,
          min: 0,
          max: 0.25,
          fmt: (v) => '${(v * 100).round()}%',
          onChanged: (v) => _update(_cfg.copyWith(antiDeadzone: v)),
        ),
        if (_axis == AxisId.steer) ...[
          _Slider(
            label: 'Steering Limit (max angle)',
            value: _cfg.steeringLimit,
            min: 0.3,
            max: 1.0,
            fmt: (v) => '${(v * 100).round()}%',
            onChanged: (v) => _update(_cfg.copyWith(steeringLimit: v)),
          ),
          _Slider(
            label: 'Neutral Calibration Offset',
            value: _cfg.neutralOffset,
            min: -0.3,
            max: 0.3,
            fmt: (v) => v >= 0 ? '+${(v * 100).round()}%' : '${(v * 100).round()}%',
            onChanged: (v) => _update(_cfg.copyWith(neutralOffset: v)),
          ),
        ],
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.fmt,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double) fmt;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              activeColor: cs.primary,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              fmt(value),
              textAlign: TextAlign.end,
              style: const TextStyle(
                  fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}
