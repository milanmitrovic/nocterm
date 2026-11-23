import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// `isEmpty` is a matcher in both packages; take the test package's.
import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:nocterm/src/components/image.dart' as img;
import 'package:nocterm/src/image/graphics_caps.dart';
import 'package:test/test.dart';

/// Fake tty: records writes and lets the test resize the window.
class _Backend implements TerminalBackend {
  final output = StringBuffer();
  final input = StreamController<List<int>>.broadcast();
  final resize = StreamController<Size>.broadcast();

  @override
  void writeRaw(String data) => output.write(data);

  @override
  Size getSize() => const Size(80, 24);

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream => input.stream;

  @override
  Stream<Size>? get resizeStream => resize.stream;

  @override
  Stream<void>? get shutdownStream => null;

  @override
  Stream<int>? get terminateStream => null;

  @override
  void enableRawMode() {}

  @override
  void disableRawMode() {}

  @override
  bool get isAvailable => true;

  @override
  void requestExit([int code = 0]) {}

  @override
  void notifySizeChanged(Size newSize) {}

  @override
  void dispose() {}
}

/// A 100x80 px image that resolves without decoding.
class _Pixels extends img.ImageProvider {
  const _Pixels();

  @override
  Future<img.ImageData> resolve() async => img.ImageData(
        pixels: Uint8List(100 * 80 * 4)..fillRange(0, 100 * 80 * 4, 200),
        width: 100,
        height: 80,
      );

  @override
  bool operator ==(Object other) => other is _Pixels;

  @override
  int get hashCode => 1;
}

class _Value<T> extends ChangeNotifier implements ValueListenable<T> {
  _Value(this._value);

  T _value;

  @override
  T get value => _value;

  set value(T next) {
    _value = next;
    notifyListeners();
  }
}

final _label = _Value('one');
final _showImage = _Value(true);

class _App extends StatelessComponent {
  const _App();

  @override
  Component build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: _showImage,
        builder: (context, show, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: _label,
              builder: (context, label, _) => Text(label),
            ),
            if (show)
              const img.Image(
                image: _Pixels(),
                width: 10,
                height: 4,
                contentKey: 'blob-1',
              ),
          ],
        ),
      );
}

int _count(String out, String command) =>
    RegExp(RegExp.escape('\x1b_G$command')).allMatches(out).length;

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

/// A TerminalBinding registers dart:developer service extensions, so only one
/// can exist per isolate — hence this end-to-end check has its own file.
void main() {
  test(
      'the binding transmits an image once, places it, re-places it on a '
      'full redraw, deletes it when it goes, and frees it at shutdown',
      () async {
    final id = kittyImageId(utf8.encode('blob-1'));
    final backend = _Backend();
    final binding =
        TerminalBinding(Terminal(backend, size: const Size(80, 24)));
    binding.initialize(probeGraphics: false);
    binding.enableFrameRateLimiting = false;
    GraphicsCaps.current = const GraphicsCaps(
        kitty: true, cellPixelSize: CellPixelSize(10, 20));
    addTearDown(() => GraphicsCaps.current = GraphicsCaps.unknown);

    binding.attachRootComponent(const _App());
    binding.scheduleFrame();
    await _settle();

    var out = backend.output.toString();
    expect(_count(out, 'a=t,f=100,i=$id,'), 1, reason: 'transmitted');
    expect(out, contains('\x1b[2;1H\x1b_Ga=p,i=$id,p='),
        reason: 'placed under the one-row label');
    expect(_count(out, 'a=T'), 0);

    // A text-only frame neither transmits nor places again.
    backend.output.clear();
    _label.value = 'two';
    await _settle();
    out = backend.output.toString();
    expect(out, contains('\x1b[1;1Ht'), reason: 'the frame did render');
    expect(_count(out, 'a=t'), 0);
    expect(_count(out, 'a=p'), 0);

    // A resize redraws the whole screen: placed again, never re-sent.
    backend.output.clear();
    backend.resize.add(const Size(100, 30));
    await _settle();
    out = backend.output.toString();
    expect(_count(out, 'a=p,i=$id,'), 1);
    expect(_count(out, 'a=t'), 0);

    // The terminal evicted the image (kitty's storage quota): the
    // placement's error reply (q=1) makes the binding send it again and
    // place it, without waiting for anything else to repaint.
    expect(out, contains(',C=1,q=1'), reason: 'placements ask for errors');
    backend.output.clear();
    backend.input.add(
        utf8.encode('\x1b_Gi=$id,p=1;ENOENT:No image with id: $id\x1b\\'));
    await _settle();
    out = backend.output.toString();
    expect(_count(out, 'a=t,f=100,i=$id,'), 1, reason: 're-sent');
    expect(_count(out, 'a=p,i=$id,'), 1, reason: 'placed again');

    // A reply for an image it never sent is ignored.
    backend.output.clear();
    backend.input.add(utf8.encode('\x1b_Gi=99;ENOENT:No image\x1b\\'));
    await _settle();
    expect(_count(backend.output.toString(), 'a=t'), 0);

    // The image leaves the tree: its placement is deleted, data kept.
    backend.output.clear();
    _showImage.value = false;
    await _settle();
    out = backend.output.toString();
    expect(_count(out, 'a=d,d=i,i=$id,'), 1);

    // Shutdown frees what this session transmitted.
    backend.output.clear();
    binding.requestShutdown();
    expect(backend.output.toString(), contains('\x1b_Ga=d,d=I,i=$id,q=2'));
  });
}
