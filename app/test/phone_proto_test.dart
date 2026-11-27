import 'package:flutter_test/flutter_test.dart';
import 'package:ringx/core/phone_proto.dart';
import 'package:ringx/core/templates.dart';

void main() {
  group('PhoneMsg.tryDecode', () {
    test('decodes a state frame and clamps values', () {
      final msg = PhoneMsg.tryDecode(
          '{"t":"state","s":2.5,"th":-1,"br":0.7,"bt":[3,1,3,999,0,"x"]}');
      expect(msg, isA<PhoneStateMsg>());
      final s = msg! as PhoneStateMsg;
      expect(s.steer, 1.0); // clamped
      expect(s.throttle, 0.0); // clamped
      expect(s.brake, 0.7);
      // 0 dropped (below 1), 999 dropped (above 128), dup 3 collapsed.
      expect(s.buttons, {1, 3});
    });

    test('toggle and stat frames', () {
      expect(PhoneMsg.tryDecode('{"t":"toggle"}'), isA<ToggleMsg>());
      final stat = PhoneMsg.tryDecode('{"t":"stat","enabled":true}');
      expect(stat, isA<StatMsg>());
      expect((stat as StatMsg).enabled, isTrue);
      // Non-bool enabled is dropped like junk.
      expect(PhoneMsg.tryDecode('{"t":"stat","enabled":"yes"}'), isNull);
    });

    test('hello frame with long name', () {
      final msg =
          PhoneMsg.tryDecode('{"t":"hello","name":"${'x' * 90}"}');
      final h = msg! as HelloMsg;
      expect(h.name.length, 40);
      expect(PhoneMsg.tryDecode('{"t":"hello"}'), isNull);
    });

    test('template frame passes raw json through', () {
      final msg = PhoneMsg.tryDecode(
          '{"t":"tpl","tpl":{"name":"Racing","pages":[{"name":"P1","elements":[]}]}}');
      final t = msg! as TemplateMsg;
      final parsed = Template.tryParse(t.template);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'Racing');
      expect(parsed.pages.first.name, 'P1');
    });

    test('junk is dropped silently (python parity)', () {
      expect(PhoneMsg.tryDecode('not json'), isNull);
      expect(PhoneMsg.tryDecode('[1,2,3]'), isNull);
      expect(PhoneMsg.tryDecode('"string"'), isNull);
      expect(PhoneMsg.tryDecode('{"t":"nope"}'), isNull);
      expect(PhoneMsg.tryDecode('{"t":"state"}'), isA<PhoneStateMsg>());
    });
  });

  group('PhoneStateMsg roundtrip', () {
    test('encode -> decode is lossless', () {
      const msg = PhoneStateMsg(
          steer: -0.42, throttle: 0.5, brake: 1.0, buttons: {7, 2});
      final back = PhoneMsg.tryDecode(msg.encode())! as PhoneStateMsg;
      expect(back.steer, msg.steer);
      expect(back.throttle, msg.throttle);
      expect(back.brake, msg.brake);
      expect(back.buttons, msg.buttons);
    });

    test('infinite values decode clamped (1e999 overflow)', () {
      // 1e999 is valid JSON that parses to a double infinity.
      final msg = PhoneMsg.tryDecode(
          '{"t":"state","s":1e999,"th":-1e999,"br":1e999}');
      final s = msg! as PhoneStateMsg;
      expect(s.steer, 1.0);
      expect(s.throttle, 0.0);
      expect(s.brake, 1.0);
    });
  });
}
