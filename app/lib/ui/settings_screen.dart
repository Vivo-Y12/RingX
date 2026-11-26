/// Engine settings: vJoy device, tick rate, toggle hotkey, reset defaults.
library;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/profile.dart';
import '../core/vk_names.dart';
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
              ],
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
          'Ringx 0.1.0 — free, offline, no account. Turns your keyboard into '
          'a smooth virtual racing controller through vJoy. Original '
          'clean-room implementation; not affiliated with any other product.',
          style: TextStyle(color: Color(0xFF7A8089), fontSize: 12),
        ),
      ],
    );
  }
}
