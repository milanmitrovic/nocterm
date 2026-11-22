import 'package:nocterm/src/keyboard/input_event.dart';
import 'package:nocterm/src/keyboard/input_parser.dart';
import 'package:test/test.dart';

/// Feed a string of escape bytes to a fresh parser and drain every event.
List<InputEvent> parseAll(String bytes) {
  final parser = InputParser();
  parser.addBytes(bytes.codeUnits);
  final events = <InputEvent>[];
  InputEvent? event;
  while ((event = parser.parseNext()) != null) {
    events.add(event!);
  }
  return events;
}

/// Replies to the graphics probe (kitty a=q, CSI 16 t, DA1) must reach the
/// binding as TerminalReplyInputEvents — never as keystrokes, and never
/// stalling the parser.
void main() {
  group('graphics probe replies', () {
    for (final (name, reply) in [
      ('kitty graphics OK', '\x1b_Gi=31;OK\x1b\\'),
      ('kitty graphics error',
          '\x1b_Gi=31;ENOTSUPPORTED:graphics not supported\x1b\\'),
      ('DA1', '\x1b[?62;22c'),
      ('DA1 with sixel', '\x1b[?64;1;4;6;22c'),
      ('cell size (CSI 16 t)', '\x1b[6;20;10t'),
    ]) {
      test('a $name reply is one terminal reply, verbatim', () {
        final events = parseAll(reply);

        expect(events, hasLength(1), reason: '$events');
        expect((events.single as TerminalReplyInputEvent).reply, reply);
      });
    }

    test('a whole probe answer in one read gives three replies, no keys', () {
      final events = parseAll('\x1b_Gi=31;OK\x1b\\\x1b[6;20;10t\x1b[?62;22c');

      expect(events.whereType<KeyboardInputEvent>(), isEmpty);
      expect(events.map((e) => (e as TerminalReplyInputEvent).reply), [
        '\x1b_Gi=31;OK\x1b\\',
        '\x1b[6;20;10t',
        '\x1b[?62;22c',
      ]);
    });

    test('a key typed in the same read after a reply still parses', () {
      final events = parseAll('\x1b_Gi=31;OK\x1b\\x');

      expect(events, hasLength(2));
      expect(events[0], isA<TerminalReplyInputEvent>());
      expect((events[1] as KeyboardInputEvent).event.character, 'x');
    });

    test('a kitty reply split across reads is buffered, not leaked', () {
      final parser = InputParser();
      parser.addBytes('\x1b_Gi=31;O'.codeUnits);
      expect(parser.parseNext(), isNull, reason: 'incomplete — must wait');

      parser.addBytes('K\x1b\\'.codeUnits);
      final event = parser.parseNext();
      expect((event as TerminalReplyInputEvent).reply, '\x1b_Gi=31;OK\x1b\\');
      expect(parser.parseNext(), isNull);
    });

    test('a DA1 reply split across reads is buffered, not leaked', () {
      final parser = InputParser();
      parser.addBytes('\x1b[?62;'.codeUnits);
      expect(parser.parseNext(), isNull, reason: 'incomplete — must wait');

      parser.addBytes('22c'.codeUnits);
      final event = parser.parseNext();
      expect((event as TerminalReplyInputEvent).reply, '\x1b[?62;22c');
    });

    test('Alt+_ alone is still Escape then underscore', () {
      // Only ESC _ G (a kitty graphics reply) is claimed as an APC reply.
      final events = parseAll('\x1b_');

      expect(events.whereType<TerminalReplyInputEvent>(), isEmpty);
    });
  });
}
