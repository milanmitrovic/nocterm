import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

void main() {
  test('TextField should have default selection color', () async {
    await testNocterm(
      'default selection color',
      (tester) async {
        final controller = TextEditingController(text: 'Test selection colors');

        await tester.pumpComponent(
          Container(
            width: 30,
            height: 3,
            decoration: BoxDecoration(border: BoxBorder.all()),
            child: TextField(
              controller: controller,
              focused: true,
              // No selectionColor or cursorColor specified - using defaults
            ),
          ),
        );

        // Select all text. Ctrl+A is now line-start, so set the selection
        // directly for this default-color visual check.
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
        await tester.pump();

        // Verify selection is made
        expect(controller.selection.start, 0);
        expect(controller.selection.end, controller.text.length);
        expect(controller.selection.isCollapsed, false);

        print(
            'Selected text: "${controller.text.substring(controller.selection.start, controller.selection.end)}"');
      },
      debugPrintAfterPump: true,
    );
  });
}
