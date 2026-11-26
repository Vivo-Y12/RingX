"""Ringx portable-edition test suite.

Runs anywhere with plain Python 3 (no pytest, no Windows):
    python tests/test_ringx.py

Covers: shaper math, profile validation/roundtrip/store, full engine
behavior with a fake vJoy + fake hook, and a headless UI smoke test
(needs Xvfb on Linux; skipped if no display is possible).
"""

import os
import queue
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                ".."))

from ringx_app import engine as engine_mod  # noqa: E402
from ringx_app.engine import Engine  # noqa: E402
from ringx_app.keyhook import KeyHook  # noqa: E402
from ringx_app.profile import (AXES, Binding, Profile, ProfileStore,  # noqa: E402
                               vk_name)
from ringx_app.shaper import AxisConfig, AxisShaper  # noqa: E402
from ringx_app.vjoy import (STAT_FREE, USAGE_X, USAGE_Y, USAGE_Z,  # noqa: E402
                            axis_name)

PASS = 0


def check(name, cond):
    global PASS
    assert cond, f"FAILED: {name}"
    PASS += 1
    print(f"  ok  {name}")


# --- ui prerequisites (self-provisioning on bare CI images) -------------------

def _missing_ui_packages():
    """apt packages the headless UI sections need ([] when all present)."""
    missing = []
    try:
        import tkinter  # noqa: F401
    except Exception:
        missing.append("python3-tk")
    if shutil.which("Xvfb") is None:
        missing.append("xvfb")
    return missing


def _install_ui_packages(packages):
    """apt-get install the missing packages (sudo unless already root).

    CI package mirrors occasionally hiccup (hash-sum mismatches while a
    mirror syncs); a short retry loop makes provisioning solid.
    """
    sudo = [] if os.geteuid() == 0 else ["sudo"]
    cmds = [sudo + ["apt-get", "update", "-qq"],
            sudo + ["apt-get", "install", "-y", "-qq"] + packages]

    def run_all():
        for cmd in cmds:
            if os.environ.get("RINGX_TEST_APT_DRYRUN"):
                print("  dry-run:", " ".join(cmd))
                continue
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode != 0:
                raise RuntimeError(f"{' '.join(cmd)} -> exit {r.returncode}\n"
                                   f"{r.stderr[-400:]}")

    for attempt in (1, 2, 3):
        try:
            run_all()
            return
        except Exception as e:
            print(f"  apt attempt {attempt} failed: {e}")
            if attempt < 3:
                time.sleep(5 * attempt)
    raise RuntimeError("apt-get failed after 3 attempts")


def ensure_ui_prereqs():
    """Install tkinter/Xvfb on demand so CI runs the full suite for real.

    Bare CI images (e.g. ubuntu-latest) ship neither package, and the
    Xvfb-driven sections would otherwise crash. Locally both are normally
    present and this is a no-op. Without sudo the suite degrades to its
    documented skip paths instead of installing anything.
    """
    if sys.platform == "win32":
        return
    missing = _missing_ui_packages()
    if not missing:
        return
    print("ui prerequisites missing:", ", ".join(missing))
    if not (os.geteuid() == 0 or shutil.which("sudo")):
        print("  no sudo available; install the packages above for the "
              "full suite")
        return
    try:
        _install_ui_packages(missing)
        if not os.environ.get("RINGX_TEST_APT_DRYRUN"):
            print("  installed:", ", ".join(missing))
    except Exception as e:
        print("  install failed:", e)
    still = _missing_ui_packages()
    if still and not os.environ.get("RINGX_TEST_APT_DRYRUN"):
        # The headless UI sections cannot run without these packages; fail
        # now with a clear reason instead of a confusing FileNotFoundError
        # crashing the suite halfway through.
        print("FATAL: required packages still missing after install "
              f"attempts: {', '.join(still)}", file=sys.stderr)
        sys.exit(2)


# --- fakes ------------------------------------------------------------------

