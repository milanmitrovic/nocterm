// `isEmpty` is a matcher in both packages; take the test package's.
import 'package:nocterm/nocterm.dart' hide isEmpty;
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

void main() {
  group('DEC 2031 colour-scheme reports', () {
    test('CSI ? 997 ; 1 n decodes as dark', () {
      final events = parseAll('\x1b[?997;1n');

      expect(events, hasLength(1));
      final event = events.single as ColorSchemeInputEvent;
      expect(event.notice.brightness, Brightness.dark);
      expect(event.notice.reportedValue, 1);
    });

    test('CSI ? 997 ; 2 n decodes as light', () {
      final events = parseAll('\x1b[?997;2n');

      expect(events, hasLength(1));
      final event = events.single as ColorSchemeInputEvent;
      expect(event.notice.brightness, Brightness.light);
      expect(event.notice.reportedValue, 2);
    });

    test('an unknown payload still reports a change, with no brightness', () {
      // Terminals disagree about this parameter; a notice we cannot decode
      // is still "the colours changed, go re-read them".
      final events = parseAll('\x1b[?997;7n');

      expect(events, hasLength(1));
      final event = events.single as ColorSchemeInputEvent;
      expect(event.notice.brightness, isNull);
      expect(event.notice.reportedValue, 7);
    });

    test('the report never leaks as keystrokes', () {
      // The whole point of claiming it in the parser: no KeyboardInputEvent,
      // and in particular no stray Escape / '?' / digits reaching the app.
      final events = parseAll('\x1b[?997;1n');

      expect(events.whereType<KeyboardInputEvent>(), isEmpty);
    });

    test('a keypress arriving in the same read still parses', () {
      // A notification can be flushed into the same stdin read as real
      // input; the parser must consume exactly the report and no more.
      final events = parseAll('\x1b[?997;2na');

      expect(events, hasLength(2));
      expect(events[0], isA<ColorSchemeInputEvent>());
      final key = events[1] as KeyboardInputEvent;
      expect(key.event.character, 'a');
    });

    test('a report split across two reads is buffered, not dropped', () {
      final parser = InputParser();
      parser.addBytes('\x1b[?997;'.codeUnits);
      expect(parser.parseNext(), isNull, reason: 'incomplete — must wait');

      parser.addBytes('1n'.codeUnits);
      final event = parser.parseNext();
      expect(event, isA<ColorSchemeInputEvent>());
      expect((event as ColorSchemeInputEvent).notice.brightness,
          Brightness.dark);
    });

    test('a multi-digit payload is read in full', () {
      final events = parseAll('\x1b[?997;12n');

      expect((events.single as ColorSchemeInputEvent).notice.reportedValue, 12);
    });

    test('other CSI ? replies are not mistaken for colour reports', () {
      // A DECRPM report and a DA reply share the ESC [ ? prefix. They must
      // fall through to the ordinary CSI handling (consumed, not emitted),
      // never decoded as a colour scheme.
      for (final sequence in ['\x1b[?2031;1\$y', '\x1b[?62;1;6c']) {
        final events = parseAll(sequence);
        expect(events.whereType<ColorSchemeInputEvent>(), isEmpty,
            reason: sequence);
      }
    });

    test('mode 996 (the query we send) is not decoded as a report', () {
      // Only 997 is a report. Echoing the query back must not become one.
      final events = parseAll('\x1b[?996n');

      expect(events.whereType<ColorSchemeInputEvent>(), isEmpty);
    });
  });

  group('ColorSchemeNotice', () {
    test('decodes 1/2 and keeps anything else verbatim', () {
      expect(ColorSchemeNotice.fromReportedValue(1).brightness,
          Brightness.dark);
      expect(ColorSchemeNotice.fromReportedValue(2).brightness,
          Brightness.light);
      expect(ColorSchemeNotice.fromReportedValue(0).brightness, isNull);
      expect(ColorSchemeNotice.fromReportedValue(0).reportedValue, 0);
    });

    test('is a value type', () {
      expect(ColorSchemeNotice.fromReportedValue(1),
          ColorSchemeNotice.fromReportedValue(1));
      expect(ColorSchemeNotice.fromReportedValue(1),
          isNot(ColorSchemeNotice.fromReportedValue(2)));
    });
  });

  group('escape codes', () {
    test('mode 2031 is enabled/disabled and 996 queries', () {
      expect(EscapeCodes.enable.colorSchemeUpdates, '\x1B[?2031h');
      expect(EscapeCodes.disable.colorSchemeUpdates, '\x1B[?2031l');
      expect(EscapeCodes.queryColorScheme, '\x1b[?996n');
    });

    test('mode 2031 is NOT in the unconditional enable/disable lists', () {
      // Those lists are written to every app at startup and teardown;
      // 2031 is opt-in and must stay out of them.
      expect(EscapeCodes.enable.values,
          isNot(contains(EscapeCodes.enable.colorSchemeUpdates)));
      expect(EscapeCodes.disable.values,
          isNot(contains(EscapeCodes.disable.colorSchemeUpdates)));
    });
  });
}
