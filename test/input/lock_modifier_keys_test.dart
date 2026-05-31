import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/keyboard/input_parser.dart';
import 'package:nocterm/src/keyboard/input_event.dart';
import 'package:test/test.dart';

/// Regression tests for cursor/edit keys reported with lock modifiers folded
/// into the modifier parameter.
///
/// Terminals implementing the kitty keyboard protocol / xterm modifyOtherKeys
/// (e.g. kitty) report an UNMODIFIED arrow key as `CSI 1 ; 129 A` when num lock
/// is on — 129 = 1 + 128, where bit 128 is num_lock (bit 64 is caps_lock).
/// nocterm previously only parsed a single-digit modifier (`CSI 1 ; X A`), so
/// these multi-digit sequences were dropped and arrow navigation silently broke
/// under kitty. The parser must read a multi-digit modifier and ignore lock
/// bits so the key resolves to a plain arrow.
void main() {
  KeyboardEvent? firstKey(List<int> bytes) {
    final parser = InputParser();
    parser.addBytes(bytes);
    InputEvent? e;
    while ((e = parser.parseNext()) != null) {
      if (e is KeyboardInputEvent) return e.event;
    }
    return null;
  }

  List<int> csi(String body) => [0x1B, 0x5B, ...body.codeUnits];

  group('cursor keys with lock modifiers folded in (kitty/num_lock)', () {
    test('CSI 1;129 A -> plain ArrowUp (num lock, no real modifier)', () {
      final e = firstKey(csi('1;129A'));
      expect(e, isNotNull);
      expect(e!.logicalKey, LogicalKey.arrowUp);
      expect(e.modifiers.shift, isFalse);
      expect(e.modifiers.ctrl, isFalse);
      expect(e.modifiers.alt, isFalse);
      expect(e.modifiers.meta, isFalse);
    });

    test('CSI 1;129 B/C/D -> plain Down/Right/Left', () {
      expect(firstKey(csi('1;129B'))!.logicalKey, LogicalKey.arrowDown);
      expect(firstKey(csi('1;129C'))!.logicalKey, LogicalKey.arrowRight);
      expect(firstKey(csi('1;129D'))!.logicalKey, LogicalKey.arrowLeft);
    });

    test('CSI 1;130 A -> Shift+ArrowUp (num lock + shift)', () {
      // 130 = 1 + 129; bitmask 129 = num_lock(128) | shift(1)
      final e = firstKey(csi('1;130A'))!;
      expect(e.logicalKey, LogicalKey.arrowUp);
      expect(e.modifiers.shift, isTrue);
      expect(e.modifiers.ctrl, isFalse);
    });

    test('CSI 1;65 A -> plain ArrowUp (caps lock only)', () {
      // 65 = 1 + 64; bit 64 = caps_lock
      final e = firstKey(csi('1;65A'))!;
      expect(e.logicalKey, LogicalKey.arrowUp);
      expect(e.modifiers.shift, isFalse);
    });

    test('single-digit modifiers still work: CSI 1;2 A -> Shift+ArrowUp', () {
      final e = firstKey(csi('1;2A'))!;
      expect(e.logicalKey, LogicalKey.arrowUp);
      expect(e.modifiers.shift, isTrue);
    });

    test('plain legacy arrow CSI A still works', () {
      expect(firstKey(csi('A'))!.logicalKey, LogicalKey.arrowUp);
    });

    test('Home/End with num lock: CSI 1;129 H/F -> plain Home/End', () {
      expect(firstKey(csi('1;129H'))!.logicalKey, LogicalKey.home);
      expect(firstKey(csi('1;129F'))!.logicalKey, LogicalKey.end);
    });

    test('fragmented delivery across reads reassembles to ArrowUp', () {
      final parser = InputParser();
      parser.addBytes([0x1B, 0x5B, 0x31, 0x3B, 0x31, 0x32]); // ESC [ 1 ; 1 2
      expect(parser.parseNext(), isNull, reason: 'incomplete: should wait');
      parser.addBytes([0x39, 0x41]); // 9 A  -> completes CSI 1;129 A
      InputEvent? e;
      KeyboardEvent? key;
      while ((e = parser.parseNext()) != null) {
        if (e is KeyboardInputEvent) key = e.event;
      }
      expect(key, isNotNull);
      expect(key!.logicalKey, LogicalKey.arrowUp);
      expect(key.modifiers.shift, isFalse);
    });
  });

  group('~-terminated edit keys with lock modifiers', () {
    test('CSI 3;129 ~ -> plain Delete', () {
      final e = firstKey(csi('3;129~'))!;
      expect(e.logicalKey, LogicalKey.delete);
      expect(e.modifiers.shift, isFalse);
    });

    test('CSI 6;129 ~ -> plain PageDown', () {
      expect(firstKey(csi('6;129~'))!.logicalKey, LogicalKey.pageDown);
    });

    test('CSI 5;130 ~ -> Shift+PageUp', () {
      final e = firstKey(csi('5;130~'))!;
      expect(e.logicalKey, LogicalKey.pageUp);
      expect(e.modifiers.shift, isTrue);
    });

    test('plain CSI 3 ~ still works (Delete, no modifier)', () {
      expect(firstKey(csi('3~'))!.logicalKey, LogicalKey.delete);
    });
  });
}
