import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringx/core/phone_link.dart';
import 'package:ringx/core/phone_proto.dart';

Future<void> _ms(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('PhoneLink server', () {
    test('accepts ws on /ws and bare /, routes messages, one phone rule',
        () async {
      final link = PhoneLink(pageLoader: () async => utf8.encode('<!doctype html><p>phone'));
      final (ok, err) = await link.start(19870);
      expect(ok, isTrue, reason: err ?? 'bind failed');
      final port = link.port!;

      final received = <PhoneMsg>[];
      final connects = <bool>[];
      final sub = link.events.listen((m) => received.add(m));
      final csub = link.clientChanges.listen(connects.add);

      // --- phone.html-style client: /ws path ------------------------------
      final c1 = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      c1.add(const PhoneStateMsg(
              steer: 0.4, throttle: 0.25, brake: 0, buttons: {5})
          .encode());
      await _ms(200);
      expect(received.whereType<PhoneStateMsg>(), isNotEmpty);
      expect(link.connected, isTrue);
      expect(connects, contains(true));

      // Hello names the phone for the dashboard.
      c1.add(const HelloMsg(name: 'Test Phone').encode());
      await _ms(200);
      expect(link.phoneName, 'Test Phone');

      // Junk frames are dropped without killing the session (python parity).
      c1.add('not json at all');
      c1.add('{"t":"unknown-type","x":1}');
      await _ms(200);
      expect(link.connected, isTrue);

      // Stat push reaches the phone.
      final toPhone = <String>[];
      c1.listen((d) => toPhone.add(d as String), onDone: () {});
      link.send(const StatMsg(enabled: true));
      await _ms(200);
      expect(toPhone, isNotEmpty);
      expect(toPhone.first, contains('"t":"stat"'));
      expect(toPhone.first, contains('"enabled":true'));

      // Second phone while one is connected: upgraded then closed (1008).
      final c2 = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      final c2Closed = Completer<void>();
      c2.listen((_) {}, onDone: () => c2Closed.complete());
      await c2Closed.future.timeout(const Duration(seconds: 5));
      expect(link.connected, isTrue); // c1 still owns the link

      // --- QR-style client: no path at all --------------------------------
      await c1.close();
      await _ms(200);
      expect(link.connected, isFalse);
      expect(connects, contains(false));

      final c3 = await WebSocket.connect('ws://127.0.0.1:$port');
      final nBefore = received.length;
      c3.add(const PhoneStateMsg(
              steer: -0.7, throttle: 0, brake: 1, buttons: {})
          .encode());
      await _ms(200);
      expect(received.length, greaterThan(nBefore));
      expect(link.connected, isTrue);

      // --- plain GET / serves the fallback page ---------------------------
      final http = await HttpClient().getUrl(
          Uri.parse('http://127.0.0.1:$port/'));
      final resp = await http.close();
      expect(resp.statusCode, 200);
      final body = await resp.transform(utf8.decoder).join();
      expect(body, contains('phone'));

      await sub.cancel();
      await csub.cancel();
      await c3.close();
      await link.stop();
      expect(link.running, isFalse);
    });

    test('stop closes an active phone cleanly', () async {
      final link = PhoneLink();
      final (ok, _) = await link.start(19871);
      expect(ok, isTrue);
      final c = await WebSocket.connect('ws://127.0.0.1:${link.port}/ws');
      await _ms(100);
      expect(link.connected, isTrue);
      await link.stop();
      final closed = Completer<void>();
      c.listen((_) {}, onDone: () => closed.complete());
      await closed.future.timeout(const Duration(seconds: 5));
    });
  });
}