class FakeVjoy:
    """Records writes; mimics the vjoy.Vjoy surface used by Engine."""

    def __init__(self):
        self.enabled = True
        self.version = 0x214
        self.axis_writes = []
        self.btn_writes = []
        self.calls = []

    def status(self, device_id):
        return STAT_FREE

    def acquire(self, device_id):
        self.calls.append(("acquire", device_id))
        return True

    def relinquish(self, device_id):
        self.calls.append(("relinquish", device_id))

    def reset(self, device_id):
        self.calls.append(("reset", device_id))

    def axis_exists(self, device_id, usage):
        return usage in (USAGE_X, USAGE_Y, USAGE_Z)

    def axis_range(self, device_id, usage):
        return 0x1, 0x8000

    def set_axis(self, value, device_id, usage):
        self.axis_writes.append((value, device_id, usage))
        return True

    def set_btn(self, pressed, device_id, button):
        self.btn_writes.append((pressed, device_id, button))
        return True


class FakeHook:
    def __init__(self):
        self.events = queue.Queue()

    def start(self):
        return True

    def stop(self):
        pass


# --- shaper -----------------------------------------------------------------

def test_shaper():
    print("shaper:")
    cfg = AxisConfig(attack_ms=200, decay_ms=100)
    s = AxisShaper()
    s.step(100, 1, cfg)
    out = s.step(100, 1, cfg)
    check("reaches full after attack time", out > 0.99 and s.value == 1.0)

    s = AxisShaper()
    s.value = 1.0
    s.step(100, 0, cfg)
    check("returns to neutral after decay time", s.value == 0.0)

    left = AxisShaper()
    left.step(50, -1, cfg)
    right = AxisShaper()
    right.step(50, 1, cfg)
    check("left/right symmetric", left.value == -right.value)

    s = AxisShaper()
    s.step(5000, 1, cfg)
    check("overshoot clamped to target", s.value == 1.0)

    smooth = AxisConfig(curve="smooth", anti_dz=0)
    check("smoothstep midpoint", abs(AxisShaper.shape(0.5, smooth) - 0.5)
          < 0.001)
    check("smoothstep quarter", abs(AxisShaper.shape(0.25, smooth) - 0.15625)
          < 0.001)

    adz = AxisConfig(anti_dz=0.08)
    check("anti-deadzone floor lifts small inputs",
          AxisShaper.shape(0.02, adz) == 0.08)
    check("anti-deadzone leaves large inputs",
          AxisShaper.shape(0.5, adz) > 0.08)
    check("zero stays zero", AxisShaper.shape(0, adz) == 0)
    check("negative keeps sign", AxisShaper.shape(-0.5, adz) < 0)

    bad = AxisConfig.from_dict({"attack_ms": -5, "decay_ms": "x",
                                "curve": "bogus", "anti_dz": 99})
    check("config clamps bad values", bad.attack_ms == 10
          and bad.decay_ms == 180 and bad.curve == "smooth"
          and bad.anti_dz == 0.25)


# --- profile ----------------------------------------------------------------

def test_profile():
    print("profile:")
    p = Profile.defaults()
    check("defaults are WASD + Space",
          [(b.vk, b.act, b.button) for b in p.bindings] ==
          [(0x41, "steer_left", 1), (0x44, "steer_right", 1),
           (0x57, "throttle", 1), (0x53, "brake", 1),
           (0x20, "button", 1)])
    check("default toggle is F8", p.toggle_vk == 0x77)
    check("default axes present", set(p.axes) == set(AXES))

    # roundtrip
    p2 = Profile.from_dict(p.to_dict())
    check("JSON roundtrip keeps bindings",
          [(b.vk, b.act, b.button) for b in p2.bindings] ==
          [(b.vk, b.act, b.button) for b in p.bindings])
    check("JSON roundtrip keeps axis tuning",
          p2.axes["steer"].to_dict() == p.axes["steer"].to_dict())

    # hostile input
    bad = Profile.from_dict({"name": "x" * 100, "device_id": 999,
                             "tick_ms": -1, "toggle_vk": None,
                             "bindings": ["junk", {"vk": 7, "act": "nope",
                                                   "button": 999}],
                             "axes": "junk"})
    check("hostile JSON fully clamped", len(bad.name) == 40
          and bad.device_id == 16 and bad.tick_ms == 10
          and bad.bindings[1].act == "button" and bad.bindings[1].button == 32
          and bad.bindings[0].vk == 0 and bad.bindings[1].vk == 7
          and bad.axes["steer"].curve == "smooth")

    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "profile.json")
        store = ProfileStore(path)
        loaded, err = store.load()
        check("missing file -> defaults, no error",
              err is None and loaded.bindings == p.bindings)
        ok, err = store.save(loaded)
        check("save ok", ok and err is None)
        with open(path, "w", encoding="utf-8") as f:
            f.write("{broken json")
        loaded, err = store.load()
        check("corrupt file -> defaults + error message",
              err is not None and len(loaded.bindings) == 5)
        check("no tmp files left", os.listdir(td) == ["profile.json"])

    check("vk names", vk_name(0x41) == "A" and vk_name(0x77) == "F8"
          and vk_name(0x25) == "Left" and vk_name(0xFE) == "VK_0xFE")
    check("axis names", axis_name(USAGE_X) == "X" and axis_name(USAGE_Z) == "Z")


