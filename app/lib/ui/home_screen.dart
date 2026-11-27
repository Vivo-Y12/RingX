/// Ringx dashboard: live wheel/pedal gauges, status chips, mapping switch.
library;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/profile.dart';
import '../core/vk_names.dart';
import 'phone_panel.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.engine});

  final MapperEngine engine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final axes = engine.axisUsages;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                StatusChip(
                    engine.hookRunning ? 'Keyboard hook active' : 'No keyboard hook',
                    ok: engine.hookRunning,
                    error: !engine.hookRunning),
                const SizedBox(width: 10),
                StatusChip(engine.vjoyNote, ok: engine.acquired),
                const SizedBox(width: 10),
                StatusChip(
                    'Steer ${axes.containsKey(AxisId.steer) ? _axisName(axes[AxisId.steer]!) : '—'}'
                    ' · Throttle ${axes.containsKey(AxisId.throttle) ? _axisName(axes[AxisId.throttle]!) : '—'}'
                    ' · Brake ${axes.containsKey(AxisId.brake) ? _axisName(axes[AxisId.brake]!) : '—'}',
                    ok: axes.length == 3),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WheelGauge(steer: engine.steerOut),
                const SizedBox(width: 48),
                Row(
                  children: [
                    PedalBar(
                        value: engine.throttleOut,
                        label: 'THROTTLE',
                        color: const Color(0xFF46A758)),
                    const SizedBox(width: 20),
                    PedalBar(
                        value: engine.brakeOut,
                        label: 'BRAKE',
                        color: const Color(0xFFE5484D)),
                  ],
                ),
                const Spacer(),
                _Controls(engine: engine, cs: cs),
              ],
            ),
            const SizedBox(height: 24),
            PhonePanel(engine: engine),
            const SizedBox(height: 24),
            Text('Recent keys', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (engine.recentKeys.isEmpty)
                  const Text('Hold your mapped keys — they show up here.',
                      style: TextStyle(color: Color(0xFF7A8089)))
                else
                  for (final vk in engine.recentKeys)
                    KeyBadge(vk, held: engine.heldKeys.contains(vk)),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _axisName(int usage) => switch (usage) {
        0x30 => 'X',
        0x31 => 'Y',
        0x32 => 'Z',
        0x33 => 'RX',
        0x34 => 'RY',
        0x35 => 'RZ',
        0x36 => 'SL0',
        0x37 => 'SL1',
        _ => '0x${usage.toRadixString(16)}',
      };
}

class _Controls extends StatelessWidget {
  const _Controls({required this.engine, required this.cs});

  final MapperEngine engine;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SwitchListTile(
          title: const Text('Mapping', style: TextStyle(fontSize: 16)),
          subtitle: Text(
              'Hotkey: ${vkName(engine.profile.toggleVk)}',
              style: const TextStyle(fontSize: 12)),
          value: engine.enabled,
          onChanged: engine.setEnabled,
          activeColor: cs.primary,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: engine.centerAndReset,
          icon: const Icon(Icons.center_focus_strong, size: 18),
          label: const Text('Center & reset'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () {
            final (ok, err) = engine.applyProfile(engine.profile);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok
                    ? 'Profile saved to ${engine.store.dirPath}'
                    : (err ?? 'Could not save profile.')),
                behavior: SnackBarBehavior.floating,
              ));
            }
          },
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Save profile'),
        ),
      ],
    );
  }
}
