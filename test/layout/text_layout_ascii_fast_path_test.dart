import 'dart:math';

import 'package:characters/characters.dart';
import 'package:nocterm/src/text/text_layout_engine.dart';
import 'package:nocterm/src/utils/unicode_width.dart';
import 'package:test/test.dart';

/// The printable-ASCII fast paths — `UnicodeWidth.stringWidth` and the
/// word split `TextLayoutEngine` wraps with — must answer EXACTLY what the
/// grapheme walks answer. A layout that moved one break would move a row
/// on every screen that wraps English text, so each is checked against
/// its slow twin over a randomized corpus heavy in the characters the
/// break rules care about (space, hyphen, slash), plus the edge shapes.
void main() {
  const alphabet = 'ab -/ -xyz  /Q9.,;:!?()[]{}~^_"\'';

  List<String> corpus() {
    final rng = Random(20260926);
    return [
      '',
      ' ',
      '  ',
      ' a',
      'a ',
      '  a  b  ',
      '-',
      '/',
      '--x//y- /',
      'http://example.com/a-b/c',
      for (var i = 0; i < 2000; i++)
        String.fromCharCodes([
          for (var j = 0; j < rng.nextInt(80); j++)
            alphabet.codeUnitAt(rng.nextInt(alphabet.length)),
        ]),
    ];
  }

  test('every sample IS printable ASCII (guard the guard)', () {
    for (final s in corpus()) {
      expect(UnicodeWidth.isPrintableAscii(s), isTrue, reason: s);
    }
    expect(UnicodeWidth.isPrintableAscii('tab\there'), isFalse);
    expect(UnicodeWidth.isPrintableAscii('é'), isFalse);
    expect(UnicodeWidth.isPrintableAscii('日本'), isFalse);
  });

  test('the split is token-for-token the grapheme split', () {
    for (final s in corpus()) {
      expect(
        TextLayoutEngine.debugSplitAscii(s),
        TextLayoutEngine.debugSplitByGraphemes(s),
        reason: '"$s"',
      );
    }
  });

  test('the width is the grapheme walk\'s width', () {
    for (final s in corpus()) {
      var slow = 0;
      for (final g in s.characters) {
        slow += UnicodeWidth.graphemeWidth(g);
      }
      expect(UnicodeWidth.stringWidth(s), slow, reason: '"$s"');
    }
  });

  test('non-ASCII text still takes the grapheme path', () {
    expect(UnicodeWidth.stringWidth('日本'), 4);
    expect(
      TextLayoutEngine.layout(
        '日本語のテキスト',
        const TextLayoutConfig(maxWidth: 6),
      ).actualHeight,
      3,
    );
  });
}
