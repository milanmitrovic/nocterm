import 'dart:typed_data';

import 'package:nocterm/nocterm.dart' hide isNotEmpty;
import 'package:nocterm/src/components/image.dart' as img;
import 'package:nocterm/src/image/graphics_caps.dart';
import 'package:test/test.dart';

img.ImageData _image(int width, int height) => img.ImageData(
      pixels: Uint8List(width * height * 4),
      width: width,
      height: height,
    );

/// RenderImage takes its cell pixel size and its protocol from
/// GraphicsCaps.current, not from a hard-coded 8x16 or the environment.
void main() {
  tearDown(() => GraphicsCaps.current = GraphicsCaps.unknown);

  test('the cell size from the probe sets the image aspect in cells', () {
    // A 100x40 px image on a 10x20 px cell is 10x2 cells: aspect 5.
    // At 20 cells wide that is exactly 4 rows (8x16 would give ~4.6).
    GraphicsCaps.current = const GraphicsCaps(
        kitty: true, cellPixelSize: CellPixelSize(10, 20));
    final render = img.RenderImage(
      imageData: _image(100, 40),
      requestedWidth: 20,
    );

    render.layout(const BoxConstraints(maxWidth: 80, maxHeight: 24));

    expect(render.size, const Size(20, 4));
  });

  test('new caps after layout ask an attached image to lay out again', () {
    final render = img.RenderImage(
      imageData: _image(100, 40),
      requestedWidth: 20,
    );
    render.attach(PipelineOwner());
    render.layout(const BoxConstraints(maxWidth: 80, maxHeight: 24));
    expect(render.needsLayout, isFalse);

    GraphicsCaps.current = const GraphicsCaps(
        kitty: true, cellPixelSize: CellPixelSize(10, 20));

    expect(render.needsLayout, isTrue);
    render.detach();
  });

  test('a detached image stops listening for caps', () {
    final render = img.RenderImage(
      imageData: _image(100, 40),
      requestedWidth: 20,
    );
    render.attach(PipelineOwner());
    render.layout(const BoxConstraints(maxWidth: 80, maxHeight: 24));
    render.detach();

    GraphicsCaps.current = const GraphicsCaps(
        kitty: true, cellPixelSize: CellPixelSize(10, 20));

    expect(render.needsLayout, isFalse);
  });

  group('protocol choice', () {
    test('kitty caps choose the kitty protocol', () {
      expect(
          img.RenderImage.protocolFor(const GraphicsCaps(
              kitty: true, cellPixelSize: CellPixelSize(10, 20))),
          ImageProtocol.kitty);
    });

    test('anything else falls back to half blocks', () {
      expect(img.RenderImage.protocolFor(GraphicsCaps.unknown),
          ImageProtocol.unicodeBlocks);
    });
  });
}
