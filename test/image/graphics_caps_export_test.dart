import 'package:nocterm/nocterm.dart' show CellPixelSize, GraphicsCaps;
import 'package:test/test.dart';

/// An app reads the probed caps through the public library, never `src/`.
void main() {
  test('GraphicsCaps and CellPixelSize are exported from nocterm.dart', () {
    const caps =
        GraphicsCaps(kitty: true, cellPixelSize: CellPixelSize(10, 20));
    expect(caps.kitty, isTrue);
    expect(caps.cellPixelSize, const CellPixelSize(10, 20));
  });
}
