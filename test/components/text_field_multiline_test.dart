import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('TextField Multi-line', () {
    test('cursor position is correct with wrapped lines', () async {
      await testNocterm(
        'wrapped lines cursor',
        (tester) async {
          final controller = TextEditingController(text: '');

          await tester.pumpComponent(
            TextField(
              controller: controller,
              width: 30,
              maxLines: 5,
              focused: true,
              decoration: const InputDecoration(
                border: BoxBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 1),
              ),
              showCursor: true,
              cursorBlinkRate: null, // Static cursor
            ),
          );

          // Width = 30, minus 2 for border, minus 2 for padding = 26 available
          // Add text that will wrap
          controller.text =
              'This is a long line that will definitely wrap to the next line';
          controller.selection =
              TextSelection.collapsed(offset: controller.text.length);
          await tester.pump();

          // The cursor should be at the end of the wrapped text
          // Not beyond the border
          expect(tester.terminalState, isNotNull);
          print('Text with wrapped lines:');
          print(tester.terminalState.toString());
        },
        debugPrintAfterPump: true,
      );
    });

    test('cursor moves correctly across wrapped lines', () async {
      await testNocterm(
        'cursor movement across wrapped lines',
        (tester) async {
          final controller = TextEditingController(text: '');

          await tester.pumpComponent(
            TextField(
              controller: controller,
              width: 20,
              maxLines: 4,
              focused: true,
              decoration: const InputDecoration(
                border: BoxBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 1),
              ),
              showCursor: true,
              cursorBlinkRate: null,
            ),
          );

          // Width = 20, minus 2 for border, minus 2 for padding = 16 available
          // Each line can fit 16 characters
          controller.text = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'; // 26 chars, will wrap

          // Test cursor at various positions
          controller.selection = TextSelection.collapsed(offset: 0);
          await tester.pump();
          print('\nCursor at position 0:');

          controller.selection = TextSelection.collapsed(offset: 16);
          await tester.pump();
          print('\nCursor at position 16 (should be start of line 2):');

          controller.selection = TextSelection.collapsed(offset: 26);
          await tester.pump();
          print('\nCursor at position 26 (end of text):');

          expect(tester.terminalState, isNotNull);
        },
        debugPrintAfterPump: true,
      );
    });

    test('Alt+Enter keeps inserting newlines past maxLines', () async {
      // Regression: TextField._insertText used to silently drop a '\n'
      // insertion once the content reached maxLines lines. With viewport
      // scrolling now in place, maxLines bounds the visible window, not
      // the content — newline insertion must keep working.
      await testNocterm(
        'newline past maxLines',
        (tester) async {
          // Pre-fill 5 lines so we're already at maxLines=5.
          final controller = TextEditingController(text: 'a\nb\nc\nd\ne');
          controller.selection =
              TextSelection.collapsed(offset: controller.text.length);

          await tester.pumpComponent(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 20,
                height: 5,
                child: TextField(
                  controller: controller,
                  maxLines: 5,
                  focused: true,
                  showCursor: true,
                  cursorBlinkRate: null,
                ),
              ),
            ),
          );

          // Send Alt+Enter — should insert a newline even though we're
          // already at maxLines.
          await tester.sendKeyEvent(const KeyboardEvent(
            logicalKey: LogicalKey.enter,
            modifiers: ModifierKeys(alt: true),
          ));

          expect(controller.text, 'a\nb\nc\nd\ne\n');

          // Type a character on the new line — it should land there.
          await tester.enterText('f');
          expect(controller.text, 'a\nb\nc\nd\ne\nf');
        },
      );
    });

    test('cursor stays visible when content exceeds maxLines', () async {
      // Regression: previously TextLayoutEngine truncated to the FIRST
      // maxLines wrapped lines and the cursor was clamped to the last
      // visible row, so typing past the bottom of the field looked frozen.
      // The fix scrolls the viewport so the cursor row stays in view.
      await testNocterm(
        'cursor visible past maxLines',
        (tester) async {
          final controller = TextEditingController(
            text: '1\n2\n3\n4\n5\n6\n7\n8',
          );
          controller.selection =
              TextSelection.collapsed(offset: controller.text.length);

          // Wrap in Align so the field gets loose constraints (not the
          // tight terminal-sized constraints from the test binding) and
          // the maxLines bound is respected.
          await tester.pumpComponent(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 20,
                height: 5,
                child: TextField(
                  controller: controller,
                  maxLines: 5,
                  focused: true,
                  showCursor: true,
                  cursorBlinkRate: null,
                ),
              ),
            ),
          );

          // The viewport should have scrolled so the bottom of the text is
          // visible. '8' is the last typed line; '1' and '2' are above the
          // scroll window (8 lines total, 5 visible → window is rows 3..7).
          expect(tester.terminalState, containsText('8'));
          expect(tester.terminalState, containsText('4'));
          expect(tester.terminalState, isNot(containsText('1')));
          expect(tester.terminalState, isNot(containsText('2')));
        },
      );
    });

    test('text entry works correctly with wrapped lines', () async {
      await testNocterm(
        'text entry with wrapped lines',
        (tester) async {
          final controller = TextEditingController(text: '');

          await tester.pumpComponent(
            TextField(
              controller: controller,
              width: 25,
              maxLines: 3,
              focused: true,
              decoration: const InputDecoration(
                border: BoxBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 1),
              ),
              showCursor: true,
              cursorBlinkRate: null,
            ),
          );

          // Simulate typing a long text
          String longText =
              'Hello this is a cool thing to do is typing a cool long string that can be enough';
          controller.text = longText;
          controller.selection =
              TextSelection.collapsed(offset: longText.length);
          await tester.pump();

          print('\nTyped long text - cursor should be visible at the end:');
          expect(tester.terminalState, containsText('Hello'));
          expect(tester.terminalState, containsText('enough'));
        },
        debugPrintAfterPump: true,
      );
    });

    test('cursor paints where text inserts after a wrap-dropped space',
        () async {
      await testNocterm(
        'cursor position after dropped wrap space',
        (tester) async {
          // Regression: when a word ends exactly at the wrap column and the
          // next character is a space, the layout engine drops that space
          // from the wrapped lines. The cursor paint path then mapped every
          // offset after the wrap one column too far right — text appeared
          // to insert one cell LEFT of the block cursor.
          //
          // Width 8 → layout maxWidth 7 (1 column reserved for the cursor).
          // 'this is a test' lays out as ['this is', 'a test'] with the
          // space at offset 7 dropped.
          final controller = TextEditingController(text: 'this is a test');
          // Offset 8 = the 'a' of 'a test': first char of visual line 1.
          controller.selection = const TextSelection.collapsed(offset: 8);

          await tester.pumpComponent(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 8,
                height: 4,
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  focused: true,
                  showCursor: true,
                  cursorBlinkRate: null,
                  cursorColor: Colors.green,
                ),
              ),
            ),
          );

          // The block cursor must sit ON the 'a' at row 1, column 0.
          final cursorCell = tester.terminalState.getCellAt(0, 1);
          expect(cursorCell?.char, 'a');
          expect(cursorCell?.style.backgroundColor, Colors.green,
              reason: 'block cursor should paint at row 1 col 0');
          expect(
            tester.terminalState.getCellAt(1, 1)?.style.backgroundColor,
            isNot(Colors.green),
            reason: 'cursor must not paint one cell right of the insert point',
          );

          // Typing inserts exactly under the painted cursor.
          await tester.enterText('X');
          expect(controller.text, 'this is Xa test');
          final row1 = tester.terminalState
              .getText(area: Rect.fromLTWH(0, 1, 8, 1))
              .trimRight();
          expect(row1, 'Xa test');
        },
      );
    });
  });
}
