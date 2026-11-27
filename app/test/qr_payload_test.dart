import 'package:flutter_test/flutter_test.dart';
import 'package:ringx/core/qr_payload.dart';

void main() {
  group('QrPayload', () {
    test('build + hostPort roundtrip', () {
      final url = QrPayload.build('192.168.1.5', 9870);
      expect(url, 'ws://192.168.1.5:9870');
      final hp = QrPayload.hostPort(url);
      expect(hp, ('192.168.1.5', 9870));
    });

    test('parses ws url with /ws path (web-page QR)', () {
      expect(QrPayload.tryParse('ws://10.0.0.2:9870/ws'),
          'ws://10.0.0.2:9870');
    });

    test('parses http page url as ws (scheme upgrade)', () {
      expect(QrPayload.tryParse('http://10.0.0.2:9870/'),
          'ws://10.0.0.2:9870');
      expect(QrPayload.tryParse('https://example.com:443'),
          'ws://example.com:443');
    });

    test('whitespace tolerated', () {
      expect(QrPayload.tryParse('  ws://1.2.3.4:5555  '),
          'ws://1.2.3.4:5555');
    });

    test('junk rejected', () {
      expect(QrPayload.tryParse(''), isNull);
      expect(QrPayload.tryParse('hello world'), isNull);
      expect(QrPayload.tryParse('ws://'), isNull);
      expect(QrPayload.tryParse('ws://host:0'), isNull);
      expect(QrPayload.tryParse('ws://host:99999'), isNull);
      expect(QrPayload.tryParse('ws://:1234'), isNull);
      expect(QrPayload.tryParse('x' * 300), isNull);
    });

    test('no port defaults to 80', () {
      expect(QrPayload.tryParse('ws://example.com'), 'ws://example.com:80');
    });
  });
}
