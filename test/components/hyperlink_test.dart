import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

import '../foundation/signal_backend_fake.dart';

void main() {
  group('TextStyle.hyperlink', () {
    test('participates in equality and hashCode', () {
      const plain = TextStyle(color: Colors.red);
      const linked = TextStyle(color: Colors.red, hyperlink: 'https://a.io');
      const linked2 = TextStyle(color: Colors.red, hyperlink: 'https://a.io');

      expect(plain, isNot(equals(linked)));
      expect(linked, equals(linked2));
      expect(linked.hashCode, equals(linked2.hashCode));
    });

    test('survives copyWith and merge', () {
      const linked = TextStyle(hyperlink: 'https://a.io');

      expect(linked.copyWith(color: Colors.blue).hyperlink, 'https://a.io');
      expect(
        const TextStyle(color: Colors.red).merge(linked).hyperlink,
        'https://a.io',
      );
      // Merging a link-less style on top keeps the link (merge uses ??).
      expect(
        linked.merge(const TextStyle(color: Colors.red)).hyperlink,
        'https://a.io',
      );
    });

    test('flows through TextSpan into rendered cells', () async {
      await testNocterm(
        'hyperlink cells',
        (tester) async {
          await tester.pumpComponent(
            RichText(
              text: const TextSpan(
                children: [
                  TextSpan(text: 'see '),
                  TextSpan(
                    text: 'link',
                    style: TextStyle(hyperlink: 'https://example.com'),
                  ),
                  TextSpan(text: ' here'),
                ],
              ),
            ),
          );

          // 'see ' — no link.
          expect(
            tester.terminalState.getCellAt(0, 0)!.style.hyperlink,
            isNull,
          );
          // 'link' — cells 4..7 carry the URL.
          for (var x = 4; x < 8; x++) {
            expect(
              tester.terminalState.getCellAt(x, 0)!.style.hyperlink,
              'https://example.com',
              reason: 'cell $x should carry the hyperlink',
            );
          }
          // ' here' — closed again.
          expect(
            tester.terminalState.getCellAt(8, 0)!.style.hyperlink,
            isNull,
          );
        },
      );
    });

    test('parent span hyperlink is inherited by children', () async {
      await testNocterm(
        'hyperlink inheritance',
        (tester) async {
          await tester.pumpComponent(
            RichText(
              text: const TextSpan(
                style: TextStyle(hyperlink: 'https://parent.io'),
                children: [
                  TextSpan(text: 'ab'),
                  TextSpan(
                    text: 'cd',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          );

          for (var x = 0; x < 4; x++) {
            expect(
              tester.terminalState.getCellAt(x, 0)!.style.hyperlink,
              'https://parent.io',
              reason: 'cell $x should inherit the parent hyperlink',
            );
          }
        },
      );
    });
  });

  group('Terminal.writeHyperlink', () {
    test('emits OSC 8 open and close sequences', () {
      final backend = FakeSignalBackend();
      final terminal = Terminal(backend);
      terminal.writeHyperlink('https://example.com');
      terminal.writeHyperlink(null);
      terminal.flush();
      expect(
        backend.output.toString(),
        '\x1b]8;;https://example.com\x1b\\\x1b]8;;\x1b\\',
      );
    });
  });
}
