"""Profile model + JSON store under %APPDATA%\\Ringx.

Everything loaded from disk is validated and clamped — the file may be
hand-edited or corrupt. Pure logic, no Windows dependencies.
"""

import json
import os
import tempfile

from .shaper import AxisConfig

ACTS = ("steer_left", "steer_right", "throttle", "brake", "button")
AXES = ("steer", "throttle", "brake")
ACT_LABELS = {
    "steer_left": "Steer Left", "steer_right": "Steer Right",
    "throttle": "Throttle", "brake": "Brake", "button": "Gamepad Button",
}

# Default tuning per axis: steer slower for stability, brake fastest.
DEFAULT_AXIS = {
    "steer": dict(attack_ms=350, decay_ms=180),
    "throttle": dict(attack_ms=250, decay_ms=120),
    "brake": dict(attack_ms=150, decay_ms=90),
}


def _clamp_int(v, lo, hi, fallback):
    try:
        i = int(v)
    except (TypeError, ValueError):
        return fallback
    return lo if i < lo else hi if i > hi else i


class Binding:
    __slots__ = ("vk", "act", "button")

    def __init__(self, vk, act, button=1):
        self.vk = _clamp_int(vk, 0x01, 0xFE, 0)
        self.act = act if act in ACTS else "button"
        self.button = _clamp_int(button, 1, 32, 1)

    def __eq__(self, other):
        return (isinstance(other, Binding)
                and (self.vk, self.act, self.button)
                == (other.vk, other.act, other.button))

    def to_dict(self):
        return {"vk": self.vk, "act": self.act, "button": self.button}

    @classmethod
    def from_dict(cls, d):
        d = d if isinstance(d, dict) else {}
        return cls(d.get("vk"), d.get("act"), d.get("button"))


class Profile:
    __slots__ = ("name", "device_id", "tick_ms", "toggle_vk", "axes",
                 "bindings", "phone_enabled", "phone_port")

    def __init__(self, name="Default Racing", device_id=1, tick_ms=20,
                 toggle_vk=0x77, axes=None, bindings=None,
                 phone_enabled=True, phone_port=9870):
        self.name = (str(name) or "Default Racing")[:40]
        self.device_id = _clamp_int(device_id, 1, 16, 1)
        self.tick_ms = _clamp_int(tick_ms, 10, 50, 20)
        self.toggle_vk = _clamp_int(toggle_vk, 0x01, 0xFE, 0x77)  # F8
        self.axes = {a: (axes or {}).get(a) or AxisConfig(**DEFAULT_AXIS[a])
                     for a in AXES}
        self.bindings = list(bindings or [])
        self.phone_enabled = bool(phone_enabled)
        self.phone_port = _clamp_int(phone_port, 1024, 65535, 9870)

    def to_dict(self):
        return {
            "name": self.name, "device_id": self.device_id,
            "tick_ms": self.tick_ms, "toggle_vk": self.toggle_vk,
            "axes": {a: self.axes[a].to_dict() for a in AXES},
            "bindings": [b.to_dict() for b in self.bindings],
            "phone_enabled": self.phone_enabled,
            "phone_port": self.phone_port,
        }

    @classmethod
    def from_dict(cls, d):
        d = d if isinstance(d, dict) else {}
        raw_axes = d.get("axes") if isinstance(d.get("axes"), dict) else {}
        raw_bindings = d.get("bindings")
        return cls(
            name=d.get("name"),
            device_id=d.get("device_id"),
            tick_ms=d.get("tick_ms"),
            toggle_vk=d.get("toggle_vk"),
            axes={a: AxisConfig.from_dict(raw_axes.get(a)) for a in AXES},
            bindings=[Binding.from_dict(b) for b in raw_bindings]
            if isinstance(raw_bindings, list) else [],
            phone_enabled=d.get("phone_enabled", True),
            phone_port=d.get("phone_port", 9870),
        )

    @classmethod
    def defaults(cls):
        """Sensible racing defaults: WASD + Space as button 1."""
        return cls(bindings=[
            Binding(0x41, "steer_left"),    # A
            Binding(0x44, "steer_right"),   # D
            Binding(0x57, "throttle"),      # W
            Binding(0x53, "brake"),         # S
            Binding(0x20, "button", 1),     # Space
        ])


class ProfileStore:
    """Atomic JSON profile store: %APPDATA%\\Ringx\\profile.json."""

    def __init__(self, path=None):
        if path is None:
            base = (os.environ.get("APPDATA")
                    or os.environ.get("HOME")
                    or tempfile.gettempdir())
            self.dir = os.path.join(base, "Ringx")
            try:
                os.makedirs(self.dir, exist_ok=True)
            except OSError:
                pass  # read-only home: load still works, save reports failure
            path = os.path.join(self.dir, "profile.json")
        self.path = path

    def load(self):
        """Returns (profile, error_message_or_None)."""
        try:
            with open(self.path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except FileNotFoundError:
            return Profile.defaults(), None
        except (json.JSONDecodeError, OSError) as e:
            return Profile.defaults(), f"profile.json unreadable: {e}"
        if not isinstance(data, dict):
            return Profile.defaults(), "profile.json is not an object."
        return Profile.from_dict(data), None

    def save(self, profile):
        """Atomic write (temp file + rename). Returns (ok, error_or_None)."""
        tmp = self.path + ".tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(profile.to_dict(), f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, self.path)
            return True, None
        except OSError as e:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            return False, f"could not save profile: {e}"


# --- Virtual-key names for the UI (common keys; rest show VK_0x..) ---------

_VK_NAMES = {
    0x08: "Backspace", 0x09: "Tab", 0x0D: "Enter", 0x10: "Shift",
    0x11: "Ctrl", 0x12: "Alt", 0x13: "Pause", 0x14: "CapsLock",
    0x1B: "Esc", 0x20: "Space",
    0x21: "PgUp", 0x22: "PgDn", 0x23: "End", 0x24: "Home",
    0x25: "Left", 0x26: "Up", 0x27: "Right", 0x28: "Down",
    0x2D: "Insert", 0x2E: "Delete",
    0x60: "Num0", 0x61: "Num1", 0x62: "Num2", 0x63: "Num3", 0x64: "Num4",
    0x65: "Num5", 0x66: "Num6", 0x67: "Num7", 0x68: "Num8", 0x69: "Num9",
    0x90: "NumLock", 0x91: "ScrollLock",
    0xA0: "LShift", 0xA1: "RShift", 0xA2: "LCtrl", 0xA3: "RCtrl",
    0xA4: "LAlt", 0xA5: "RAlt",
    0xBA: ";", 0xBB: "=", 0xBC: ",", 0xBD: "-", 0xBE: ".", 0xBF: "/",
    0xC0: "`", 0xDB: "[", 0xDC: "\\", 0xDD: "]", 0xDE: "'",
}
for _c in "0123456789":
    _VK_NAMES[ord(_c)] = _c
for _c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
    _VK_NAMES[ord(_c)] = _c


def vk_name(vk):
    if vk in _VK_NAMES:
        return _VK_NAMES[vk]
    if 0x70 <= vk <= 0x87:
        return f"F{vk - 0x6F}"
    return f"VK_0x{vk:02X}"
