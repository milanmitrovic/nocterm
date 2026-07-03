import 'package:nocterm/src/components/text_field/cursor_movement.dart';
import 'package:nocterm/src/text/text_layout_engine.dart';
import 'package:test/test.dart';

void main() {
  group('CursorMovement', () {
    test('handles Unicode characters correctly in horizontal movement', () {
      final text = 'Hello 世界 🌍';

      // Move right from start
      var offset = CursorMovement.moveCursorHorizontally(
        text: text,
        currentOffset: 0,
        direction: 1,
      );
      expect(offset, 1); // H -> e

      // Move to emoji
      offset = CursorMovement.moveCursorHorizontally(
        text: text,
        currentOffset: 10,
        direction: 1,
      );
      expect(offset,
          11); // Space before emoji -> emoji (emoji is 1 grapheme cluster)
    });

    test('handles wrapped lines in vertical movement', () {
      final text = 'This is a long line that should wrap when displayed';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: true,
          maxWidth: 20, // Force wrapping
        ),
      );

      // Start at position 10 ('l' in 'long')
      final newOffset = CursorMovement.moveCursorVertically(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 10,
        direction: 1, // Move down
        targetVisualColumn: 10,
      );

      // Should move to the next wrapped line
      expect(newOffset, greaterThan(10));
    });

    test('maintains visual column when moving vertically', () {
      final text = 'Line one\nA much longer second line\nShort';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Start at position 20 (somewhere in second line)
      var offset = CursorMovement.moveCursorVertically(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 20,
        direction: -1, // Move up
        targetVisualColumn: 11,
      );

      // Should try to maintain column position
      expect(offset, lessThan(20));
      expect(offset, lessThanOrEqualTo(8)); // End of first line
    });

    test('moves by word correctly', () {
      final text = 'Hello world, this is a test!';

      // Move forward by word from start
      var offset = CursorMovement.moveCursorByWord(
        text: text,
        currentOffset: 0,
        direction: 1,
      );
      expect(offset, 6); // After 'Hello '

      // Move backward by word
      offset = CursorMovement.moveCursorByWord(
        text: text,
        currentOffset: 12,
        direction: -1,
      );
      expect(offset, 6); // Start of 'world'
    });

    test('finds correct cursor position in laid out text', () {
      final text = 'First line\nSecond line\nThird';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Position at start of second line
      final pos = CursorMovement.getCursorPosition(
        layoutResult: layoutResult,
        text: text,
        cursorOffset: 11, // Just after '\n'
      );

      // The layout engine removes newlines from the lines, so we need to track them
      expect(pos.line, 1); // Second line (0-indexed)
      expect(pos.column, 0); // Start of line
      expect(pos.visualColumn, 0);
    });

    test('handles double-width characters in cursor position', () {
      final text = '你好世界'; // Chinese characters (double-width)
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Position after first character
      // Note: In Dart strings, '你' is 1 character but takes 2 visual columns
      final pos = CursorMovement.getCursorPosition(
        layoutResult: layoutResult,
        text: text,
        cursorOffset: 1, // After '你' (1 character in Dart string)
      );

      expect(pos.visualColumn, 2); // Double-width character
    });

    test('handles line start and end movement', () {
      final text = 'First line\nSecond longer line\nThird';
      final layoutResult = TextLayoutEngine.layout(
        text,
        TextLayoutConfig(
          softWrap: false,
          maxWidth: 100,
        ),
      );

      // Move to line start from middle of second line
      var offset = CursorMovement.moveCursorToLineStart(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 20, // Somewhere in second line
      );
      expect(offset, 11); // Start of second line

      // Move to line end
      offset = CursorMovement.moveCursorToLineEnd(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 20,
      );
      expect(offset, 29); // End of second line
    });
  });

  group('CursorMovement with wrap-dropped spaces', () {
    // 'this is a test' at maxWidth 7 lays out as ['this is', 'a test'].
    // The space at offset 7 straddles the wrap boundary and is dropped from
    // the layout lines, so layout line 1 starts at text offset 8 — not 7.
    // Offset mapping must account for the dropped character or every
    // position after the wrap is off by one.
    final text = 'this is a test';
    final layoutResult = TextLayoutEngine.layout(
      text,
      TextLayoutConfig(softWrap: true, maxWidth: 7),
    );

    test('layout drops the boundary space (precondition)', () {
      expect(layoutResult.lines, ['this is', 'a test']);
    });

    test('cursor at start of continuation word maps to column 0', () {
      // Offset 8 is the 'a' — the first character of layout line 1.
      final pos = CursorMovement.getCursorPosition(
        layoutResult: layoutResult,
        text: text,
        cursorOffset: 8,
      );
      expect(pos.line, 1);
      expect(pos.column, 0);
      expect(pos.visualColumn, 0);
      expect(pos.lineStartOffset, 8);
    });

    test('cursor on the dropped space itself stays at end of first line', () {
      // Offset 7 is the dropped space. It belongs to neither layout line;
      // visually the cursor sits after 'this is'.
      final pos = CursorMovement.getCursorPosition(
        layoutResult: layoutResult,
        text: text,
        cursorOffset: 7,
      );
      expect(pos.line, 0);
      expect(pos.column, 7);
    });

    test('vertical movement across the dropped space keeps the column', () {
      // From 'i' in 'this' (offset 2, visual column 2) moving down should
      // land on 't' of 'test' — offset 8 + 2 = 10 — not offset 9.
      final newOffset = CursorMovement.moveCursorVertically(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 2,
        direction: 1,
        targetVisualColumn: 2,
      );
      expect(newOffset, 10);
    });

    test('line end on continuation line reaches the last character', () {
      // Line 1 is 'a test' spanning offsets [8, 14).
      final offset = CursorMovement.moveCursorToLineEnd(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 10,
      );
      expect(offset, 14);
    });

    test('line start on continuation line lands after the dropped space', () {
      final offset = CursorMovement.moveCursorToLineStart(
        layoutResult: layoutResult,
        text: text,
        currentOffset: 10,
      );
      expect(offset, 8);
    });

    test('mapping stays correct after a newline preceding the wrap', () {
      // Explicit newline followed by a paragraph that wraps with a dropped
      // space: both kinds of "invisible" characters must be accounted for.
      final text2 = 'ab\nthis is a test';
      final layout2 = TextLayoutEngine.layout(
        text2,
        TextLayoutConfig(softWrap: true, maxWidth: 7),
      );
      expect(layout2.lines, ['ab', 'this is', 'a test']);

      // Offset 11 is the 'a' of 'a test' (3 for 'ab\n' + 8).
      final pos = CursorMovement.getCursorPosition(
        layoutResult: layout2,
        text: text2,
        cursorOffset: 11,
      );
      expect(pos.line, 2);
      expect(pos.column, 0);
    });

    test('consecutive spaces at the boundary drop only the first', () {
      // 'hello  world' (two spaces) at maxWidth 5: the first space is
      // dropped at the wrap, the second becomes its own layout line.
      final text2 = 'hello  world';
      final layout2 = TextLayoutEngine.layout(
        text2,
        TextLayoutConfig(softWrap: true, maxWidth: 5),
      );
      expect(layout2.lines, ['hello', ' ', 'world']);

      // Offset 7 = start of 'world'... no: 'hello'(0-5), spaces at 5,6,
      // 'world' starts at 7.
      final pos = CursorMovement.getCursorPosition(
        layoutResult: layout2,
        text: text2,
        cursorOffset: 7,
      );
      expect(pos.line, 2);
      expect(pos.column, 0);
    });
  });
}
