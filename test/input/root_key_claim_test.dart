import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

/// `NoctermBinding.rootKeyClaim` sees every key BEFORE the element tree.
///
/// Keys are otherwise dispatched child-first, so a focused [TextField] —
/// which consumes anything carrying a `character`, modifiers included —
/// takes `alt+a` before any ancestor can. An app-wide chord therefore had
/// no way to outrank a field without every field cooperating. The claim is
/// that way: asked once, at the root, before any component.
void main() {
  group('rootKeyClaim', () {
    final altA = KeyboardEvent(
      logicalKey: LogicalKey.keyA,
      character: 'a',
      modifiers: const ModifierKeys(alt: true),
    );

    test('a claimed key never reaches a focused TextField', () async {
      await testNocterm('claimed', (tester) async {
        final controller = TextEditingController(text: 'x');
        final claimed = <KeyboardEvent>[];
        NoctermBinding.instance.rootKeyClaim = (event) {
          if (!event.isAltPressed) return false;
          claimed.add(event);
          return true;
        };

        await tester.pumpComponent(
          TextField(controller: controller, focused: true, width: 20),
        );
        await tester.sendKeyEvent(altA);

        expect(claimed, [altA]);
        expect(controller.text, 'x', reason: 'the field must not type it');
      });
    });

    test('an unclaimed key still reaches the field', () async {
      await testNocterm('unclaimed', (tester) async {
        final controller = TextEditingController(text: 'x');
        var asked = 0;
        NoctermBinding.instance.rootKeyClaim = (event) {
          asked++;
          return false;
        };

        await tester.pumpComponent(
          TextField(controller: controller, focused: true, width: 20),
        );
        await tester.enterText('b');

        expect(asked, 1, reason: 'the claim is offered every key');
        expect(controller.text, 'xb');
      });
    });

    test('it runs before an ancestor Focusable too', () async {
      await testNocterm('ancestor', (tester) async {
        final order = <String>[];
        NoctermBinding.instance.rootKeyClaim = (event) {
          order.add('claim');
          return false;
        };

        await tester.pumpComponent(
          Focusable(
            focused: true,
            onKeyEvent: (event) {
              order.add('focusable');
              return true;
            },
            child: const Text('App'),
          ),
        );
        await tester.sendKeyEvent(altA);

        expect(order, ['claim', 'focusable']);
      });
    });

    test('with no claim set, dispatch is unchanged', () async {
      await testNocterm('unset', (tester) async {
        expect(NoctermBinding.instance.rootKeyClaim, isNull);
        final controller = TextEditingController(text: 'x');
        await tester.pumpComponent(
          TextField(controller: controller, focused: true, width: 20),
        );
        await tester.sendKeyEvent(altA);
        expect(controller.text, 'xa');
      });
    });
  });
}
