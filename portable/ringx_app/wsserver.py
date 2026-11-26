"""Phone controller link: a tiny HTTP + WebSocket (RFC 6455) server.

Serves the touch-controller page on http://<pc-ip>:<port> and accepts one
WebSocket client (the phone's browser) at /ws. Phone events land in .events
as (kind, payload) tuples — the same queue pattern as the keyboard hook, so
the UI loop can drain them in one place. Standard library only.
"""

import base64
import hashlib
import json
import os
import queue
import socket
import socketserver
import struct
import threading

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_PAYLOAD = 4096
_PAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "phone.html")


def _send_frame(sock, data, opcode=0x1):
    """One unmasked server frame (text by default)."""
    header = bytearray([0x80 | opcode])
    n = len(data)
    if n < 126:
        header.append(n)
    elif n < 65536:
        header.append(126)
        header += struct.pack(">H", n)
    else:
        header.append(127)
        header += struct.pack(">Q", n)
    sock.sendall(bytes(header) + bytes(data))


def _send_close(sock, code=1000):
    _send_frame(sock, struct.pack(">H", code), opcode=0x8)


def _ws_accept(key):
    digest = hashlib.sha1((key + WS_GUID).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


class _Handler(socketserver.StreamRequestHandler):
    """One connection: plain HTTP request or a WebSocket session."""

    disable_nagle_algorithm = True

    def setup(self):
        super().setup()
        self.request.settimeout(30)

    def handle(self):
        try:
            request_line = self.rfile.readline(2048).decode(
                "iso-8859-1").strip()
            headers = {}
            while True:
                line = self.rfile.readline(2048).decode("iso-8859-1")
                if line in ("\r\n", "\n", ""):
                    break
                if ":" in line:
                    k, v = line.split(":", 1)
                    headers[k.strip().lower()] = v.strip()
        except (OSError, ValueError):
            return
        parts = request_line.split()
        if len(parts) < 2:
            self._http(400, b"bad request")
            return
        method, path = parts[0], parts[1].split("?")[0]
        if method == "GET" and path in ("/", "/index.html"):
            self._http(200, self.server.link._load_page(),
                       "text/html; charset=utf-8")
        elif method == "GET" and path == "/favicon.ico":
            self._http(204, b"")
        elif method == "GET" and path == "/ws" and \
                headers.get("upgrade", "").lower() == "websocket":
            self._ws_session(headers)
        else:
            self._http(404, b"not found")

    # ---- plain HTTP --------------------------------------------------------

    def _http(self, code, body, ctype="text/plain; charset=utf-8"):
        reason = {200: "OK", 204: "No Content", 400: "Bad Request",
                  404: "Not Found"}.get(code, "OK")
        head = (f"HTTP/1.1 {code} {reason}\r\n"
                f"Content-Type: {ctype}\r\n"
                f"Content-Length: {len(body)}\r\n"
                f"Cache-Control: no-store\r\n"
                f"Connection: close\r\n\r\n")
        try:
            self.request.sendall(head.encode("ascii") + body)
        except OSError:
            pass

    # ---- websocket ---------------------------------------------------------

    def _ws_session(self, headers):
        key = headers.get("sec-websocket-key")
        if not key or headers.get("sec-websocket-version") != "13":
            self._http(400, b"bad websocket request")
            return
        link = self.server.link
        try:
            self.request.sendall(
                ("HTTP/1.1 101 Switching Protocols\r\n"
                 "Upgrade: websocket\r\n"
                 "Connection: Upgrade\r\n"
                 f"Sec-WebSocket-Accept: {_ws_accept(key)}\r\n\r\n"
                 ).encode("ascii"))
        except OSError:
            return

        with link._client_lock:
            if link._client_sock is not None:
                try:  # one phone at a time
                    _send_close(self.request, 1008)
                except OSError:
                    pass
                return
            link._client_sock = self.request
        link.connected = True
        link.events.put(("connect", None))
        try:
            self._ws_loop()
        finally:
            self._ws_cleanup()

    def _ws_cleanup(self):
        link = self.server.link
        with link._client_lock:
            if link._client_sock is self.request:
                link._client_sock = None
                link.connected = False
                link.events.put(("disconnect", None))
        try:
            self.request.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    def _read_exact(self, n):
        data = bytearray()
        while len(data) < n:
            chunk = self.rfile.read(n - len(data))
            if not chunk:
                raise ConnectionError("socket closed mid-frame")
            data += chunk
        return bytes(data)

    def _ws_loop(self):
        self.request.settimeout(180)
        link = self.server.link
        frag = b""
        frag_text = False
        while link.running:
            try:
                b1, b2 = self._read_exact(2)
            except (OSError, ConnectionError):
                return
            fin, opcode = b1 & 0x80, b1 & 0x0F
            masked, ln = b2 & 0x80, b2 & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", self._read_exact(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", self._read_exact(8))[0]
            if ln > MAX_PAYLOAD:
                _send_close(self.request, 1009)
                return
            if not masked:  # client frames MUST be masked (RFC 6455 5.1)
                _send_close(self.request, 1002)
                return
            mask = self._read_exact(4)
            payload = bytearray(self._read_exact(ln)) if ln else bytearray()
            for i in range(ln):
                payload[i] ^= mask[i & 3]

            if opcode == 0x8:  # close
                try:
                    _send_close(self.request, 1000)
                except OSError:
                    pass
                return
            if opcode == 0x9:  # ping -> pong
                try:
                    _send_frame(self.request, payload, opcode=0xA)
                except OSError:
                    return
                continue
            if opcode == 0xA:  # pong
                continue
            if opcode in (0x1, 0x2):  # text / binary, maybe fragmented
                frag = bytes(payload)
                frag_text = opcode == 0x1
                if fin:
                    self._ws_message(frag, frag_text)
                    frag = b""
                continue
            if opcode == 0x0:  # continuation
                frag += bytes(payload)
                if len(frag) > MAX_PAYLOAD:
                    _send_close(self.request, 1009)
                    return
                if fin:
                    self._ws_message(frag, frag_text)
                    frag = b""
                continue
            # unknown opcode: ignore the payload, keep the session

    def _ws_message(self, data, is_text):
        if not is_text:
            return
        try:
            msg = json.loads(data.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return
        if not isinstance(msg, dict):
            return
        kind = msg.get("t")
        if kind == "state":
            self.server.link.events.put(("state", msg))
        elif kind == "toggle":
            self.server.link.events.put(("toggle", None))


class _Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class PhoneLink:
    """Owns the server thread; engine/UI talk to this object only."""

    def __init__(self):
        self.events = queue.Queue()
        self.port = None
        self.running = False
        self.connected = False
        self._server = None
        self._client_sock = None
        self._client_lock = threading.Lock()
        self._send_lock = threading.Lock()
        self._page = None
        self._page_checked = False

    # ---- lifecycle ---------------------------------------------------------

    def start(self, port=9870):
        """Bind port (falls back to +1..+20). Returns (ok, error_or_None)."""
        if self.running:
            return True, None
        server = None
        for candidate in range(port, port + 21):
            try:
                server = _Server(("0.0.0.0", candidate), _Handler)
                break
            except OSError:
                continue
        if server is None:
            return False, f"no free port in {port}-{port + 20}"
        server.link = self
        self._server = server
        self.port = server.server_address[1]
        self.running = True
        threading.Thread(target=server.serve_forever, daemon=True,
                         name="ringx-phone-link").start()
        return True, None

    def stop(self):
        if not self.running:
            return
        self.running = False
        self.connected = False
        self._close_client()
        server = self._server
        self._server = None
        if server is not None:
            server.shutdown()
            server.server_close()
        while not self.events.empty():
            try:
                self.events.get_nowait()
            except queue.Empty:
                break

    def _close_client(self):
        with self._client_lock:
            sock, self._client_sock = self._client_sock, None
        if sock is not None:
            try:
                _send_close(sock, 1001)
            except OSError:
                pass
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    # ---- info ---------------------------------------------------------------

    def _load_page(self):
        if not self._page_checked:
            self._page_checked = True
            try:
                with open(_PAGE, "rb") as f:
                    self._page = f.read()
            except OSError:
                self._page = (b"<!doctype html><meta charset=utf-8>"
                              b"<body>phone page (phone.html) missing")
        return self._page

    def urls(self):
        """http://ip:port candidates for every local IPv4 address."""
        ips = set()
        try:
            for info in socket.getaddrinfo(socket.gethostname(), None,
                                           socket.AF_INET):
                ips.add(info[4][0])
        except OSError:
            pass
        ips.discard("127.0.0.1")
        if not ips:
            return [f"http://127.0.0.1:{self.port}"] if self.port else []
        return sorted(f"http://{ip}:{self.port}" for ip in ips)

    def status_text(self):
        if not self.running:
            return "phone link off"
        if self.connected:
            return f"phone connected  (port {self.port})"
        urls = self.urls()
        if len(urls) == 1:
            return f"waiting — open {urls[0]} in the phone browser"
        return f"waiting for phone  (try {', '.join(urls)})"

    # ---- outbound -----------------------------------------------------------

    def send_json(self, obj):
        """Thread-safe send to the current phone; silently ignores failures."""
        with self._client_lock:
            sock = self._client_sock
        if sock is None:
            return
        data = json.dumps(obj).encode("utf-8")
        with self._send_lock:
            try:
                _send_frame(sock, data)
            except OSError:
                pass

    def send_stat(self, enabled):
        self.send_json({"t": "stat", "enabled": bool(enabled)})