# --- engine -----------------------------------------------------------------

def test_engine():
    print("engine:")
    vjoy = FakeVjoy()
    store = ProfileStore(os.path.join(tempfile.mkdtemp(), "p.json"))
    eng = Engine(store, Profile.defaults(), vjoy=vjoy, hook=FakeHook())
    eng.start()
    check("device acquired", eng.acquired)
    check("axis resolution X/Y/Z",
          eng.usages == {"steer": USAGE_X, "throttle": USAGE_Y,
                         "brake": USAGE_Z})
    check("note mentions acquire", "acquired" in eng.note)

    # steering: hold A for 350 ms total -> shaped output negative
    eng.set_enabled(True)
    eng.on_key(0x41, True)  # A
    for _ in range(18):  # 18 * 20 ms = 360 ms
        eng.tick(20)
    check("steer ramps left", eng.steer_out < -0.9)
    check("axis write is below center", vjoy.axis_writes[-1][0] < 0x4000)

    # release -> decays to center
    eng.on_key(0x41, False)
    for _ in range(12):  # 240 ms > decay 180 ms
        eng.tick(20)
    check("steer decays to center", abs(eng.steer_out) < 0.01)

    # throttle + button
    eng.on_key(0x57, True)   # W
    eng.on_key(0x20, True)   # Space = button 1
    eng.tick(20)
    btns = [w for w in vjoy.btn_writes if w[0]]
    check("button pressed immediately", (1, 1, 1) in btns)
    for _ in range(15):
        eng.tick(20)
    check("throttle ramps to full", eng.throttle_out > 0.9)

    # toggle hotkey F8: down transition only
    eng.on_key(0x77, True)
    check("F8 disables mapping", not eng.enabled)
    eng.on_key(0x77, False)
    eng.on_key(0x77, True)   # re-enable
    check("F8 re-enables", eng.enabled)
    off = [w for w in vjoy.btn_writes if not w[0]]
    check("buttons released on disable", (False, 1, 1) in off)

    # disabled (after second F8 press below) eases axes to neutral
    eng.on_key(0x77, True)
    eng.on_key(0x77, False)
    eng.on_key(0x57, False)
    eng.on_key(0x20, False)
    for _ in range(15):
        eng.tick(20)
    check("pedals ease to zero when off",
          eng.throttle_out == 0 and eng.brake_out == 0)

    # device switch releases the OLD device id
    old_id = eng.profile.device_id
    p = Profile.from_dict(eng.profile.to_dict())
    p.device_id = 2
    eng.apply_profile(p)
    check("old device relinquished on switch",
          ("relinquish", old_id) in vjoy.calls)
    check("reacquired on new device", ("acquire", 2) in vjoy.calls)

    # recent keys capped, latest first
    check("recent keys tracked", eng.recent_keys and
          eng.recent_keys[0] in (0x57, 0x20, 0x41, 0x77))

    # axis summary shows resolved axes
    check("axis summary", eng.axis_summary() == "X/Y/Z")


# --- ui smoke (Xvfb) --------------------------------------------------------

