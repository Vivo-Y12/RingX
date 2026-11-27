/// Phone link server (PC side): WebSocket receiver via `dart:io`.
///
/// One phone at a time, same wire protocol as the portable edition's
/// `wsserver.py` (which this replaces for the Flutter build). Also serves
/// the touch-controller web page on `http://<ip>:<port>/` as a fallback
/// for phones without the APK.
library;

import 'dart:async';
import 'dart:io';

import 'phone_proto.dart';

typedef PageLoader = Future<List<int>?> Function();

class PhoneLink {
  PhoneLink({PageLoader? pageLoader}) : _pageLoader = pageLoader;

  final PageLoader? _pageLoader;

  HttpServer? _http;
  WebSocket? _client;
  StreamSubscription? _httpSub;
  StreamSubscription? _clientSub;

  int? port;
  String phoneName = 'Phone';

  final _events = StreamController<PhoneMsg>.broadcast();
  final _clientChanges = StreamController<bool>.broadcast();

  /// Decoded phone messages (state, toggle, hello, template sync).
  Stream<PhoneMsg> get events => _events.stream;

  /// True → a phone just connected; false → it disconnected.
  Stream<bool> get clientChanges => _clientChanges.stream;

  bool get running => _http != null;
  bool get connected => _client != null;

  /// Binds [port] (falling back to +1..+20 like the Python server).
  /// Returns (ok, error).
  Future<(bool, String?)> start(int port) async {
    if (running) return (true, null);
    HttpServer? server;
    for (var candidate = port; candidate < port + 21; candidate++) {
      try {
        server = await HttpServer.bind(
            InternetAddress.anyIPv4, candidate, shared: false);
        break;
      } on SocketException {
        continue;
      }
    }
    if (server == null) {
      return (false, 'No free port in $port-${port + 20}.');
    }
    _http = server;
    this.port = server.port;
    _httpSub = server.listen(_onRequest, onError: (_) {});
    return (true, null);
  }

  Future<void> stop() async {
    await _clientSub?.cancel();
    _clientSub = null;
    final client = _client;
    _client = null;
    try {
      await client?.close(1001);
    } on StateError catch (_) {
      // already closed
    } on SocketException catch (_) {
      // peer vanished
    }
    await _httpSub?.cancel();
    _httpSub = null;
    final http = _http;
    _http = null;
    port = null;
    phoneName = 'Phone';
    try {
      await http?.close(force: true);
    } on SocketException catch (_) {
      // port already gone
    }
  }

  /// Sends one message to the phone; silently ignores failures.
  void send(PhoneMsg msg) {
    final client = _client;
    if (client == null) return;
    try {
      client.add(msg.encode());
    } on StateError catch (_) {
      // sink closed between our check and the write
    }
  }

  Future<void> _onRequest(HttpRequest req) async {
    // Any request carrying a WebSocket Upgrade is a controller session,
    // whatever path it used (the QR encodes ws://ip:port, phone.html uses
    // ws://ip:port/ws — both must work).
    if (req.headers.value('Upgrade')?.toLowerCase() == 'websocket') {
      final WebSocket ws;
      try {
        ws = await WebSocketTransformer.upgrade(req);
      } on WebSocketException catch (_) {
        return; // transformer already rejected it
      }
      _attach(ws);
      return;
    }
    final path = req.uri.path.isEmpty ? '/' : req.uri.path;
    try {
      if (path == '/' || path == '/index.html') {
        final loader = _pageLoader;
        if (loader == null) {
          _httpText(req, 200, 'phone page not bundled');
        } else {
          final bytes = await loader();
          if (bytes != null) {
            req.response.statusCode = 200;
            req.response.headers.contentType =
                ContentType('text', 'html', charset: 'utf-8');
            req.response.headers.set('Cache-Control', 'no-store');
            req.response.add(bytes);
            await req.response.close();
          } else {
            _httpText(req, 200, 'phone page not bundled');
          }
        }
      } else if (path == '/favicon.ico') {
        req.response.statusCode = 204;
        await req.response.close();
      } else {
        _httpText(req, 404, 'not found');
      }
    } on SocketException catch (_) {
      // client dropped mid-response
    } on HttpException catch (_) {
      // malformed request; the socket is not ours to reason about
    }
  }

  void _httpText(HttpRequest req, int code, String body) {
    req.response.statusCode = code;
    req.response.headers.contentType =
        ContentType('text', 'plain', charset: 'utf-8');
    req.response.write(body);
    req.response.close();
  }

  void _attach(WebSocket ws) {
    if (_client != null) {
      // One phone at a time — mirrors the Python server (close 1008).
      try {
        ws.close(1008, 'another phone is connected');
      } on StateError catch (_) {}
      return;
    }
    _client = ws;
    // Detect dead phones quickly: server-side pings every 5 s.
    ws.pingInterval = const Duration(seconds: 5);
    _clientSub = ws.listen(
      (data) {
        if (data is String) {
          final msg = PhoneMsg.tryDecode(data);
          if (msg != null) {
            if (msg is HelloMsg) phoneName = msg.name;
            _events.add(msg);
          }
        }
        // Binary frames are ignored (junk), keeping the session alive.
      },
      onDone: () {
        _detach();
      },
      onError: (_) {
        _detach();
      },
      cancelOnError: true,
    );
    _clientChanges.add(true);
  }

  void _detach() {
    if (_client == null) return;
    _clientSub?.cancel();
    _clientSub = null;
    _client = null;
    phoneName = 'Phone';
    _clientChanges.add(false);
  }

  /// LAN IPv4 candidates for the QR code / dashboard URLs.
  static Future<List<String>> lanIps() async {
    final ips = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback) ips.add(a.address);
        }
      }
    } on SocketException catch (_) {
      // no network at all right now
    }
    return ips.toList()..sort();
  }
}
