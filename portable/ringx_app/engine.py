"""Ringx mapping engine: keyboard + phone state -> shaped analog axes /
buttons -> vJoy device. Owns live state; the UI drives the loop and reads
the getters. UI-free so it can be tested headless with a fake Vjoy.
"""

import time

from .keyhook import KeyHook
from .profile import AXES, Profile, ProfileStore
from .shaper import AxisShaper
from .vjoy import (STAT_BUSY, STAT_FREE, STAT_MISS, STAT_OWN, USAGE_RX,
                   USAGE_RY, USAGE_RZ, USAGE_SL0, USAGE_SL1, USAGE_X, USAGE_Y,
                   USAGE_Z, Vjoy, axis_name)

# vJoy usage candidates per Ringx axis; the first one the device actually has
# wins. Defaults match a standard 8-axis vJoy device.
AXIS_CANDIDATES = {
    "steer": [USAGE_X, USAGE_RX],
    "throttle": [USAGE_Y, USAGE_RY, USAGE_SL0],
    "brake": [USAGE_Z, USAGE_RZ, USAGE_SL1],
}

# A phone is considered still connected for this long without packets.
PHONE_STALE_S = 0.5


def _clamp01(v):
    try:
        f = float(v)
    except (TypeError, ValueError):
        return 0.0
    return 0.0 if f < 0 else 1.0 if f > 1 else f


