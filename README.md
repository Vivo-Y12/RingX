# RingX

**Keyboard + phone → virtual racing controller for Windows + Android. Free, offline, no account.**

RingX turns your keyboard — or your **phone over Wi-Fi** — into a smooth analog
gamepad: steering ramps with tunable attack/decay, S-curve response, anti-deadzone,
throttle and brake pedals, and up to 128 gamepad buttons. Everything is fed to a
[vJoy](https://github.com/jshafer817/vJoy) virtual joystick, so your racing games
see real analog hardware.

> RingX is an original, clean-room implementation of the "keyboard steering"
> concept (same category as reWASD or AntiMicroX). It contains no code, assets
> or data from any other product and is not affiliated with any.

RingX ships as **two complete editions + a native phone app** — same engine
behavior across all of them:

| Piece | Folder | Runtime needs | Best for |
|---|---|---|---|
| **Receiver app** (Flutter) | `app/` (Windows build) | Nothing to install (single `ringx.exe`) | Everyday use — QR pairing, templates, calibration UI |
| **Controller APK** (Flutter) | `app/` (Android build) | Android 7+ phone | The native phone controller: QR scan, drag-drop layouts, tilt steering |
| **Portable** (Python) | `portable/` | Python 3.11+ (stdlib only, no pip) | Old laptops, easy tweaking |

The phone app pairs with the receiver by **scanning the QR code** on the PC
dashboard (or "Find PC" UDP discovery on the LAN, or typing the address), then
drives it over WebSocket at ~20 Hz. A plain **browser controller page** is also
served by the receiver at the same address — so any phone works, with or
without the APK.

## Download the ready-made builds (no build tools needed)

Every push to `main` — or a manual run — makes GitHub Actions build everything
in the cloud. Get the results:

1. Open this repo on GitHub → **Actions** tab → click the latest **Build RingX** run.
2. Scroll to **Artifacts** at the bottom of the run page.
3. Download:
   - `RingX-setup-windows` — one-click installer (`RingX-Setup-0.2.0.exe`),
     with an optional bundled vJoy driver install
   - `RingX-app-windows` — the built Flutter receiver (`ringx.exe` + runtime files)
   - `RingX-controller-android` — the phone controller APK (install it on any
     Android 7+ phone; signed with a CI-generated key, so sideload "unknown
     sources" once)
   - `RingX-portable` — the portable edition, ready to run, with the official
     vJoy driver and SDK DLL already bundled

Artifacts expire after 90 days — just re-run the workflow to refresh them.

## Pairing a phone (60 seconds)

1. Start RingX on the PC (receiver or portable edition).
2. **Dashboard → Phone Controller** shows a big QR with `ws://<pc-ip>:<port>`.
3. On the phone: install the APK → **Scan the PC QR code** → connected.
   - No APK? Open the same address in the phone browser — the touch
     controller page loads itself.
4. Drive: touch wheel + pedals, or tilt steering; the circular button toggles
   mapping, pages switch layouts, the menu edits everything live.

## One-time setup (PC side)

| | |
|---|---|
| OS | Windows 10 / 11 (x64) |
| Driver | [vJoy 2.1.9+](https://github.com/jshafer817/vJoy/releases) — bundled inside the `RingX-setup-windows` and `RingX-portable` artifacts; otherwise download and run it once, then reboot |
| vJoy device | Device 1 with X/Y/Z axes (the default) |

RingX picks the axis each game expects: steering → X (fallback RX), throttle →
Y (fallback RY/SL0), brake → Z (fallback RZ/SL1), and shows what it resolved
on the dashboard.

> The 11.5 MB driver installer and the vJoy SDK DLL are **not stored in git**.
> CI downloads the official vJoy 2.1.9.1 release (pinned URL, SHA-256-verified)
> and bundles it into the artifacts. The portable edition also finds the DLL
> automatically in the installed vJoy directory, so a repo clone works too.

## Receiver app — build & run

```powershell
cd app
python -m pip install pillow
python tool\make_icon.py          # generates windows\runner\resources\app_icon.ico
flutter pub get
flutter run -d windows           # dev
flutter build windows --release  # ringx.exe under build\windows\x64\runner\Release
iscc ..\installer\RingX.iss      # optional: RingX-Setup-0.2.0.exe in ..\dist
```

Requires Flutter stable with the "Desktop development with C++" Visual Studio
workload, plus [Inno Setup 6](https://jrsoftware.org/isinfo.php) for the
installer step. Or skip all of that and download the CI artifact above.

## Controller APK — build

```bash
cd app
python tool/make_icon.py --android        # generates the mipmap launcher icons
flutter build apk --release               # app-release.apk
```

Same codebase as the receiver: one Flutter project, two faces (the phone UI
boots automatically on Android). Without an `android/key.properties` file the
release APK is debug-signed — fine for sideloading; CI stages a cached keystore
so successive CI builds keep one stable signature.

## Portable edition — run

1. Install Python 3.11+ 64-bit ("Add python.exe to PATH" ticked).
2. Install the vJoy driver if you do not have it yet (reboot once).
3. Double-click `ringx.pyw` (or `ringx.bat`).

The dashboard should say **"vJoy device 1 acquired"** and **"keyboard hook
active"**. To connect your phone: start the phone server from the dashboard,
scan the QR code, drive.

Self-check: `python tests\test_ringx.py` — 80 checks, runs on any OS with
plain Python 3. The app's Dart tests run with `cd app && flutter test`.

## Features

- **Analog steering from keys** — press-and-hold ramps to full lock; release
  eases back to center; switching sides ramps through neutral like a real wheel.
- **Native phone controller (APK)** — QR pairing, UDP "Find PC", rotating touch
  wheel with auto-center, analog pedals, PRND gear selector with momentary
  150 ms presses, paddle shifters, thumbsticks, round buttons, tilt steering
  with re-center/invert.
- **Drag-and-drop templates** — build layouts on the phone (pages, positions,
  sizes, labels, button numbers), save/rename/duplicate/delete, send them to
  the PC; three factory layouts included (Racing / Gamepad / Lite).
- **Phone works with every edition** — same WebSocket protocol
  (`state` / `toggle` / `stat` / `hello` / template sync), same 0.5 s
  staleness rule; the browser page keeps working when the APK is not around.
- **Per-axis tuning** — attack time, decay time (auto-center), response curve
  (linear / smooth / aggressive), anti-deadzone floor, steering limit and
  neutral calibration offset.
- **Pedals** — throttle and brake with independent ramping.
- **Buttons** — bind any key to vJoy buttons 1–128 (handbrake, camera, ...);
  phone elements share the same button space.
- **F8 hotkey** (configurable) toggles mapping on/off from inside any game —
  from the keyboard or the phone.
- **Profiles** — readable JSON, saved atomically on every change.
- **Live dashboard** — rotating wheel gauge, pedal bars, held-key badges,
  vJoy + hook + phone status, QR panel.

## Repository layout

```
RingX/
├── app/                 Flutter app — Windows receiver + Android controller
│   ├── lib/core/        engine, shaper, profile, vJoy FFI, key hook,
│   │                    phone link (WS server), protocol, templates, QR, discovery
│   ├── lib/ui/          receiver screens (dashboard, templates, mappings, settings)
│   ├── lib/phone/       controller screens (connect, drive, layout editor)
│   ├── android/         Android platform (manifest, gradle; icons generated in CI)
│   ├── windows/         Windows runner (keyboard hook in C++)
│   ├── tool/            make_icon.py — .ico + Android launcher icons
│   └── test/            unit tests (protocol, templates, QR, shaper)
├── portable/            Python portable edition (stdlib only)
│   ├── ringx_app/       engine, shaper, hook, ws server, phone.html
│   └── tests/           80-check self-test suite
├── installer/           RingX.iss — Inno Setup installer script
└── .github/workflows/   CI: tests + Windows exe + installer + Android APK + portable zip
```

## License

MIT — see [LICENSE](LICENSE), which also lists the third-party components
(Flutter Windows template, vJoy SDK, `ffi`, `qr_flutter`, `mobile_scanner`,
`sensors_plus`, `shared_preferences`).
