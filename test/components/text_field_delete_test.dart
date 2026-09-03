import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  group('TextField forward delete', () {
    test('Delete removes the character after the cursor and stays put',
        () async {
      // Regression: _handleDelete assigned controller.text and relied on a
      // comment claiming "cursor position stays the same". The text setter
      // collapses the selection to newText.length, so every Delete press
      // teleported the cursor to the end of the buffer and the next press
      // deleted nothing (or the wrong thing).
      await testNocterm(
        'forward delete keeps cursor',
        (tester) async {
          final controller = TextEditingController();

          await tester.pumpComponent(
            Container(
              width: 30,
              height: 3,
              decoration: BoxDecoration(border: BoxBorder.all()),
              child: TextField(
                controller: controller,
                focused: true,
              ),
            ),
          );

          await tester.enterText('abcdef');
          expect(controller.text, 'abcdef');

          // Put the cursor between 'b' and 'c'.
          controller.selection = const TextSelection.collapsed(offset: 2);
          await tester.pump();

          await tester.sendKey(LogicalKey.delete);
          expect(controller.text, 'abdef');
          expect(controller.selection.isCollapsed, isTrue);
          expect(controller.selection.extentOffset, 2);

          await tester.sendKey(LogicalKey.delete);
          expect(controller.text, 'abef');
          expect(controller.selection.extentOffset, 2);

          await tester.sendKey(LogicalKey.delete);
          expect(controller.text, 'abf');
          expect(controller.selection.isCollapsed, isTrue);
          expect(controller.selection.extentOffset, 2);
        },
      );
    });

    test('Delete at the end of the buffer is a no-op', () async {
      await testNocterm(
        'forward delete at end',
        (tester) async {
          final controller = TextEditingController(text: 'abc');
          controller.selection = const TextSelection.collapsed(offset: 3);

          await tester.pumpComponent(
            Container(
              width: 30,
              height: 3,
              decoration: BoxDecoration(border: BoxBorder.all()),
              child: TextField(
                controller: controller,
                focused: true,
              ),
            ),
          );

          await tester.sendKey(LogicalKey.delete);
          expect(controller.text, 'abc');
          expect(controller.selection.extentOffset, 3);
        },
      );
    });

    test('Delete with a selection removes it and collapses at its start',
        () async {
      await testNocterm(
        'forward delete of selection',
        (tester) async {
          final controller = TextEditingController(text: 'abcdef');
          controller.selection =
              const TextSelection(baseOffset: 1, extentOffset: 4);

          await tester.pumpComponent(
            Container(
              width: 30,
              height: 3,
              decoration: BoxDecoration(border: BoxBorder.all()),
              child: TextField(
                controller: controller,
                focused: true,
              ),
            ),
          );

          await tester.sendKey(LogicalKey.delete);
          expect(controller.text, 'aef');
          expect(controller.selection.isCollapsed, isTrue);
          expect(controller.selection.extentOffset, 1);
        },
      );
    });

    test('Ctrl+Delete deletes the word ahead and keeps the cursor', () async {
      // Regression: the plain `key == LogicalKey.delete` branch came first in
      // the if-chain, so Ctrl+Delete never reached _deleteWordForward — and
      // _deleteWordForward carried the same stale "cursor stays the same"
      // comment as _handleDelete.
      await testNocterm(
        'ctrl+delete word forward',
        (tester) async {
          final controller = TextEditingController(text: 'foo bar baz');
          // Cursor at the start of 'bar'.
          controller.selection = const TextSelection.collapsed(offset: 4);

          await tester.pumpComponent(
            Container(
              width: 30,
              height: 3,
              decoration: BoxDecoration(border: BoxBorder.all()),
              child: TextField(
                controller: controller,
                focused: true,
              ),
            ),
          );

          await tester.sendKeyEvent(const KeyboardEvent(
            logicalKey: LogicalKey.delete,
            modifiers: ModifierKeys(ctrl: true),
          ));

          // 'bar' and the space after it are gone; the cursor has not moved.
          expect(controller.text, 'foo baz');
          expect(controller.selection.isCollapsed, isTrue);
          expect(controller.selection.extentOffset, 4);
        },
      );
    });

    test('Ctrl+Backspace still deletes the word behind the cursor', () async {
      // The Ctrl+Backspace branch was unreachable for the same reason as
      // Ctrl+Delete; pin it now that the branch order is fixed.
      await testNocterm(
        'ctrl+backspace word backward',
        (tester) async {
          final controller = TextEditingController(text: 'foo bar baz');
          // Cursor at the end of 'bar'.
          controller.selection = const TextSelection.collapsed(offset: 7);

          await tester.pumpComponent(
            Container(
              width: 30,
              height: 3,
              decoration: BoxDecoration(border: BoxBorder.all()),
              child: TextField(
                controller: controller,
                focused: true,
              ),
            ),
          );

          await tester.sendKeyEvent(const KeyboardEvent(
            logicalKey: LogicalKey.backspace,
            modifiers: ModifierKeys(ctrl: true),
          ));

          expect(controller.text, 'foo  baz');
          expect(controller.selection.isCollapsed, isTrue);
          expect(controller.selection.extentOffset, 4);
        },
      );
    });
  });
}
