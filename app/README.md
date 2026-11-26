# Ringx

**Keyboard → virtual racing controller for Windows. Free, offline, no account.**

Ringx turns your keyboard into a smooth analog gamepad: steering ramps with
tunable attack/decay, S-curve response, anti-deadzone, throttle and brake
pedals, and up to 32 gamepad buttons — all fed to a [vJoy](https://github.com/shauleiz/vJoy)
virtual joystick your racing games see as real hardware.

> Ringx is an original, clean-room implementation of the "keyboard steering"
> concept (the same category as reWASD or AntiMicroX). It contains no code,
> assets or data from any other product and is not affiliated with any.

## Features

- **Analog steering from keys** — press-and-hold ramps to full lock; release
  eases back to center. Left/right switching ramps through neutral like a
  real wheel.
- **Per-axis tuning** — attack time, decay time, response curve
  (linear / smooth / aggressive) and anti-deadzone floor, per axis.
- **Pedals** — throttle and brake with independent ramping.
- **Buttons** — bind any key to vJoy buttons 1–32 (handbrake, camera, ...).
- **Live dashboard** — rotating wheel gauge, pedal bars, held-key badges,
  vJoy device status.
- **F8 hotkey** (configurable) toggles mapping on/off from inside any game;
  axes neutralize and buttons release when off.
- **Profiles** — stored as readable JSON in `%APPDATA%\Ringx`, saved
  atomically on every change. Defaults: WASD + Space.

## Requirements

| | |
|---|---|
| OS | Windows 10 / 11 (x64) |
| Driver | [vJoy 2.1.9+](https://github.com/jshafer817/vJoy/releases) installed, device 1 configured with X/Y/Z axes |
| Build | Flutter stable 3.33+ with the "Desktop development with C++" VS workload |

vJoy default device 1 (X, Y, Z axes) works out of the box. Ringx picks the
first axis each game expects: steering → X (fallback RX), throttle → Y
(fallback RY/SL0), brake → Z (fallback RZ/SL1), and shows what it resolved
on the dashboard.

## Build & run

```powershell
flutter config --enable-windows-desktop
python -m pip install pillow
python tool\make_icon.py    # generates windows\runner\resources\app_icon.ico
flutter pub get
flutter run -d windows          # dev
flutter build windows --release # ringx.exe under build\windows\x64\runner\Release
iscc ..\installer\RingX.iss    # optional: one-click installer in ..\dist
```

> The app is started from the build output folder next to `data\`, or you can
> zip the whole Release folder and run it anywhere. `vJoyInterface.dll` is
> provided by the installed vJoy driver (system PATH) — no bundling needed.

Unit tests: `flutter test` (pure-logic shaper tests, run on any host).

## Usage

1. Install the vJoy driver and reboot; keep device 1 enabled in **vJoyConf**
   (default axes are fine).
2. Start Ringx — the dashboard shows `vJoy device 1 acquired`.
3. Check bindings under **Mappings** (defaults: `A`/`D` steer, `W` throttle,
   `S` brake, `Space` button 1). Click any binding to rebind it to another key.
4. In your game, set controls to the vJoy controller ("vJoy Device").
5. Press **F8** to toggle mapping (works while the game has focus).

Tuning tips: raise steering attack (350→600 ms) for highway stability, lower
it for gymkhana; set anti-deadzone to just above your game's inner steering
deadzone; aggressive curve gives quicker lock from light taps.

## Architecture

```
keyboard ──WH_KEYBOARD_LL (C++ thread, windows/runner/keyhook.cpp)
        │      exported as ringx_hook_start/stop → Dart FFI
        ▼
Dart MapperEngine (lib/core/engine.dart)
  · key state + bindings (lib/core/profile.dart)
  · axis shaping: ramp → curve → anti-deadzone (lib/core/shaper.dart)
  · tick loop 50–200 Hz
        ▼  dart:ffi
vJoyInterface.dll (AcquireVJD / SetAxis / SetBtn)
        ▼
vJoy virtual joystick → game
```

- **No plugins, no Node sidecar, no network.** The whole native surface is
  one ~100-line C++ hook file plus direct FFI calls to the vJoy SDK.
- The hook skips injected keystrokes (so other tools' synthetic input never
  double-triggers) and forwards events through a `NativeCallable`, which
  only posts to the Dart event loop — never blocks the hook.
- Everything degrades visibly: no vJoy → dashboard note, no hook → badges
  still update from the Dart side.

## Project layout

```
lib/core/   vjoy.dart (FFI), keyhook.dart (FFI), engine.dart,
            shaper.dart, profile.dart, vk_names.dart
lib/ui/     app.dart, home_screen.dart, mapping_screen.dart,
            settings_screen.dart, widgets.dart
test/       shaper_test.dart
windows/    Flutter template (BSD-3) + runner/keyhook.cpp (original)
```

## Roadmap (not built yet)

- Per-binding modifiers (shift+key combos)
- Multiple profiles with a switcher
- POV hat output
- ViGEm (Xbox) backend as an alternative to vJoy

## License

MIT for Ringx code — see [LICENSE](LICENSE). Windows runner files come from
the Flutter template (BSD-3, The Flutter Authors); vJoy is used at runtime
via its public SDK.
