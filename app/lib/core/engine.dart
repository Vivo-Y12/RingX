/// Ringx mapping engine: keyboard hook -> shaped analog axes / buttons ->
/// vJoy device. Owns the tick loop and all live state shown in the UI.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'keyhook.dart';
import 'profile.dart';
import 'shaper.dart';
import 'vjoy.dart';

/// vJoy usage candidates per Ringx axis; the first one the configured device
/// actually has wins. Defaults match a standard 8-axis vJoy device.
const Map<AxisId, List<int>> _axisCandidates = {
  AxisId.steer: [hidUsageX, hidUsageRx],
  AxisId.throttle: [hidUsageY, hidUsageRy, hidUsageSl0],
  AxisId.brake: [hidUsageZ, hidUsageRz, hidUsageSl1],
};

class MapperEngine extends ChangeNotifier {
  MapperEngine({required this.store}) : profile = Profile.defaults();

  final ProfileStore store;
  Profile profile;

  final KeyHook _hook = KeyHook();
  Vjoy? _vjoy;
  Timer? _timer;
  StreamSubscription<RawKeyEvent>? _keySub;

  final Map<AxisId, AxisShaper> _shapers = {
    for (final a in AxisId.values) a: AxisShaper(),
  };

  /// Resolved vJoy usage per axis (null when the device lacks it).
  final Map<AxisId, int> _usage = {};
  final Map<AxisId, (int, int)> _range = {};

  final Set<int> _held = {};
  final Set<int> _pressedButtons = {};
  final List<int> _recentKeys = [];

  bool _enabled = false;
  bool _acquired = false;
  bool _hookOk = false;
  int _lastNotifyMs = 0;
  String _vjoyNote = '';

  // ---- Live state for the UI --------------------------------------------

  /// True when the keyboard hook is installed (Windows runner only).
  bool get hookRunning => _hookOk;

  /// Raw key events, for the press-to-capture fields in the editors.
  Stream<RawKeyEvent> get keyEvents => _hook.events;

  /// True when a vJoy device is acquired and receives output.
  bool get acquired => _acquired;

  /// Human-readable vJoy state ('driver missing', 'device busy', ...).
  String get vjoyNote => _vjoyNote;

  /// Mapping active? (the F8 hotkey toggles this).
  bool get enabled => _enabled;

  /// Shaped outputs, -1..1 steer / 0..1 pedals.
  double get steerOut => AxisShaper.shape(_shapers[AxisId.steer]!.value,
      profile.axes[AxisId.steer] ?? const AxisConfig());
  double get throttleOut => AxisShaper.shape(_shapers[AxisId.throttle]!.value,
      profile.axes[AxisId.throttle] ?? const AxisConfig());
  double get brakeOut => AxisShaper.shape(_shapers[AxisId.brake]!.value,
      profile.axes[AxisId.brake] ?? const AxisConfig());

  /// Currently held virtual-key codes.
  Set<int> get heldKeys => Set.unmodifiable(_held);

  /// vJoy button numbers currently pressed (1-based).
  Set<int> get pressedButtons => Set.unmodifiable(_pressedButtons);

  /// Last key-downs, newest first, capped for the dashboard badges.
  List<int> get recentKeys => List.unmodifiable(_recentKeys);

  /// Resolved vJoy usage per axis (for the status chips).
  Map<AxisId, int> get axisUsages => Map.unmodifiable(_usage);

  // ---- Lifecycle ---------------------------------------------------------

  /// Boots the engine: hook on, vJoy open + acquire, tick loop running.
  /// Safe to call on machines without vJoy (UI shows the note).
  void start() {
    _hookOk = _hook.available && _hook.start();
    if (_hookOk) _keySub = _hook.events.listen(_onKey);
    _vjoy = Vjoy.tryOpen();
    _applyDevice();
    _restartTimer();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _keySub?.cancel();
    _hook.dispose();
    _releaseDevice();
    super.dispose();
  }

  /// Swaps the profile, re-acquiring the device or re-timing the loop when
  /// needed, and persists it. Returns (ok, error) from the save.
  (bool, String?) applyProfile(Profile next) {
    final old = profile;
    if (next.deviceId != old.deviceId) {
      _releaseDevice(old.deviceId); // release the OLD id before switching
    }
    profile = next;
    if (next.deviceId != old.deviceId) _applyDevice();
    if (next.tickMs != old.tickMs) _restartTimer();
    _resetOutputs();
    notifyListeners();
    return store.save(next);
  }

  /// (Re)acquires the configured vJoy device.
  void _applyDevice() {
    _releaseDevice();
    final vjoy = _vjoy;
    _usage.clear();
    _range.clear();
    if (vjoy == null) {
      _vjoyNote = 'vJoy driver not found (install vJoy 2.1.9+).';
      return;
    }
    if (!vjoy.driverEnabled) {
      _vjoyNote = 'vJoy driver is not enabled.';
      return;
    }
    final id = profile.deviceId;
    final status = vjoy.deviceStatus(id);
    switch (status) {
      case VjdStat.own || VjdStat.free:
        if (!vjoy.acquire(id)) {
          _vjoyNote = 'vJoy device $id could not be acquired.';
          return;
        }
        _acquired = true;
        vjoy.reset(id);
        _vjoyNote = 'vJoy device $id acquired.';
        for (final e in _axisCandidates.entries) {
          for (final usage in e.value) {
            if (vjoy.axisExists(id, usage)) {
              _usage[e.key] = usage;
              _range[e.key] = vjoy.axisRange(id, usage);
              break;
            }
          }
        }
      case VjdStat.busy:
        _vjoyNote = 'vJoy device $id is owned by another app.';
      case VjdStat.miss:
        _vjoyNote = 'vJoy device $id is missing (enable it in vJoyConf).';
      case VjdStat.unkn:
        _vjoyNote = 'vJoy device $id status unknown.';
    }
  }

