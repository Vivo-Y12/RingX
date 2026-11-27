/// UDP discovery: the phone broadcasts `RINGX_DISCOVER` on port 5556 and
/// every RingX receiver on the LAN answers with `RINGX ws://<ip>:<port>`.
/// Secondary to QR pairing — QR always works, this is the "find my PC"
/// button. Both classes are `dart:io` only.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'phone_link.dart';

const int discoveryPort = 5556;
const String discoveryQuery = 'RINGX_DISCOVER';
const String discoveryReplyPrefix = 'RINGX ';

/// PC side: answers discovery broadcasts with the live WebSocket URL.
class DiscoveryResponder {
  RawDatagramSocket? _sock;
  StreamSubscription? _sub;

  /// [wsPortProvider] must return the *bound* phone-link port (it may
  /// have shifted from the requested one when ports were busy).
  Future<(bool, String?)> start({required int Function() wsPortProvider}) async {
    if (_sock != null) return (true, null);
    final RawDatagramSocket sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4,
          discoveryPort,
          reuseAddress: true, reusePort: false);
    } on SocketException catch (e) {
      return (false, 'Discovery port $discoveryPort unavailable: '
          '${e.message}');
    }
    _sock = sock;
    _sub = sock.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      if (utf8.decode(dg.data, allowMalformed: true).trim() !=
          discoveryQuery) {
        return;
      }
      final port = wsPortProvider();
      if (port < 1) return;
      // Answer from every LAN IPv4 so multi-homed machines work.
      PhoneLink.lanIps().then((ips) {
        for (final ip in ips) {
          try {
            sock.send(utf8.encode('$discoveryReplyPrefix'
                'ws://$ip:$port'), dg.address, dg.port);
          } on SocketException catch (_) {
            // one interface down; the others still answer
          }
        }
      });
    });
    return (true, null);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    final sock = _sock;
    _sock = null;
    sock?.close();
  }
}

/// Phone side: broadcast once, return the first reply's `ws://` URL.
class DiscoveryFinder {
  /// Returns `ws://host:port` or null when no receiver answered in time.
  static Future<String?> find({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    RawDatagramSocket sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0,
          reuseAddress: true, reusePort: false);
    } on SocketException catch (_) {
      return null;
    }
    try {
      sock.broadcastEnabled = true;
      sock.send(utf8.encode(discoveryQuery),
          InternetAddress('255.255.255.255'), discoveryPort);
      final completer = Completer<String?>();
      final sub = sock.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = sock.receive();
        if (dg == null) return;
        final text = utf8.decode(dg.data, allowMalformed: true).trim();
        if (!text.startsWith(discoveryReplyPrefix)) return;
        if (!completer.isCompleted) {
          completer.complete(text.substring(discoveryReplyPrefix.length));
        }
      });
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });
      try {
        final reply = await completer.future;
        return reply;
      } finally {
        timer.cancel();
        await sub.cancel();
      }
    } finally {
      sock.close();
    }
  }
}
