# RingX

**Keyboard + phone → virtual racing controller for Windows. Free, offline, no account.**

RingX turns your keyboard — or your **phone over Wi-Fi** — into a smooth analog
gamepad: steering ramps with tunable attack/decay, S-curve response, anti-deadzone,
throttle and brake pedals, and up to 32 gamepad buttons. Everything is fed to a
[vJoy](https://github.com/jshafer817/vJoy) virtual joystick, so your racing games
see real analog hardware.

> RingX is an original, clean-room implementation of the "keyboard steering"
> concept (same category as reWASD or AntiMicroX). It contains no code, assets
> or data from any other product and is not affiliated with any.

RingX ships as **two complete editions** — same engine behavior, two runtimes:

| Edition | Folder | Runtime needs | Best for |
|---|---|---|---|
| **App** (Flutter) | `app/` | Nothing to install (single `ringx.exe`) | Everyday use — cleanest UI |
| **Portable** (Python) | `portable/` | Python 3.11+ (stdlib only, no pip) | Old laptops, easy tweaking, phone controller |

The **phone controller** (touch wheel + pedals, or tilt steering, in any phone
browser — Android/iPhone, no app install) is served by the portable edition
over your local Wi-Fi.

## Download the ready-made builds (no build tools needed)

Every push to `main` — or a manual run — makes GitHub Actions build everything
in the cloud. Get the results:

1. Open this repo on GitHub → **Actions** tab → click the latest **Build RingX** run.
2. Scroll to **Artifacts** at the bottom of the run page.
3. Download:
   - `RingX-setup-windows` — one-click installer (`RingX-Setup-0.1.0.exe`),
     with an optional bundled vJoy driver install
   - `RingX-app-windows` — the built Flutter app (`ringx.exe` + runtime files)
   - `RingX-portable` — the portable edition, ready to run, with the official
     vJoy driver and SDK DLL already bundled

Artifacts expire after 90 days — just re-run the workflow to refresh them.

## One-time setup (either edition)

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

## App edition — build & run

```powershell
cd app
python -m pip install pillow
python tool\make_icon.py          # generates windows\runner\resources\app_icon.ico
flutter pub get
flutter run -d windows           # dev
flutter build windows --release  # ringx.exe under build\windows\x64\runner\Release
iscc ..\installer\RingX.iss      # optional: RingX-Setup-0.1.0.exe in ..\dist
```

Requires Flutter stable with the "Desktop development with C++" Visual Studio
workload, plus [Inno Setup 6](https://jrsoftware.org/isinfo.php) for the
installer step. Or skip all of that and download the CI artifact above.

## Portable edition — run

1. Install Python 3.11+ 64-bit ("Add python.exe to PATH" ticked).
2. Install the vJoy driver if you do not have it yet (reboot once).
3. Double-click `ringx.pyw` (or `ringx.bat`).

The dashboard should say **"vJoy device 1 acquired"** and **"keyboard hook
active"**. To connect your phone: start the phone server from the dashboard,
scan the QR code, drive.

Self-check: `python tests\test_ringx.py` — 80 checks, runs on any OS with
plain Python 3.

## Features

- **Analog steering from keys** — press-and-hold ramps to full lock; release
  eases back to center; switching sides ramps through neutral like a real wheel.
- **Phone controller** — touch wheel + pedal bars, or tilt steering, over
  Wi-Fi (WebSocket, ~1 KB/s). Works in any phone browser.
- **Per-axis tuning** — attack time, decay time, response curve
  (linear / smooth / aggressive) and anti-deadzone floor.
- **Pedals** — throttle and brake with independent ramping.
- **Buttons** — bind any key to vJoy buttons 1–32 (handbrake, camera, ...).
- **F8 hotkey** (configurable) toggles mapping on/off from inside any game.
- **Profiles** — readable JSON, saved atomically on every change.
- **Live dashboard** — rotating wheel gauge, pedal bars, held-key badges,
  vJoy status.

## Repository layout

```
RingX/
├── app/                 Flutter Windows app (source)
│   ├── lib/             Dart code: engine, shaper, vJoy FFI, UI
│   ├── windows/         Windows runner (keyboard hook in C++)
│   ├── tool/            make_icon.py — generates the app icon
│   └── test/            unit tests
├── portable/            Python portable edition (stdlib only)
│   ├── ringx_app/       engine, shaper, hook, ws server, phone.html
│   └── tests/           80-check self-test suite
├── installer/           RingX.iss — Inno Setup installer script
└── .github/workflows/   CI: tests + Windows exe + installer + portable zip
```

## License

MIT — see [LICENSE](LICENSE), which also lists the third-party components
(Flutter Windows template, vJoy SDK, `ffi` package).