  void _releaseDevice([int? deviceId]) {
    if (_acquired) {
      _resetOutputs();
      _vjoy?.relinquish(deviceId ?? profile.deviceId);
      _acquired = false;
    }
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(milliseconds: profile.tickMs), (_) {
      _tick(profile.tickMs.toDouble());
    });
  }

  // ---- Input routing -----------------------------------------------------

  void _onKey(RawKeyEvent ev) {
    final vk = ev.vk;
    if (vk == profile.toggleVk) {
      // Only the down-transition toggles; auto-repeat must not spam it.
      if (ev.down && !_held.contains(vk)) setEnabled(!enabled);
      if (ev.down) _held.add(vk);
      if (!ev.down) _held.remove(vk);
      return;
    }
    if (ev.down && !_held.contains(vk)) {
      _recentKeys.insert(0, vk);
      if (_recentKeys.length > 12) _recentKeys.removeLast();
    }
    ev.down ? _held.add(vk) : _held.remove(vk);
    if (_enabled && _acquired) {
      for (final b in profile.bindings) {
        if (b.vk == vk && b.act == Act.button) {
          _setButton(b.button, ev.down);
        }
      }
    }
    _notifyThrottled(force: true);
  }

  /// Toggles mapping; when turning off, all buttons release and axes ease to
  /// neutral on the next ticks.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!_enabled) {
      for (final btn in _pressedButtons.toList()) {
        _setButton(btn, false);
      }
    }
    notifyListeners();
  }

  void _setButton(int button, bool pressed) {
    final vjoy = _vjoy;
    if (vjoy == null || !_acquired) return;
    vjoy.setBtn(pressed, profile.deviceId, button);
    pressed ? _pressedButtons.add(button) : _pressedButtons.remove(button);
  }

  /// Neutralizes outputs immediately (buttons off, axes centered).
  void _resetOutputs() {
    for (final btn in _pressedButtons.toList()) {
      _setButton(btn, false);
    }
    for (final s in _shapers.values) {
      s.reset();
    }
    _writeAxes();
  }

  /// Public reset used by the dashboard button: neutral + reset vJoy device.
  void centerAndReset() {
    _resetOutputs();
    _vjoy?.reset(profile.deviceId);
    notifyListeners();
  }

  // ---- Tick --------------------------------------------------------------

  void _tick(double dtMs) {
    if (_enabled) {
      _shapers[AxisId.steer]!
          .step(dtMs, _steerTarget(), _axisCfg(AxisId.steer));
      _shapers[AxisId.throttle]!
          .step(dtMs, _keyTarget(Act.throttle), _axisCfg(AxisId.throttle));
      _shapers[AxisId.brake]!
          .step(dtMs, _keyTarget(Act.brake), _axisCfg(AxisId.brake));
    } else {
      // Ease back to neutral so the wheel visibly returns to center.
      for (final a in AxisId.values) {
        _shapers[a]!.step(dtMs, 0, _axisCfg(a));
      }
    }
    _writeAxes();
    _notifyThrottled();
  }

  AxisConfig _axisCfg(AxisId a) => profile.axes[a] ?? const AxisConfig();

  double _steerTarget() {
    var t = 0.0;
    for (final b in profile.bindings) {
      if (!_held.contains(b.vk)) continue;
      if (b.act == Act.steerLeft) t -= 1;
      if (b.act == Act.steerRight) t += 1;
    }
    return t.clamp(-1.0, 1.0);
  }

  double _keyTarget(Act act) {
    for (final b in profile.bindings) {
      if (b.act == act && _held.contains(b.vk)) return 1;
    }
    return 0;
  }

  void _writeAxes() {
    final vjoy = _vjoy;
    if (vjoy == null || !_acquired) return;
    final id = profile.deviceId;
    _writeAxis(vjoy, id, AxisId.steer, steerOut, centered: true);
    _writeAxis(vjoy, id, AxisId.throttle, throttleOut, centered: false);
    _writeAxis(vjoy, id, AxisId.brake, brakeOut, centered: false);
  }

  void _writeAxis(Vjoy vjoy, int id, AxisId axis, double out,
      {required bool centered}) {
    final usage = _usage[axis];
    final range = _range[axis];
    if (usage == null || range == null) return;
    final (min, max) = range;
    final span = (max - min).toDouble();
    final v = centered
        ? (min + span * (out + 1) / 2).round()
        : (min + span * out.clamp(0.0, 1.0)).round();
    vjoy.setAxis(v, id, usage);
  }

  /// UI notifies coalesced to ~30 Hz so 100 Hz ticks don't rebuild widgets.
  void _notifyThrottled({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (force || now - _lastNotifyMs >= 33) {
      _lastNotifyMs = now;
      notifyListeners();
    }
  }
}
