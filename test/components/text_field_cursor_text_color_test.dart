import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

/// Pump a focused single-line TextField under [theme] with the cursor parked
/// on the first character, and return the cell the block cursor painted.
Future<Cell> cursorCell(
  NoctermTester tester, {
  required TuiThemeData theme,
  Color? cursorColor,
  Color? cursorTextColor,
  CursorStyle cursorStyle = CursorStyle.block,
}) async {
  final controller = TextEditingController(text: 'abc');
  controller.selection = const TextSelection.collapsed(offset: 0);

  await tester.pumpComponent(
    TuiTheme(
      data: theme,
      child: SizedBox(
        width: 10,
        height: 1,
        child: TextField(
          controller: controller,
          focused: true,
          cursorColor: cursorColor,
          cursorTextColor: cursorTextColor,
          cursorStyle: cursorStyle,
        ),
      ),
    ),
  );

  final cell = tester.terminalState.getCellAt(0, 0)!;
  expect(cell.char, 'a', reason: 'cursor should sit on the first character');
  return cell;
}

void main() {
  group('TextField cursorTextColor', () {
    test('defaults to the theme onPrimary, not a hard-coded black', () async {
      await testNocterm('block cursor default text colour', (tester) async {
        // The light theme is the case the old hard-coded Colors.black got
        // wrong: a near-black glyph on a mid-blue cursor.
        final cell = await cursorCell(tester, theme: TuiThemeData.light);

        expect(cell.style.backgroundColor, TuiThemeData.light.primary);
        expect(cell.style.color, TuiThemeData.light.onPrimary);
        expect(cell.style.color, isNot(Colors.black));
      });
    });

    test('an explicit cursorTextColor wins over the theme', () async {
      await testNocterm('block cursor explicit text colour', (tester) async {
        final cell = await cursorCell(
          tester,
          theme: TuiThemeData.light,
          cursorColor: Colors.yellow,
          cursorTextColor: Colors.magenta,
        );

        expect(cell.style.backgroundColor, Colors.yellow);
        expect(cell.style.color, Colors.magenta);
      });
    });

    test('blockOutline honours it too', () async {
      await testNocterm('block outline cursor text colour', (tester) async {
        final cell = await cursorCell(
          tester,
          theme: TuiThemeData.light,
          cursorStyle: CursorStyle.blockOutline,
          cursorColor: Colors.green,
          cursorTextColor: Colors.red,
        );

        expect(cell.style.backgroundColor, Colors.green);
        expect(cell.style.color, Colors.red);
      });
    });

    test('the underline cursor is unaffected — it repaints no character',
        () async {
      await testNocterm('underline cursor ignores text colour', (tester) async {
        final cell = await cursorCell(
          tester,
          theme: TuiThemeData.light,
          cursorStyle: CursorStyle.underline,
          cursorTextColor: Colors.magenta,
        );

        expect(cell.style.color, isNot(Colors.magenta));
        expect(cell.style.decoration?.hasUnderline, isTrue);
      });
    });

    test('the dark theme keeps its near-black glyph on the cursor', () async {
      await testNocterm('block cursor dark theme', (tester) async {
        // Regression guard on the default: dark's onPrimary IS the near-black
        // the code used to hard-code, so nothing about the dark theme moves.
        final cell = await cursorCell(tester, theme: TuiThemeData.dark);

        expect(cell.style.color, TuiThemeData.dark.onPrimary);
        expect(cell.style.color, Colors.black);
      });
    });
  });
}
