import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/utils/terminal_color_support.dart';
import 'package:test/test.dart';

void main() {
  group('Color.ansi SGR codes', () {
    tearDown(() => setSupportsTruecolorForTesting(null));

    test('standard slots 0-7 emit SGR 30-37 / 40-47', () {
      for (var i = 0; i < 8; i++) {
        expect(Color.ansi(i).toAnsi(), '\x1b[${30 + i}m', reason: 'fg $i');
        expect(Color.ansi(i).toAnsi(background: true), '\x1b[${40 + i}m',
            reason: 'bg $i');
      }
    });

    test('bright slots 8-15 emit SGR 90-97 / 100-107', () {
      for (var i = 8; i < 16; i++) {
        expect(Color.ansi(i).toAnsi(), '\x1b[${90 + i - 8}m', reason: 'fg $i');
        expect(Color.ansi(i).toAnsi(background: true), '\x1b[${100 + i - 8}m',
            reason: 'bg $i');
      }
    });

    test('the codes are the same whether or not truecolor is supported', () {
      // A palette slot is not a shade: it must never be emitted as 38;2;…
      // (which pins the shade) nor quantized through the 256-colour ramp.
      for (final truecolor in [true, false]) {
        setSupportsTruecolorForTesting(truecolor);
        expect(Color.ansi(4).toAnsi(), '\x1b[34m', reason: 'tc=$truecolor');
        expect(Color.ansi(12).toAnsi(background: true), '\x1b[104m',
            reason: 'tc=$truecolor');
      }
    });

    test('Color.defaultColor still emits SGR 39/49', () {
      // The reset codes are a different thing from slot 0 and must not have
      // moved.
      expect(Color.defaultColor.toAnsi(), '\x1b[39m');
      expect(Color.defaultColor.toAnsi(background: true), '\x1b[49m');
      expect(Color.ansi(0).toAnsi(), isNot('\x1b[39m'));
    });

    test('it reaches the wire through TextStyle', () {
      setSupportsTruecolorForTesting(true);
      final ansi = TextStyle(
        color: Color.ansi(3),
        backgroundColor: Color.ansi(9),
      ).toAnsi();

      expect(ansi, contains('\x1b[33m'));
      expect(ansi, contains('\x1b[101m'));
    });
  });

  group('Color.ansi semantics', () {
    test('it is an opaque, non-default set colour', () {
      final color = Color.ansi(5);

      expect(color.isDefault, isFalse,
          reason: 'it paints; it does not reset the terminal');
      expect(color.isAnsiIndexed, isTrue);
      expect(color.ansiIndex, 5);
      expect(color.alpha, 255);
      expect(color.a, 1.0);
    });

    test('an RGB colour carries no index', () {
      expect(const Color.fromRGB(1, 2, 3).ansiIndex, isNull);
      expect(const Color.fromRGB(1, 2, 3).isAnsiIndexed, isFalse);
      expect(Color.defaultColor.ansiIndex, isNull);
    });

    test('index is part of identity', () {
      expect(Color.ansi(4), Color.ansi(4));
      expect(Color.ansi(4).hashCode, Color.ansi(4).hashCode);
      expect(Color.ansi(4), isNot(Color.ansi(12)));
      // Same approximate RGB, different meaning: one follows the user's
      // palette, the other is a fixed shade.
      expect(Color.ansi(4), isNot(const Color.fromRGB(0, 0, 238)));
    });

    test('instances are canonical', () {
      expect(Color.ansi(7), same(Color.ansi(7)));
    });

    test('out-of-range indices throw', () {
      expect(() => Color.ansi(-1), throwsRangeError);
      expect(() => Color.ansi(16), throwsRangeError);
    });

    test('toString names the slot', () {
      expect(Color.ansi(10).toString(), 'Color.ansi(10)');
    });
  });

  group('Color.ansi blending', () {
    test('an opaque indexed foreground passes through alphaBlend intact', () {
      final blended =
          Color.alphaBlend(Color.ansi(2), const Color.fromRGB(10, 20, 30));

      expect(blended, same(Color.ansi(2)),
          reason: 'opaque means nothing to blend — the slot must survive');
    });

    test('withAlpha(255) keeps the slot; a translucent alpha drops it', () {
      expect(Color.ansi(6).withAlpha(255), same(Color.ansi(6)));

      final faded = Color.ansi(6).withOpacity(0.5);
      expect(faded.ansiIndex, isNull,
          reason: 'a translucent colour has to become a shade');
      expect(faded.alpha, 128);
      // It falls back to the documented approximation, not to black.
      expect(faded.red, Color.ansi(6).red);
    });

    test('it is blended under a translucent colour like any other', () {
      final blended = Color.alphaBlend(
        const Color.fromARGB(0, 1, 2, 3),
        Color.ansi(15),
      );

      expect(blended, same(Color.ansi(15)),
          reason: 'a fully transparent foreground yields the background');
    });

    test('an indexed background survives a style that names none', () async {
      // The canvas preserves an existing background when the incoming style
      // has no backgroundColor. An indexed background is a SET colour and
      // must be preserved exactly like an RGB one.
      await testNocterm('indexed background preserved', (tester) async {
        await tester.pumpComponent(
          Container(
            width: 6,
            height: 1,
            decoration: BoxDecoration(color: Color.ansi(4)),
            child: Text('hi', style: TextStyle(color: Color.ansi(15))),
          ),
        );

        final cell = tester.terminalState.getCellAt(0, 0)!;
        expect(cell.char, 'h');
        expect(cell.style.color, Color.ansi(15));
        expect(cell.style.backgroundColor, Color.ansi(4),
            reason: 'the container background must not have been dropped');

        final padding = tester.terminalState.getCellAt(4, 0)!;
        expect(padding.style.backgroundColor, Color.ansi(4));
      });
    });
  });
}