class Engine:
    def __init__(self, store: ProfileStore, profile: Profile,
                 vjoy=None, hook=None):
        self.store = store
        self.profile = profile
        self.vjoy = vjoy
        self.hook = hook or KeyHook()
        self.enabled = False
        self.acquired = False
        self.hook_running = False
        self.note = ""
        self.usages = {}   # axis -> vJoy usage
        self.ranges = {}   # axis -> (min, max)
        self.held = set()
        self.pressed_buttons = set()
        self.recent_keys = []
        self._shapers = {a: AxisShaper() for a in AXES}
        # Phone controller state (fed by the WS server via on_phone_event).
        self.phone_link = None
        self.phone_connected = False
        self._phone = {"fresh_until": 0.0, "steer": 0.0, "throttle": 0.0,
                       "brake": 0.0}
        self._phone_buttons = set()

    # ---- lifecycle ---------------------------------------------------------

    def start(self):
        """Boot: hook on, vJoy open + acquire, phone server if enabled."""
        self.hook_running = self.hook.start()
        self.vjoy = self.vjoy if self.vjoy is not None else Vjoy.open()
        self._apply_device()
        if self.phone_link is not None and self.profile.phone_enabled:
            self.phone_link.start(self.profile.phone_port)

    def stop(self):
        self.hook.stop()
        if self.phone_link is not None:
            self.phone_link.stop()
        self._release_device()

    def apply_profile(self, profile):
        """Swap profile (re-acquire device if needed), persist, return (ok, err)."""
        old = self.profile
        if profile.device_id != old.device_id:
            self._release_device(old.device_id)  # release the OLD id first
        self.profile = profile
        if profile.device_id != old.device_id:
            self._apply_device()
        self._reset_outputs()
        return self.store.save(profile)

    def _apply_device(self):
        self._release_device()
        self.usages.clear()
        self.ranges.clear()
        vjoy, dev = self.vjoy, self.profile.device_id
        if vjoy is None:
            self.note = ("vJoy driver not found - run drivers\\vJoySetup.exe "
                         "once, then restart Ringx.")
            return
        if not vjoy.enabled:
            self.note = "vJoy driver is not enabled."
            return
        status = vjoy.status(dev)
        if status in (STAT_OWN, STAT_FREE):
            if not vjoy.acquire(dev):
                self.note = f"vJoy device {dev} could not be acquired."
                return
            self.acquired = True
            vjoy.reset(dev)
            self.note = f"vJoy device {dev} acquired."
            for axis, candidates in AXIS_CANDIDATES.items():
                for usage in candidates:
                    if vjoy.axis_exists(dev, usage):
                        self.usages[axis] = usage
                        self.ranges[axis] = vjoy.axis_range(dev, usage)
                        break
        elif status == STAT_BUSY:
            self.note = f"vJoy device {dev} is owned by another app."
        elif status == STAT_MISS:
            self.note = (f"vJoy device {dev} is missing "
                         f"(enable it in vJoyConf).")
        else:
            self.note = f"vJoy device {dev} status unknown."

    def _release_device(self, device_id=None):
        if self.acquired and self.vjoy is not None:
            self._reset_outputs()
            self.vjoy.relinquish(
                self.profile.device_id if device_id is None else device_id)
            self.acquired = False

    # ---- input -------------------------------------------------------------

    def on_key(self, vk, down):
        if vk == self.profile.toggle_vk:
            # Only the down-transition toggles; auto-repeat must not spam it.
            if down and vk not in self.held:
                self.set_enabled(not self.enabled)
            self.held.add(vk) if down else self.held.discard(vk)
            return
        if down and vk not in self.held:
            self.recent_keys.insert(0, vk)
            del self.recent_keys[12:]
        self.held.add(vk) if down else self.held.discard(vk)
        if self.enabled and self.acquired:
            for b in self.profile.bindings:
                if b.vk == vk and b.act == "button":
                    self._set_button(b.button, down)

    def set_enabled(self, value):
        if self.enabled == value:
            return
        self.enabled = value
        if not value:
            for btn in list(self.pressed_buttons):
                self._set_button(btn, False)
        else:
            # Buttons already held on the phone (if it is live) come through.
            if self._phone_fresh():
                for btn in sorted(self._phone_buttons):
                    self._set_button(btn, True)
        self._push_stat()

    # ---- phone controller --------------------------------------------------

    def on_phone_event(self, kind, payload):
        """Single entry point for phone-link events (drained by the UI loop)."""
        if kind == "state":
            self._apply_phone_state(payload if isinstance(payload, dict)
                                    else {})
        elif kind == "toggle":
            self.set_enabled(not self.enabled)
        elif kind == "connect":
            self.phone_connected = True
            self._push_stat()
        elif kind == "disconnect":
            self.phone_connected = False
            self._release_phone_buttons()

    def _apply_phone_state(self, msg):
        try:
            steer = float(msg.get("s", 0))
        except (TypeError, ValueError):
            steer = 0.0
        steer = max(-1.0, min(1.0, steer))
        self._phone["steer"] = steer
        self._phone["throttle"] = _clamp01(msg.get("th"))
        self._phone["brake"] = _clamp01(msg.get("br"))
        self._phone["fresh_until"] = time.monotonic() + PHONE_STALE_S
        buttons = set()
        if isinstance(msg.get("bt"), list):
            for b in msg["bt"]:
                try:
                    buttons.add(max(1, min(32, int(b))))
                except (TypeError, ValueError):
                    continue
        if self.enabled and self.acquired:
            for btn in buttons - self._phone_buttons:
                self._set_button(btn, True)
            for btn in self._phone_buttons - buttons:
                self._set_button(btn, False)
        self._phone_buttons = buttons

    def _release_phone_buttons(self):
        for btn in list(self._phone_buttons):
            self._set_button(btn, False)
        self._phone_buttons = set()

    def _phone_fresh(self):
        return time.monotonic() < self._phone["fresh_until"]

    def set_phone_enabled(self, value):
        """Start/stop the phone server live; returns (ok, error_or_None)."""
        self.profile.phone_enabled = bool(value)
        ok, err = self.store.save(self.profile)
        if self.phone_link is not None:
            if value:
                ok2, err2 = self.phone_link.start(self.profile.phone_port)
                if not ok2:
                    return False, err2
            else:
                self.phone_link.stop()
        return ok, err

    def _push_stat(self):
        if self.phone_link is not None:
            self.phone_link.send_stat(self.enabled)

    def _set_button(self, button, pressed):
        if self.vjoy is None or not self.acquired:
            return
        self.vjoy.set_btn(pressed, self.profile.device_id, button)
        self.pressed_buttons.add(button) if pressed \
            else self.pressed_buttons.discard(button)

    def center_reset(self):
        self._reset_outputs()
        if self.vjoy is not None and self.acquired:
            self.vjoy.reset(self.profile.device_id)

    def _reset_outputs(self):
        for btn in list(self.pressed_buttons):
            self._set_button(btn, False)
        for s in self._shapers.values():
            s.reset()
        self._write_axes()

    # ---- tick --------------------------------------------------------------

    def tick(self, dt_ms):
        phone_live = self.enabled and self._phone_fresh()
        if phone_live:
            # Phone steering is already analog: apply the curve directly.
            self._shapers["steer"].value = AxisShaper.shape(
                self._phone["steer"], self.profile.axes["steer"])
            self._shapers["throttle"].value = self._phone["throttle"]
            self._shapers["brake"].value = self._phone["brake"]
        elif self.enabled:
            self._shapers["steer"].step(dt_ms, self._steer_target(),
                                        self.profile.axes["steer"])
            self._shapers["throttle"].step(dt_ms, self._act_target("throttle"),
                                           self.profile.axes["throttle"])
            self._shapers["brake"].step(dt_ms, self._act_target("brake"),
                                        self.profile.axes["brake"])
        else:
            for axis in AXES:
                self._shapers[axis].step(dt_ms, 0, self.profile.axes[axis])
        if not self._phone_fresh() and self._phone_buttons:
            self._release_phone_buttons()
        self._write_axes()

    def _steer_target(self):
        t = 0
        for b in self.profile.bindings:
            if b.vk in self.held:
                if b.act == "steer_left":
                    t -= 1
                elif b.act == "steer_right":
                    t += 1
        return max(-1, min(1, t))

    def _act_target(self, act):
        for b in self.profile.bindings:
            if b.act == act and b.vk in self.held:
                return 1
        return 0

    # ---- output ------------------------------------------------------------

    @property
    def steer_out(self):
        return AxisShaper.shape(self._shapers["steer"].value,
                                 self.profile.axes["steer"])

    @property
    def throttle_out(self):
        return AxisShaper.shape(self._shapers["throttle"].value,
                                self.profile.axes["throttle"])

    @property
    def brake_out(self):
        return AxisShaper.shape(self._shapers["brake"].value,
                                self.profile.axes["brake"])

    def _write_axes(self):
        vjoy, dev = self.vjoy, self.profile.device_id
        if vjoy is None or not self.acquired:
            return
        self._write_axis(vjoy, dev, "steer", self.steer_out, centered=True)
        self._write_axis(vjoy, dev, "throttle", self.throttle_out,
                         centered=False)
        self._write_axis(vjoy, dev, "brake", self.brake_out, centered=False)

    def _write_axis(self, vjoy, dev, axis, out, centered):
        usage = self.usages.get(axis)
        rng = self.ranges.get(axis)
        if usage is None or rng is None:
            return
        lo, hi = rng
        span = hi - lo
        if centered:
            v = round(lo + span * (out + 1) / 2)
        else:
            v = round(lo + span * max(0.0, min(1.0, out)))
        vjoy.set_axis(v, dev, usage)

    def axis_summary(self):
        """For the dashboard status line, e.g. 'X/Y/Z'."""
        return "/".join(axis_name(self.usages[a]) if a in self.usages else "-"
                        for a in AXES)
