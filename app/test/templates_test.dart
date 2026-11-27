import 'package:flutter_test/flutter_test.dart';
import 'package:ringx/core/templates.dart';

void main() {
  group('Template JSON roundtrip', () {
    test('presets survive encode -> decode', () {
      for (final t in Template.presets()) {
        final back = Template.fromJson(t.toJson());
        expect(back.name, t.name);
        expect(back.pages.length, t.pages.length);
        for (var i = 0; i < t.pages.length; i++) {
          expect(back.pages[i].name, t.pages[i].name);
          expect(back.pages[i].elements.length, t.pages[i].elements.length);
        }
      }
    });

    test('hostile json is clamped, not crashed', () {
      final t = Template.fromJson({
        'name': 'x' * 200,
        'pages': [
          {
            'name': 42, // wrong type -> 'Page'
            'elements': [
              {
                'kind': 'nonsense', // -> button
                'x': 99.0, // clamped
                'y': -5.0, // clamped
                'size': 0.01, // clamped to 0.12
                'label': 'L' * 50, // trimmed to 12
                'button': 500, // clamped to 125
                'stick': 'sideways', // -> left
              },
              null, // skipped
              'string', // skipped
            ],
          },
        ],
      });
      expect(t.name.length, 40);
      final e = t.pages.first.elements.single;
      expect(e.kind, ElKind.button);
      expect(e.x, 0.98);
      expect(e.y, 0.02);
      expect(e.size, 0.12);
      expect(e.label.length, 12);
      expect(e.button, 125);
      expect(e.stickMap, 'left');
    });

    test('tryParse rejects template-less payloads', () {
      expect(Template.tryParse({}), isNull);
      expect(Template.tryParse({'pages': []}), isNull);
      expect(Template.tryParse({'pages': 'nope'}), isNull);
      expect(
          Template.tryParse({
            'pages': [
              {'name': 'p', 'elements': []}
            ]
          }),
          isNotNull);
    });

    test('element caps: max pages, max elements per page', () {
      final pages = [
        for (var i = 0; i < 20; i++)
          {
            'name': 'p$i',
            'elements': [
              for (var j = 0; j < 40; j++) {'kind': 'button'},
            ],
          },
      ];
      final t = Template.fromJson({'name': 'big', 'pages': pages});
      expect(t.pages.length, Template.maxPages);
      expect(
          t.pages.first.elements.length, TplPage.maxElements);
    });
  });

  group('Presets are sane', () {
    test('racing has wheel + pedals on every page', () {
      for (final p in Template.racing().pages) {
        expect(p.elements.any((e) => e.kind == ElKind.wheel), isTrue);
        expect(p.elements.any((e) => e.kind == ElKind.pedalGas), isTrue);
        expect(p.elements.any((e) => e.kind == ElKind.pedalBrake), isTrue);
      }
    });

    test('gamepad has both sticks and buttons', () {
      final g = Template.gamepad().pages.first;
      expect(
          g.elements.where((e) => e.kind == ElKind.stick).length, 2);
      expect(
          g.elements.where((e) => e.kind == ElKind.button).length >= 5,
          isTrue);
    });

    test('no preset overlaps left and right sticks', () {
      for (final t in Template.presets()) {
        for (final p in t.pages) {
          final sticks = p.elements.where((e) => e.kind == ElKind.stick);
          for (final s in sticks) {
            expect(
                p.elements.where((e) =>
                    e.kind == ElKind.stick &&
                    e.stickMap == s.stickMap &&
                    !identical(e, s)),
                isEmpty,
                reason: 'two elements claim the same stick');
          }
        }
      }
    });
  });
}
