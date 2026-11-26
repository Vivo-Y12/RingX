Ringx 0.2.0 — Keyboard + Phone Racing Controller (Portable Edition)
====================================================================

Turns your keyboard — or your PHONE over Wi-Fi — into a smooth analog game
controller (steering ramps, S-curve response, anti-deadzone, throttle/brake
pedals, 32 buttons) and feeds it to a vJoy virtual joystick. Free, offline,
no account, no subscription. Original clean-room implementation — no code or
assets from any other product. Works fine on old laptops (dual-core i3, no
GPU needed), and the phone controller works in any phone browser (Android /
iPhone — no app install).

WHAT'S IN THIS FOLDER
---------------------
  ringx.pyw        double-click me to start Ringx (no console window)
  ringx.bat        same, use this if .pyw doesn't open anything
  ringx_app\       the application (pure Python, standard library only)
  bin\             vJoyInterface.dll (official vJoy SDK component, x64)
  drivers\         vJoySetup.exe — the vJoy driver, if you don't have it
  tests\           self-check suite (python tests\test_ringx.py)
  README.txt       this file

ONE-TIME SETUP (about 5 minutes, ~350 MB disk)
----------------------------------------------
1) Python 3.11 or newer, 64-bit ("x64"), from https://www.python.org/downloads/
   - IMPORTANT: tick "Add python.exe to PATH" during install.
   - The 64-bit version is required (bin\vJoyInterface.dll is 64-bit).
   - "Install tkinter" is on by default — leave it checked.

2) vJoy driver — you can SKIP this if RojX or vJoy worked on this PC before.
   Otherwise run:   drivers\vJoySetup.exe
   (install → reboot → keep default "Device 1" configuration)

RUN
---
   Double-click  ringx.pyw   (or ringx.bat)
   The dashboard should say: "vJoy device 1 acquired" and "keyboard hook
   active". If it says the driver is missing, run drivers\vJoySetup.exe.

USE — KEYBOARD
--------------
   Defaults: A/D = steering, W = throttle, S = brake, Space = button 1.
   F8 = toggle mapping ON/OFF (works while the game has focus).
   In your game, set the controller to "vJoy Device".
   Tune attack/decay/curve/anti-deadzone live in the Mappings tab.
   Your profile is saved as readable JSON in %APPDATA%\Ringx\profile.json.

USE — PHONE AS THE CONTROLLER (new in 0.2.0)
--------------------------------------------
   1. Connect the phone and this PC to the SAME Wi-Fi network
      (a phone hotspot shared to the PC, or the PC's mobile hotspot,
      or your home router — all fine).
   2. Start Ringx, open the Settings tab → "Phone controller" section.
      It shows an address like   192.168.1.5:9870
   3. Open the phone's browser (Chrome/Safari) and type that address.
      The Ringx controller page loads — no app install, nothing to download.
   4. Drive: drag the wheel (or enable TILT and turn the phone like a
      wheel), hold THROTTLE / BRAKE pads, use buttons 1-4.
      MAP on/off button = same as the F8 hotkey.
   Notes:
   - First time, Windows shows a FIREWALL prompt for Python — tick both
     networks and press "Allow access". Without this the phone can't
     reach the PC.
   - The phone page auto-reconnects if Wi-Fi blips.
   - Keep the phone screen awake (or the page pauses): Settings >
     Developer options > Stay awake while charging, or just tap the
     screen occasionally.
   - Latency on Wi-Fi is ~10-40 ms — fine for racing; keep the phone
     close to the router if it feels laggy.

TUNING TIPS
-----------
   - Steering too twitchy on highways? Raise Steering "Attack" to 500-700 ms.
   - Wheels feel dead at the center? Raise "Anti-deadzone" to 8-12%.
   - Gymkhana/rally? Lower attack to ~150 ms and use the aggressive curve.
   - Phone wheel feels too sensitive? Steer less; the S-curve keeps the
     center calm.

TROUBLESHOOTING
---------------
   - "Python not found" from ringx.bat: Python isn't installed or not on
     PATH — reinstall it and tick the PATH checkbox.
   - Nothing happens at all: look for ringx-error.log in this folder and
     send it back for a quick fix.
   - "vJoy device 1 is busy": another feeder app owns the device — close it,
     or pick a different device number in Settings.
   - Phone can't connect: check both are on the SAME Wi-Fi, re-check the
     firewall prompt (allow Python on private AND public networks), and
     try the other address shown in Settings if several are listed.
   - Using 32-bit Python by mistake: install the 64-bit one.
   - Self-check the engine anytime with:  python tests\test_ringx.py

LICENSES
--------
   Ringx application code: MIT (see LICENSE-RINGX.txt).
   vJoyInterface.dll + vJoySetup.exe: official vJoy SDK components
   (Copyright vjoy.sourceforge.net / shaul eizikovich,
   https://github.com/shauleiz/vJoy) — redistributed unmodified.
