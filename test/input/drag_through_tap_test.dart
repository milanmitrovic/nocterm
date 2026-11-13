import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

/// A drag that begins on one detector and ends on another — a text
/// selection dragged down a list of clickable rows — must tap neither:
/// the press was not on the row it ends on, and it left the row it began
/// on.
void main() {
  Component rows(List<String> taps) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final name in ['first', 'second', 'third'])
            GestureDetector(
              onTap: () => taps.add(name),
              child: SizedBox(width: 20, height: 1, child: Text(name)),
            ),
        ],
      );

  test('a drag ending on another detector taps nothing', () async {
    await testNocterm('drag through', (tester) async {
      final taps = <String>[];
      await tester.pumpComponent(rows(taps));

      await tester.press(2, 0);
      await tester.sendMouseEvent(const MouseEvent(
        button: MouseButton.left,
        x: 3,
        y: 1,
        pressed: true,
        isMotion: true,
      ));
      await tester.sendMouseEvent(const MouseEvent(
        button: MouseButton.left,
        x: 4,
        y: 2,
        pressed: true,
        isMotion: true,
      ));
      await tester.release(4, 2);

      expect(taps, hasLength(0));
    });
  });

  test('control: a click on a row taps it', () async {
    await testNocterm('click', (tester) async {
      final taps = <String>[];
      await tester.pumpComponent(rows(taps));

      await tester.press(4, 2);
      await tester.release(4, 2);

      expect(taps, ['third']);
    });
  });

  test('a press a terminal flags as motion still taps', () async {
    await testNocterm('motion press', (tester) async {
      final taps = <String>[];
      await tester.pumpComponent(rows(taps));

      await tester.sendMouseEvent(const MouseEvent(
        button: MouseButton.left,
        x: 4,
        y: 1,
        pressed: true,
        isMotion: true,
      ));
      await tester.sendMouseEvent(const MouseEvent(
        button: MouseButton.left,
        x: 4,
        y: 1,
        pressed: false,
        isMotion: true,
      ));

      expect(taps, ['second']);
    });
  });
}
