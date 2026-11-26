"""ctypes bridge to vJoyInterface.dll (public vJoy SDK API).

Signatures verified against shauleiz/vJoy inc/vjoyinterface.h. The DLL is
searched in: this app's bin/ folder, the standard vJoy install, then PATH.
All functions are __cdecl, so CDLL is used. Windows-only; on other platforms
open() returns None and the app runs in "no device" mode.
"""

import ctypes
import os
import sys

# vJoy axis HID usages (vJoy SDK public.h).
USAGE_X, USAGE_Y, USAGE_Z = 0x30, 0x31, 0x32
USAGE_RX, USAGE_RY, USAGE_RZ = 0x33, 0x34, 0x35
USAGE_SL0, USAGE_SL1 = 0x36, 0x37

# enum VjdStat.
STAT_OWN, STAT_FREE, STAT_BUSY, STAT_MISS, STAT_UNKN = 0, 1, 2, 3, 4
STAT_NAMES = {0: "owned by Ringx", 1: "free", 2: "busy (another app)",
              3: "missing", 4: "unknown"}

_AXIS_NAMES = {0x30: "X", 0x31: "Y", 0x32: "Z", 0x33: "RX", 0x34: "RY",
               0x35: "RZ", 0x36: "SL0", 0x37: "SL1"}


def axis_name(usage):
    return _AXIS_NAMES.get(usage, f"0x{usage:02X}")


def _dll_candidates():
    here = os.path.dirname(os.path.abspath(__file__))
    return [
        os.path.join(here, "..", "bin", "vJoyInterface.dll"),
        r"C:\Program Files\vJoy\x64\vJoyInterface.dll",
        "vJoyInterface.dll",
    ]


class Vjoy:
    """A live handle to vJoyInterface.dll."""

    def __init__(self, lib):
        self._lib = lib
        self.enabled = bool(lib.vJoyEnabled())
        if self.enabled:
            self.version = int(lib.GetvJoyVersion())

    @classmethod
    def open(cls):
        """Returns a Vjoy handle, or None when no DLL/driver is present."""
        if sys.platform != "win32":
            return None
        for path in _dll_candidates():
            try:
                lib = ctypes.CDLL(path)
            except OSError:
                continue
            try:
                lib.vJoyEnabled
                return cls(lib)
            except AttributeError:
                continue  # a file with the name but not the vJoy interface
        return None

    def _fn(self, name, restype, argtypes):
        fn = getattr(self._lib, name)
        fn.restype = restype
        fn.argtypes = argtypes
        return fn

    def status(self, device_id):
        return int(self._fn("GetVJDStatus", ctypes.c_int,
                            [ctypes.c_uint])(device_id))

    def status_text(self, device_id):
        return STAT_NAMES.get(self.status(device_id), "unknown")

    def device_exists(self, device_id):
        return bool(self._fn("isVJDExists", ctypes.c_int,
                             [ctypes.c_uint])(device_id))

    def acquire(self, device_id):
        return bool(self._fn("AcquireVJD", ctypes.c_int,
                             [ctypes.c_uint])(device_id))

    def relinquish(self, device_id):
        self._fn("RelinquishVJD", None, [ctypes.c_uint])(device_id)

    def reset(self, device_id):
        return bool(self._fn("ResetVJD", ctypes.c_int,
                             [ctypes.c_uint])(device_id))

    def axis_exists(self, device_id, usage):
        return bool(self._fn("GetVJDAxisExist", ctypes.c_int,
                             [ctypes.c_uint, ctypes.c_uint])(device_id,
                                                             usage))

    def axis_range(self, device_id, usage):
        """Logical axis range as (min, max); (0x1, 0x8000) if query fails."""
        out = ctypes.c_long()
        fn_min = self._fn("GetVJDAxisMin", ctypes.c_int,
                          [ctypes.c_uint, ctypes.c_uint,
                           ctypes.POINTER(ctypes.c_long)])
        fn_max = self._fn("GetVJDAxisMax", ctypes.c_int,
                          [ctypes.c_uint, ctypes.c_uint,
                           ctypes.POINTER(ctypes.c_long)])
        if fn_min(device_id, usage, ctypes.byref(out)) and 0 <= out.value:
            lo = out.value
            if fn_max(device_id, usage, ctypes.byref(out)) and out.value > lo:
                return lo, out.value
        return 0x1, 0x8000

    def set_axis(self, value, device_id, usage):
        """Writes an axis value clamped to the legal range. Returns ok."""
        lo, hi = self.axis_range(device_id, usage)
        value = lo if value < lo else hi if value > hi else value
        fn = self._fn("SetAxis", ctypes.c_int,
                      [ctypes.c_long, ctypes.c_uint, ctypes.c_uint])
        return bool(fn(value, device_id, usage))

    def set_btn(self, pressed, device_id, button):
        fn = self._fn("SetBtn", ctypes.c_int,
                      [ctypes.c_int, ctypes.c_uint, ctypes.c_ubyte])
        return bool(fn(1 if pressed else 0, device_id, button))
