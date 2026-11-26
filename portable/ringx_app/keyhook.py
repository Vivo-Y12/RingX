"""System-wide low-level keyboard hook (WH_KEYBOARD_LL) in pure ctypes.

A dedicated thread installs the hook and pumps messages; the callback only
pushes (vk, down) tuples into a queue (fast, so the hook never times out).
Injected keystrokes are skipped so other tools' synthetic input never
double-triggers. Windows-only; start() returns False elsewhere.
"""

import ctypes
import ctypes.wintypes as wintypes
import queue
import sys
import threading

WH_KEYBOARD_LL = 13
WM_KEYDOWN, WM_SYSKEYDOWN, WM_QUIT = 0x0100, 0x0104, 0x0012
HC_ACTION = 0
LLKHF_INJECTED = 0x10


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [("vkCode", wintypes.DWORD),
                ("scanCode", wintypes.DWORD),
                ("flags", wintypes.DWORD),
                ("time", wintypes.DWORD),
                ("dwExtraInfo", ctypes.c_void_p)]


class KeyHook:
    """Feeds key events into .events (a queue of (vk, down) tuples)."""

    def __init__(self):
        self.events = queue.Queue()
        self.running = False
        self._thread = None
        self._proc = None  # keeps the callback alive
        self._thread_id = 0
        self._ready = threading.Event()
        self._user32 = self._kernel32 = None

    def start(self):
        if self.running:
            return True
        if sys.platform != "win32":
            return False
        self._ready.clear()
        self._thread = threading.Thread(target=self._thread_main,
                                        daemon=True, name="ringx-keyhook")
        self._thread.start()
        self._ready.wait(2.0)  # hook install (or failure) must happen first
        self.running = self._thread_id != 0
        return self.running

    def stop(self):
        if self.running and self._thread is not None:
            if self._user32 is not None:
                self._user32.PostThreadMessageW(self._thread_id, WM_QUIT, 0, 0)
            self._thread.join(timeout=2.0)
        self.running = False
        self._thread = None

    # --- internals (Windows only) -------------------------------------------

    def _thread_main(self):
        user32 = ctypes.WinDLL("user32", use_last_error=True)
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self._user32, self._kernel32 = user32, kernel32

        user32.CallNextHookEx.restype = wintypes.LRESULT
        user32.CallNextHookEx.argtypes = [ctypes.c_void_p, ctypes.c_int,
                                          wintypes.WPARAM, wintypes.LPARAM]

        hook_proc = ctypes.WINFUNCTYPE(
            wintypes.LRESULT, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)
        self._proc = hook_proc(self._on_hook)

        user32.SetWindowsHookExW.restype = ctypes.c_void_p
        user32.SetWindowsHookExW.argtypes = [ctypes.c_int, hook_proc,
                                             wintypes.HINSTANCE, wintypes.DWORD]
        hook = user32.SetWindowsHookExW(
            WH_KEYBOARD_LL, self._proc, kernel32.GetModuleHandleW(None), 0)
        if not hook:
            self._ready.set()
            return

        self._thread_id = kernel32.GetCurrentThreadId()
        self._ready.set()

        msg = wintypes.MSG()
        # GetMessageW returns 0 on WM_QUIT, -1 on error; both end the pump.
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))

        user32.UnhookWindowsHookEx(hook)
        self._thread_id = 0

    def _on_hook(self, n_code, w_param, l_param):
        if n_code == HC_ACTION:
            info = ctypes.cast(l_param,
                               ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
            if not info.flags & LLKHF_INJECTED:
                down = w_param in (WM_KEYDOWN, WM_SYSKEYDOWN)
                self.events.put((int(info.vkCode), down))
        return self._user32.CallNextHookEx(None, n_code, w_param, l_param)