def test_ui_smoke():
    print("ui smoke (headless):")
    try:
        import tkinter as tk
        if sys.platform == "win32" or os.environ.get("DISPLAY"):
            base = None
        else:
            base = "xvfb-run -a"
    except Exception:
        print("  skip  no tkinter")
        return

    script = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "_ui_smoke_inner.py")
    code = '''
import os, sys, queue
sys.path.insert(0, {root!r})
from ringx_app.engine import Engine
from ringx_app.profile import Profile, ProfileStore
from ringx_app.ui import RingxUI
from ringx_app.keyhook import KeyHook
import ringx_app.engine as em

class FakeVjoy:
    enabled = True; version = 1
    def status(self, d): return 1  # FREE
    def acquire(self, d): return True
    def relinquish(self, d): pass
    def reset(self, d): pass
    def axis_exists(self, d, u): return u in (0x30, 0x31, 0x32)
    def axis_range(self, d, u): return (0x1, 0x8000)
    def set_axis(self, v, d, u): pass
    def set_btn(self, p, d, b): pass

class FakeHook:
    def __init__(self): self.events = queue.Queue()
    def start(self): return True
    def stop(self): pass

store = ProfileStore(os.path.join(os.environ["SMOKE_DIR"], "p.json"))
eng = Engine(store, Profile.defaults(), vjoy=FakeVjoy(), hook=FakeHook())
eng.start()
ui = RingxUI(eng)

# simulate a few frames
for _ in range(5):
    ui.root.update()

# push keys through the UI loop (drains hook queue)
eng.hook.events.put((0x41, True))
eng.set_enabled(True)
import time
for _ in range(22):  # ~550 ms of real frame time -> attack (350 ms) completes
    ui.root.update()
    time.sleep(0.025)
assert eng.steer_out < -0.5, "steer should ramp via UI loop"
ui.root.update()

# exercise dialogs non-modally is hard; at least mappings list built
assert ui.listbox.size() == 5, ui.listbox.size()
ui._refresh_dashboard()
ui.root.update()
ui._on_close()
print("UI-OK")
'''.format(root=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             ".."))
    with open(script, "w", encoding="utf-8") as f:
        f.write(code)

    env = dict(os.environ, SMOKE_DIR=tempfile.mkdtemp())
    # xvfb-run needs xauth; drive Xvfb directly instead.
    xvfb = subprocess.Popen(
        ["Xvfb", ":7199", "-screen", "0", "1024x700x24"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    env["DISPLAY"] = ":7199"
    try:
        r = subprocess.run([sys.executable, script], env=env,
                           capture_output=True, text=True, timeout=60)
    finally:
        xvfb.terminate()
        xvfb.wait(timeout=10)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr)
    check("ui builds, ramps steering, refreshes, closes",
          r.returncode == 0 and "UI-OK" in r.stdout)
    os.unlink(script)


# --- phone: engine input path ----------------------------------------------

def test_phone_engine():
    print("phone engine:")
    import time as _t
    vjoy = FakeVjoy()
    store = ProfileStore(os.path.join(tempfile.mkdtemp(), "p.json"))
    eng = Engine(store, Profile.defaults(), vjoy=vjoy, hook=FakeHook())
    eng.start()
    eng.set_enabled(True)

    # phone state overrides the keyboard ramp directly (already analog)
    eng.on_phone_event("state", {"s": -0.8, "th": 1.0, "br": 0.0, "bt": [2]})
    eng.tick(20)
    check("phone steering applied with curve", eng.steer_out < -0.6)
    check("phone throttle applied", eng.throttle_out > 0.9)
    check("phone button pressed", (True, 1, 2) in vjoy.btn_writes)

    # button diff on the next state message
    eng.on_phone_event("state", {"s": -0.8, "th": 1.0, "br": 1.0, "bt": [3]})
    eng.tick(20)
    check("phone button released on diff", (False, 1, 2) in vjoy.btn_writes)
    check("phone new button pressed", (True, 1, 3) in vjoy.btn_writes)
    check("phone brake applied", eng.brake_out > 0.9)

    # hostile payloads are clamped, not crashed
    eng.on_phone_event("state", {"s": "junk", "th": 99, "br": -3, "bt": "x"})
    eng.tick(20)
    check("hostile phone state clamped", eng.steer_out == 0.0
          and eng.throttle_out <= 1.0 and eng.brake_out == 0.0)

    # toggle event flips mapping
    eng.on_phone_event("toggle", None)
    check("phone toggle flips mapping", not eng.enabled)
    off = [w for w in vjoy.btn_writes if not w[0]]
    check("phone buttons released on toggle-off", (False, 1, 3) in off)
    eng.on_phone_event("toggle", None)
    check("phone toggle back on", eng.enabled)

    # staleness: no packets for a while -> keyboard ramp takes over again
    eng.on_key(0x44, True)  # D = full right
    eng._phone["fresh_until"] = _t.monotonic() - 1.0
    for _ in range(20):
        eng.tick(20)
    check("stale phone reverts to keyboard", eng.steer_out > 0.9)

    # connect/disconnect events manage state
    eng.on_phone_event("state", {"s": 0.0, "th": 0, "br": 0, "bt": [5]})
    eng.on_phone_event("disconnect", None)
    check("disconnect releases phone buttons", (False, 1, 5) in vjoy.btn_writes)
    eng.on_phone_event("connect", None)
    check("connect event tracked", eng.phone_connected)


# --- phone: websocket server protocol --------------------------------------

class WsClient:
    """Minimal raw-socket websocket client for protocol tests."""

    def __init__(self, port):
        import socket as _s
        self.sock = _s.create_connection(("127.0.0.1", port), timeout=5)
        self.buf = b""

    def _fill(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("closed")
            self.buf += chunk

    def handshake(self, path="/ws", key="dGhlIHNhbXBsZSBub25jZQ=="):
        req = (f"GET {path} HTTP/1.1\r\nHost: t\r\nUpgrade: websocket\r\n"
               f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
               "Sec-WebSocket-Version: 13\r\n\r\n")
        self.sock.sendall(req.encode())
        while b"\r\n\r\n" not in self.buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("closed during handshake")
            self.buf += chunk
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        return head.decode("iso-8859-1")

    def http(self, path="/"):
        self.sock.sendall(f"GET {path} HTTP/1.1\r\nHost: t\r\n"
                          "Connection: close\r\n\r\n".encode())
        data = b""
        while True:
            chunk = self.sock.recv(4096)
            if not chunk:
                break
            data += chunk
        return data

    def send_text(self, text):
        import struct as _st
        data = text.encode()
        mask = os.urandom(4)
        header = bytearray([0x81])
        if len(data) < 126:
            header.append(0x80 | len(data))
        else:
            header.append(0x80 | 126)
            header += _st.pack(">H", len(data))
        masked = bytes(b ^ mask[i & 3] for i, b in enumerate(data))
        self.sock.sendall(bytes(header) + mask + masked)

    def recv_frame(self):
        import struct as _st
        self._fill(2)
        b1, b2 = self.buf[0], self.buf[1]
        ln, off = b2 & 0x7F, 2
        if ln == 126:
            self._fill(4)
            ln = _st.unpack(">H", self.buf[2:4])[0]
            off = 4
        self._fill(off + ln)
        payload = self.buf[off:off + ln]
        self.buf = self.buf[off + ln:]
        return b1 & 0x0F, payload

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def test_wsserver():
    print("wsserver:")
    import struct
    from ringx_app.wsserver import _ws_accept
    check("RFC 6455 handshake accept (known answer)",
          _ws_accept("dGhlIHNhbXBsZSBub25jZQ==")
          == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    from ringx_app.wsserver import PhoneLink
    link = PhoneLink()
    ok, err = link.start(0)  # ephemeral port
    check("server starts", ok and err is None and link.running)
    port = link.port

    # plain HTTP page serve
    page_cli = WsClient(port)
    page = page_cli.http("/")
    check("GET / serves the controller page",
          page.startswith(b"HTTP/1.1 200")
          and b"viewport" in page
          and b"Ringx Controller" in page)
    page_cli.close()
    miss = WsClient(port).http("/nope")
    check("unknown path -> 404", miss.startswith(b"HTTP/1.1 404"))

    # websocket session
    cli = WsClient(port)
    head = cli.handshake()
    check("101 + accept header", "101" in head
          and "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" in head)
    import time as _t
    _t.sleep(0.05)
    check("connect event queued", link.connected)
    kind, payload = link.events.get_nowait()
    check("connect event kind", kind == "connect")

    # phone state message flows into the queue
    cli.send_text('{"t":"state","s":0.5,"th":1,"br":0,"bt":[1,4]}')
    _t.sleep(0.05)
    kinds = []
    while not link.events.empty():
        kinds.append(link.events.get_nowait())
    state = [p for k, p in kinds if k == "state"]
    check("state message received", state and state[0]["s"] == 0.5
          and state[0]["bt"] == [1, 4])

    # toggle message
    cli.send_text('{"t":"toggle"}')
    _t.sleep(0.05)
    kinds = []
    while not link.events.empty():
        kinds.append(link.events.get_nowait())
    check("toggle message received", ("toggle", None) in kinds)

    # junk does not kill the session
    cli.send_text("not json at all")
    cli.send_text('{"t":"unknown"}')
    _t.sleep(0.05)
    while not link.events.empty():
        link.events.get_nowait()
    cli.send_text('{"t":"state","s":-1}')
    _t.sleep(0.05)
    got = None
    while not link.events.empty():
        k, p = link.events.get_nowait()
        if k == "state":
            got = p
    check("session survives junk", got and got["s"] == -1)

    # server -> phone push
    link.send_stat(True)
    opcode, payload = cli.recv_frame()
    import json as _j
    check("stat push reaches phone", opcode == 1
          and _j.loads(payload.decode()) == {"t": "stat", "enabled": True})

    # second client is politely rejected (one phone at a time)
    cli2 = WsClient(port)
    head2 = cli2.handshake()
    opcode2, payload2 = cli2.recv_frame()
    check("second client gets 101 then close 1008",
          "101" in head2 and opcode2 == 0x8
          and struct.unpack(">H", payload2[:2])[0] == 1008)
    cli2.close()

    # ping is answered with pong
    import struct as _st
    mask = os.urandom(4)
    cli.sock.sendall(bytes([0x89, 0x80 | 4]) + mask
                     + bytes(b ^ mask[i & 3] for i, b in enumerate(b"ping")))
    opcode, payload = cli.recv_frame()
    check("ping answered with pong", opcode == 0xA and payload == b"ping")

    # clean close handshake
    mask = os.urandom(4)
    cli.sock.sendall(bytes([0x88, 0x80 | 2]) + mask
                     + bytes(b ^ mask[i & 3] for i, b in enumerate(b"\x03\xe8")))
    opcode, payload = cli.recv_frame()
    check("close echoed", opcode == 0x8
          and struct.unpack(">H", payload[:2])[0] == 1000)
    cli.close()
    _t.sleep(0.1)
    check("disconnect event after close", not link.connected)

    # restart on the same object works (stop -> start)
    link.stop()
    check("stop clears state", not link.running and link.port is None
          or not link.running)
    ok, err = link.start(0)
    check("restart works", ok and link.running)
    link.stop()


# --- phone: page static checks ---------------------------------------------

def test_phone_html():
    print("phone.html:")
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "ringx_app", "phone.html")
    with open(path, encoding="utf-8") as f:
        html = f.read()
    check("viewport meta", 'name="viewport"' in html)
    check("touch-action disabled", "touch-action:none" in html)
    check("pointer events for multitouch", "pointerdown" in html
          and "setPointerCapture" in html)
    check("websocket client", "new WebSocket" in html)
    check("state payload fields", 't: "state"' in html and "bt:" in html)
    import re
    ext = re.findall(r'(?:src|href)\s*=\s*["\']https?://[^"\']+["\']', html)
    check("no external resources", not ext)
    check("portrait hint", 'orientation: portrait' in html)
    check("tilt mode present", "deviceorientation" in html)

    # JS syntax check with node
    m = re.search(r"<script>(.*)</script>", html, re.S)
    ok = False
    if m:
        with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False,
                                         encoding="utf-8") as f:
            f.write(m.group(1))
            js = f.name
        r = subprocess.run(["node", "--check", js], capture_output=True,
                           text=True)
        os.unlink(js)
        ok = r.returncode == 0
        if not ok:
            print(r.stderr[:400])
    check("inline JS parses (node --check)", ok)


# --- phone: full integration (Xvfb + real ws client) -----------------------

def test_phone_integration():
    print("phone integration (headless):")
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "_phone_int_inner.py")
    code = r'''
import json, os, queue, struct, sys, time
sys.path.insert(0, {root!r})
from ringx_app.engine import Engine
from ringx_app.keyhook import KeyHook
from ringx_app.profile import Profile, ProfileStore
from ringx_app.ui import RingxUI
from ringx_app.wsserver import PhoneLink

class FakeVjoy:
    enabled = True; version = 1
    def __init__(self): self.btn_log = []
    def status(self, d): return 1
    def acquire(self, d): return True
    def relinquish(self, d): pass
    def reset(self, d): pass
    def axis_exists(self, d, u): return u in (0x30, 0x31, 0x32)
    def axis_range(self, d, u): return (0x1, 0x8000)
    def set_axis(self, v, d, u): pass
    def set_btn(self, p, d, b): self.btn_log.append((p, d, b))

class FakeHook:
    def __init__(self): self.events = queue.Queue()
    def start(self): return True
    def stop(self): pass

import socket
store = ProfileStore(os.path.join(os.environ["SMOKE_DIR"], "p.json"))
profile = Profile.defaults()
profile.phone_enabled = False  # started manually below on an ephemeral port
eng = Engine(store, profile, vjoy=FakeVjoy(), hook=FakeHook())
link = PhoneLink()
eng.phone_link = link
eng.start()
ok, err = link.start(0)
assert ok, err
ui = RingxUI(eng)
for _ in range(3):
    ui.root.update()

# --- raw websocket client (the "phone")
def frame(data):
    mask = os.urandom(4)
    return (bytes([0x81, 0x80 | len(data)]) + mask
            + bytes(b ^ mask[i & 3] for i, b in enumerate(data)))

s = socket.create_connection(("127.0.0.1", link.port), timeout=5)
s.sendall(("GET /ws HTTP/1.1\r\nHost: t\r\nUpgrade: websocket\r\n"
           "Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
           "Sec-WebSocket-Version: 13\r\n\r\n").encode())
buf = b""
while b"\r\n\r\n" not in buf:
    buf += s.recv(4096)
assert b"101 Switching Protocols" in buf, buf[:200]
buf = buf.split(b"\r\n\r\n", 1)[1]

# wait for the engine's stat push after the connect event is drained
deadline = time.time() + 2
stat = None
while time.time() < deadline and stat is None:
    ui.root.update()
    try:
        s.settimeout(0.05)
        chunk = s.recv(4096)
        if chunk:
            buf += chunk
            if b"\x81" in buf and len(buf) >= 2:
                ln = buf[1] & 0x7F
                if len(buf) >= 2 + ln:
                    payload = buf[2:2 + ln]
                    stat = json.loads(payload.decode())
                    buf = buf[2 + ln:]
    except socket.timeout:
        pass
assert stat == {{"t": "stat", "enabled": False}}, stat

# enable mapping from the "phone" and drive it like the real page does:
# a state message every ~50 ms keeps the link fresh
s.sendall(frame(b'{{"t":"toggle"}}'))
for i in range(30):
    if i == 0:
        s.sendall(frame(b'{{"t":"state","s":-0.7,"th":1,"br":0,"bt":[2]}}'))
    elif i % 2 == 0:
        s.sendall(frame(b'{{"t":"state","s":-0.7,"th":1,"br":0,"bt":[2]}}'))
    ui.root.update()
    time.sleep(0.025)
assert eng.enabled, "toggle message should enable mapping"
assert eng.throttle_out > 0.9, eng.throttle_out
assert eng.steer_out < -0.5, eng.steer_out
assert (True, 1, 2) in eng.vjoy.btn_log, eng.vjoy.btn_log

# staleness works through the live loop too: stop sending, pedal eases out
for _ in range(30):
    ui.root.update()
    time.sleep(0.025)
assert eng.throttle_out < 0.1, f"stale phone should decay, got {{eng.throttle_out}}"

# phone label reflects connection
assert "phone connected" in ui.lbl_phone.cget("text"), ui.lbl_phone.cget("text")

# toggle off -> buttons released, stat pushed to phone
s.sendall(frame(b'{{"t":"toggle"}}'))
for _ in range(10):
    ui.root.update()
    time.sleep(0.025)
assert not eng.enabled
ui._on_close()
print("PHONE-INT-OK")
'''.format(root=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "..")).replace("{{", "{").replace("}}", "}")
    with open(script, "w", encoding="utf-8") as f:
        f.write(code)

    env = dict(os.environ, SMOKE_DIR=tempfile.mkdtemp())
    xvfb = subprocess.Popen(
        ["Xvfb", ":7199", "-screen", "0", "1024x700x24"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    env["DISPLAY"] = ":7199"
    try:
        r = subprocess.run([sys.executable, script], env=env,
                           capture_output=True, text=True, timeout=90)
    finally:
        xvfb.terminate()
        xvfb.wait(timeout=10)
    if r.returncode != 0:
        print(r.stdout[-1500:])
        print(r.stderr[-1500:])
    check("real ws client drives the live UI+engine",
          r.returncode == 0 and "PHONE-INT-OK" in r.stdout)
    os.unlink(script)


if __name__ == "__main__":
    ensure_ui_prereqs()
    test_shaper()
    test_profile()
    test_engine()
    test_phone_engine()
    test_wsserver()
    test_phone_html()
    test_ui_smoke()
    test_phone_integration()
    print(f"\nALL TESTS PASSED ({PASS} checks)")
