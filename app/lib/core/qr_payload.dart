/// QR pairing payload: the PC shows a QR with its WebSocket URL, the phone
/// scans it and connects. Pure string build/parse — unit tested.
library;

class QrPayload {
  const QrPayload._();

  /// Builds the QR payload shown by the receiver.
  static String build(String host, int port) => 'ws://$host:$port';

  /// Parses a scanned string into a `ws://host:port` URL.
  ///
  /// Accepts `ws://` and `http(s)://` (a phone that scanned the receiver's
  /// *web* URL gets the matching WebSocket URL), an optional trailing `/ws`
  /// path, and whitespace around the code. Returns null when unusable.
  static String? tryParse(String raw) {
    var s = raw.trim();
    if (s.isEmpty || s.length > 200) return null;
    if (s.startsWith('http://')) {
      s = 'ws://${s.substring(7)}';
    } else if (s.startsWith('https://')) {
      s = 'ws://${s.substring(8)}';
    }
    if (!s.startsWith('ws://')) return null;
    final rest = s.substring(5);
    // Strip an optional /ws (or /) path; QR codes sometimes encode the page.
    final slash = rest.indexOf('/');
    final hostPort = slash < 0 ? rest : rest.substring(0, slash);
    if (hostPort.isEmpty) return null;
    final colon = hostPort.lastIndexOf(':');
    String host;
    int port;
    if (colon >= 0) {
      host = hostPort.substring(0, colon);
      port = int.tryParse(hostPort.substring(colon + 1)) ?? 80;
    } else {
      host = hostPort;
      port = 80;
    }
    if (host.isEmpty) return null;
    if (port < 1 || port > 65535) return null;
    return 'ws://$host:$port';
  }

  /// `(host, port)` of a URL produced by [tryParse], or null.
  static (String, int)? hostPort(String url) {
    final parsed = tryParse(url);
    if (parsed == null) return null;
    final rest = parsed.substring(5);
    final colon = rest.lastIndexOf(':');
    return (rest.substring(0, colon), int.parse(rest.substring(colon + 1)));
  }
}
