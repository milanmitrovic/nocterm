import 'dart:async';

// `isEmpty` is a matcher in both packages; take the test package's.
import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:nocterm/src/image/graphics_caps.dart';
import 'package:test/test.dart';

/// Fake tty: records writes, lets the test type replies and resize the
/// window.
class _ProbeBackend implements TerminalBackend {
  final output = StringBuffer();
  final input = StreamController<List<int>>.broadcast();
  final resize = StreamController<Size>.broadcast();
  final terminate = StreamController<int>.broadcast();

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
  Stream<int>? get terminateStream => terminate.stream;

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

/// A TerminalBinding registers dart:developer service extensions, so only one
/// can exist per isolate — hence this end-to-end check has its own file.
void main() {
  test(
      'initialize probes graphics through the input parser, sets '
      'GraphicsCaps.current, and re-measures the cell on resize', () async {
    final backend = _ProbeBackend();
    final binding =
        TerminalBinding(Terminal(backend, size: const Size(80, 24)));

    final keys = <KeyboardEvent>[];
    final replies = <String>[];
    binding.keyboardEvents.listen(keys.add);
    binding.terminalReplies.listen(replies.add);

    binding.initialize();

    final startup = backend.output.toString();
    expect(startup, contains(GraphicsProbe.kittyQuery));
    expect(startup, contains('\x1b[16t'));
    expect(startup, contains('\x1b[c'));
    expect(startup, isNot(contains('\x1b[14t')));
    expect(GraphicsCaps.current, GraphicsCaps.unknown,
        reason: 'nothing answered yet');

    // The terminal answers all three in one read.
    backend.input.add('\x1b_Gi=31;OK\x1b\\\x1b[6;20;10t\x1b[?62;22c'.codeUnits);
    await pumpEventQueue();

    expect(keys, isEmpty, reason: 'probe replies must not be keystrokes');
    expect(replies, hasLength(3));
    expect(GraphicsCaps.current,
        const GraphicsCaps(kitty: true, cellPixelSize: CellPixelSize(10, 20)));

    // A resize (font zoom changes the cell size) asks for the cell again.
    backend.output.clear();
    backend.resize.add(const Size(100, 30));
    await pumpEventQueue();

    final resizeQueries = backend.output.toString();
    expect(resizeQueries, contains('\x1b[16t'));
    expect(resizeQueries, isNot(contains(GraphicsProbe.kittyQuery)),
        reason: 'kitty support does not change on resize');

    backend.input.add('\x1b[6;24;12t\x1b[?62;22c'.codeUnits);
    await pumpEventQueue();

    expect(GraphicsCaps.current,
        const GraphicsCaps(kitty: true, cellPixelSize: CellPixelSize(12, 24)));
    expect(keys, isEmpty);

    backend.terminate.add(143);
    await pumpEventQueue();
  });
}
