/// Bindings editor and per-axis tuning. Edits apply to a draft profile and
/// persist (atomically) through [MapperEngine.applyProfile] on change end.
library;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/profile.dart';
import '../core/shaper.dart';
import '../core/vk_names.dart';
import 'widgets.dart';

class MappingScreen extends StatefulWidget {
  const MappingScreen({super.key, required this.engine});

  final MapperEngine engine;

  @override
  State<MappingScreen> createState() => _MappingScreenState();
}

class _MappingScreenState extends State<MappingScreen> {
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
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text('Bindings', style: t.titleMedium),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _addBinding,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add binding'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_draft.bindings.isEmpty)
          const Text('No bindings yet — add one to feed the virtual device.',
              style: TextStyle(color: Color(0xFF7A8089))),
        for (final (i, b) in _draft.bindings.indexed)
          Card(
            color: const Color(0xFF16181D),
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: KeyBadge(b.vk),
              title: Text(
                b.act == Act.button ? '${b.act.label} ${b.button}' : b.act.label,
                style: const TextStyle(fontSize: 14),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit',
                    onPressed: () => _editBinding(i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Remove',
                    onPressed: () => setState(() {
                      _draft = _draft.copyWith(
                          bindings: [..._draft.bindings]..removeAt(i));
                      _apply();
                    }),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text('Axis tuning', style: t.titleMedium),
        const SizedBox(height: 4),
        const Text(
            'Attack: time from neutral to full. Decay: time back to neutral. '
            'Anti-deadzone: smallest non-zero output so the game never ignores light input.',
            style: TextStyle(color: Color(0xFF7A8089), fontSize: 12)),
        const SizedBox(height: 12),
        for (final axis in AxisId.values)
          _AxisCard(
            axis: axis,
            cfg: _draft.axes[axis] ?? const AxisConfig(),
            onChangeEnd: (cfg) {
              setState(() {
                _draft = _draft.copyWith(axes: {..._draft.axes, axis: cfg});
              });
              _apply();
            },
          ),
      ],
    );
  }

  Future<void> _addBinding() async {
    final b = await _editDialog(null);
    if (b != null) {
      setState(() {
        _draft = _draft.copyWith(bindings: [..._draft.bindings, b]);
      });
      _apply();
    }
  }

  Future<void> _editBinding(int index) async {
    final b = await _editDialog(_draft.bindings[index]);
    if (b != null) {
      setState(() {
        final list = [..._draft.bindings];
        list[index] = b;
        _draft = _draft.copyWith(bindings: list);
      });
      _apply();
    }
  }

  Future<Binding?> _editDialog(Binding? initial) {
    var vk = initial?.vk ?? 0x00;
    var act = initial?.act ?? Act.steerLeft;
    var button = initial?.button ?? 1;
    return showDialog<Binding>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(initial == null ? 'Add binding' : 'Edit binding'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KeyCaptureField(
                engine: widget.engine,
                current: vk,
                onCaptured: (v) => setDialog(() => vk = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Act>(
                initialValue: act,
                decoration: const InputDecoration(labelText: 'Action'),
                items: [
                  for (final a in Act.values)
                    DropdownMenuItem(value: a, child: Text(a.label)),
                ],
                onChanged: (a) => setDialog(() => act = a!),r
              ),
              if (act == Act.button) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: button < 1 ? 1 : (button > 32 ? 32 : button),
                  decoration:
                      const InputDecoration(labelText: 'Button number'),
                  items: [
                    for (var n = 1; n <= 32; n++)
                      DropdownMenuItem(value: n, child: Text('Button $n')),
                  ],
                  onChanged: (n) => setDialog(() => button = n!),
                ),
              ],
              if (_draft.bindings.any((b) => b.vk == vk && b.vk != 0) &&
                  vk != initial?.vk)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Note: this key is already bound.',
                      style: TextStyle(color: Color(0xFFE5A13D), fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              // No key captured yet — nothing sensible to save.
              onPressed: vk == 0
                  ? null
                  : () => Navigator.pop(
                      context, Binding(vk: vk, act: act, button: button)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AxisCard extends StatefulWidget {
  const _AxisCard({
    required this.axis,
    required this.cfg,
    required this.onChangeEnd,
  });

  final AxisId axis;
  final AxisConfig cfg;
  final ValueChanged<AxisConfig> onChangeEnd;

  @override
  State<_AxisCard> createState() => _AxisCardState();
}

class _AxisCardState extends State<_AxisCard> {
  // Local drag state so sliders move live; commits happen on drag end.
  late double _attack = widget.cfg.attackMs / 1000;
  late double _decay = widget.cfg.decayMs / 1000;
  late double _antiDz = widget.cfg.antiDeadzone;

  static String _label(AxisId a) => switch (a) {
        AxisId.steer => 'Steering',
        AxisId.throttle => 'Throttle',
        AxisId.brake => 'Brake',
      };

  @override
  Widget build(BuildContext context) {
    final cfg = widget.cfg;
    return Card(
      color: const Color(0xFF16181D),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_label(widget.axis),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            _slider(
              'Attack',
              '${(_attack * 1000).round()} ms',
              _attack,
              (v) => setState(() => _attack = v),
              (v) => widget
                  .onChangeEnd(cfg.copyWith(attackMs: (v * 1000).round())),
            ),
            _slider(
              'Decay',
              '${(_decay * 1000).round()} ms',
              _decay,
              (v) => setState(() => _decay = v),
              (v) => widget
                  .onChangeEnd(cfg.copyWith(decayMs: (v * 1000).round())),
            ),
            _slider(
              'Anti-deadzone',
              '${(_antiDz * 100).round()}%',
              _antiDz,
              (v) => setState(() => _antiDz = v),
              (v) => widget.onChangeEnd(cfg.copyWith(antiDeadzone: v)),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<ResponseCurve>(
              initialValue: cfg.curve,
              decoration: const InputDecoration(labelText: 'Response curve'),
              items: [
                for (final c in ResponseCurve.values)
                  DropdownMenuItem(value: c, child: Text(c.label)),
              ],
              onChanged: (c) => widget.onChangeEnd(cfg.copyWith(curve: c!)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, String value, double current,
      ValueChanged<double> onChanged, ValueChanged<double> onChangedEnd) {
    return Row(
      children: [
        SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Color(0xFF7A8089)))),
        Expanded(
          child: Slider(
            value: current.clamp(0.0, 1.0),
            onChanged: onChanged,
            onChangeEnd: onChangedEnd,
          ),
        ),
        SizedBox(
            width: 64,
            child: Text(value,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.end)),
      ],
    );
  }
}
