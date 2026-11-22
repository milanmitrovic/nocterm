import 'dart:convert';
import 'dart:typed_data';

import 'package:nocterm/nocterm.dart' hide isNotEmpty, isEmpty;
import 'package:nocterm/src/components/image.dart' as img;
import 'package:nocterm/src/framework/terminal_canvas.dart';
import 'package:nocterm/src/image/graphics_caps.dart';
import 'package:nocterm/src/image/kitty_placer.dart';
import 'package:test/test.dart';

const _kitty =
    GraphicsCaps(kitty: true, cellPixelSize: CellPixelSize(10, 20));

/// A 100x80 px red image: 10x4 cells on a 10x20 px cell.
img.ImageData _red() {
  final pixels = Uint8List(100 * 80 * 4);
  for (var i = 0; i < pixels.length; i += 4) {
    pixels[i] = 255;
    pixels[i + 3] = 255;
  }
  return img.ImageData(pixels: pixels, width: 100, height: 80);
}

img.RenderImage _render({String? contentKey}) {
  final render = img.RenderImage(
    imageData: _red(),
    requestedWidth: 10,
    requestedHeight: 4,
    contentKey: contentKey,
  );
  render.layout(const BoxConstraints(maxWidth: 80, maxHeight: 24));
  return render;
}

Buffer _buffer() => Buffer(40, 20);

TerminalCanvas _screen(Buffer buffer) =>
    TerminalCanvas(buffer, const Rect.fromLTWH(0, 0, 40, 20));

List<int> _cells(ImagePlacement p) => [p.x, p.y, p.columns, p.rows];

bool _isHalfBlock(Cell cell) =>
    cell.char == '▀' || cell.char == '▄' || cell.char == '█';

void main() {
  tearDown(() => GraphicsCaps.current = GraphicsCaps.unknown);

  test('a fully visible kitty image becomes one placement at its cells', () {
    GraphicsCaps.current = _kitty;
    final buffer = _buffer();

    _render().paint(_screen(buffer), const Offset(3, 2));

    expect(buffer.imagePlacements.map(_cells), [
      [3, 2, 10, 4]
    ]);
  });

  test('inside a clipped canvas the placement is at absolute cells', () {
    GraphicsCaps.current = _kitty;
    final buffer = _buffer();
    final pane = _screen(buffer).clip(const Rect.fromLTWH(5, 3, 20, 10));

    _render().paint(pane, const Offset(2, 1));

    expect(buffer.imagePlacements.map(_cells), [
      [7, 4, 10, 4]
    ]);
  });

  test('a half-scrolled image paints half blocks and is not placed', () {
    GraphicsCaps.current = _kitty;
    final buffer = _buffer();
    final viewport = _screen(buffer).clip(const Rect.fromLTWH(0, 5, 40, 10));

    // Two of its four rows are above the viewport's top.
    _render().paint(viewport, const Offset(0, -2));

    expect(buffer.imagePlacements, isEmpty);
    expect(_isHalfBlock(buffer.getCell(0, 5)), isTrue,
        reason: 'the visible rows show the blocky preview');
    expect(_isHalfBlock(buffer.getCell(0, 4)), isFalse,
        reason: 'nothing leaks above the viewport');
  });

  test('an image cut by the right edge paints half blocks', () {
    GraphicsCaps.current = _kitty;
    final buffer = _buffer();

    _render().paint(_screen(buffer), const Offset(35, 0));

    expect(buffer.imagePlacements, isEmpty);
    expect(_isHalfBlock(buffer.getCell(39, 0)), isTrue);
  });

  test('back to a placement once the image is fully visible again', () {
    GraphicsCaps.current = _kitty;
    final render = _render();
    final clipped = _buffer();
    render.paint(_screen(clipped), const Offset(35, 0));
    expect(clipped.imagePlacements, isEmpty);

    final visible = _buffer();
    render.paint(_screen(visible), const Offset(20, 0));

    expect(visible.imagePlacements.map(_cells), [
      [20, 0, 10, 4]
    ]);
  });

  test('without kitty the image is always half blocks', () {
    final buffer = _buffer();

    _render().paint(_screen(buffer), const Offset(3, 2));

    expect(buffer.imagePlacements, isEmpty);
    expect(_isHalfBlock(buffer.getCell(3, 2)), isTrue);
  });

  test('the image id and placement id hold across frames', () {
    GraphicsCaps.current = _kitty;
    final render = _render();
    final first = _buffer();
    final second = _buffer();

    render.paint(_screen(first), const Offset(3, 2));
    render.paint(_screen(second), const Offset(3, 7));

    final a = first.imagePlacements.single;
    final b = second.imagePlacements.single;
    expect(b.imageId, a.imageId);
    expect(b.placementId, a.placementId);
    expect(a.imageId, isNot(0));
  });

  test('two image widgets get different placement ids', () {
    GraphicsCaps.current = _kitty;
    final buffer = _buffer();

    _render().paint(_screen(buffer), const Offset(0, 0));
    _render().paint(_screen(buffer), const Offset(20, 0));

    final ids = buffer.imagePlacements.map((p) => p.placementId).toSet();
    expect(ids, hasLength(2));
    expect(buffer.imagePlacements.map((p) => p.imageId).toSet(), hasLength(1),
        reason: 'same pixels, same image');
  });

  test('a content key names the image', () {
    GraphicsCaps.current = _kitty;
    final buffer = _buffer();

    _render(contentKey: 'blob-1').paint(_screen(buffer), const Offset(0, 0));

    final placement = buffer.imagePlacements.single;
    expect(placement.imageId, kittyImageId(utf8.encode('blob-1')));
    expect(placement.image.key, 'blob-1');
  });

  test('text painted over the image takes it off the kitty layer', () {
    GraphicsCaps.current = _kitty;
    final buffer = _buffer();
    final screen = _screen(buffer);

    _render().paint(screen, const Offset(0, 0));
    screen.drawText(const Offset(2, 1), 'menu');

    expect(buffer.imagePlacements, isEmpty);
    expect(buffer.getCell(2, 1).char, 'm');
    expect(_isHalfBlock(buffer.getCell(0, 0)), isTrue,
        reason: 'the uncovered part shows the blocky preview');
  });

  test('an image painted over another hides the lower one', () {
    GraphicsCaps.current = _kitty;
    final buffer = _buffer();
    final screen = _screen(buffer);

    _render().paint(screen, const Offset(0, 0));
    _render(contentKey: 'top').paint(screen, const Offset(5, 2));

    expect(buffer.imagePlacements.map((p) => p.image.key), ['top']);
  });

  group('drawImage', () {
    test('places the region at the clip origin plus the local offset', () {
      final buffer = _buffer();
      final pane = _screen(buffer).clip(const Rect.fromLTWH(5, 3, 20, 10));

      pane.drawImage(null, 'SIXEL', 2, 1, 4, 2);

      final image = buffer.pendingImages.single;
      expect([image.x, image.y, image.width, image.height], [7, 4, 4, 2]);
      expect(buffer.getCell(7, 4).isImagePlaceholder, isTrue);
      expect(buffer.getCell(6, 4).isImagePlaceholder, isFalse);
    });
  });
}
