import 'dart:async';

import 'package:nocterm/src/image/graphics_caps.dart';
import 'package:test/test.dart';

const kittyOk = '\x1b_Gi=31;OK\x1b\\';
const kittyError = '\x1b_Gi=31;ENOTSUPPORTED:graphics not supported\x1b\\';
const da1 = '\x1b[?62;22c';
const da1Sixel = '\x1b[?62;4;22c';

void main() {
  group('GraphicsCaps.parse: kitty graphics', () {
    test('an OK reply before the DA1 reply means kitty graphics work', () {
      final caps = GraphicsCaps.parse('$kittyOk$da1');

      expect(caps.kitty, isTrue);
    });

    test('a DA1 reply with no kitty reply means no kitty graphics', () {
      final caps = GraphicsCaps.parse(da1);

      expect(caps.kitty, isFalse);
    });

    test('a kitty error reply means no kitty graphics', () {
      final caps = GraphicsCaps.parse('$kittyError$da1');

      expect(caps.kitty, isFalse);
    });

    test('an OK that arrives after the DA1 reply does not count', () {
      // DA1 is the sentinel: every terminal answers it, and in order. A kitty
      // reply behind it is not an answer to this probe.
      final caps = GraphicsCaps.parse('$da1$kittyOk');

      expect(caps.kitty, isFalse);
    });

    test('an OK for a different image id is not our answer', () {
      final caps = GraphicsCaps.parse('\x1b_Gi=7;OK\x1b\\$da1');

      expect(caps.kitty, isFalse);
    });

    test('no replies at all means no kitty graphics', () {
      final caps = GraphicsCaps.parse('');

      expect(caps.kitty, isFalse);
    });
  });

  group('GraphicsCaps.parse: cell pixel size', () {
    test('CSI 6 ; h ; w t gives the cell size in pixels', () {
      final caps = GraphicsCaps.parse('$kittyOk\x1b[6;20;10t$da1');

      expect(caps.cellPixelSize, const CellPixelSize(10, 20));
      expect(caps.cellPixelSizeKnown, isTrue);
    });

    test('without a CSI 16 t reply, the tty pixel size divided by cells is used',
        () {
      final caps = GraphicsCaps.parse(
        da1,
        winsize: const TerminalWinsize(
            columns: 100, rows: 50, pixelWidth: 900, pixelHeight: 950),
      );

      expect(caps.cellPixelSize, const CellPixelSize(9, 19));
      expect(caps.cellPixelSizeKnown, isTrue);
    });

    test('the CSI 16 t reply wins over the tty pixel size', () {
      final caps = GraphicsCaps.parse(
        '\x1b[6;20;10t$da1',
        winsize: const TerminalWinsize(
            columns: 100, rows: 50, pixelWidth: 900, pixelHeight: 950),
      );

      expect(caps.cellPixelSize, const CellPixelSize(10, 20));
    });

    test('a tty that reports zero pixels is not a measurement', () {
      final caps = GraphicsCaps.parse(
        da1,
        winsize: const TerminalWinsize(
            columns: 100, rows: 50, pixelWidth: 0, pixelHeight: 0),
      );

      expect(caps.cellPixelSize, const CellPixelSize(8, 16));
      expect(caps.cellPixelSizeKnown, isFalse);
    });

    test('with no measurement the size stays 8x16 and is marked unknown', () {
      final caps = GraphicsCaps.parse(da1);

      expect(caps.cellPixelSize, const CellPixelSize(8, 16));
      expect(caps.cellPixelSizeKnown, isFalse);
    });

    test('a CSI 4 t (whole window) reply is not taken as a cell size', () {
      // CSI 14 t is wrong inside zellij (#5835); we never ask for it, and if
      // its reply shows up anyway it must not be read as cell pixels.
      final caps = GraphicsCaps.parse('\x1b[4;800;1600t$da1');

      expect(caps.cellPixelSizeKnown, isFalse);
    });
  });

  test('the unknown caps are no kitty and an unknown 8x16 cell', () {
    expect(GraphicsCaps.unknown.kitty, isFalse);
    expect(GraphicsCaps.unknown.cellPixelSize, const CellPixelSize(8, 16));
    expect(GraphicsCaps.unknown.cellPixelSizeKnown, isFalse);
  });

  group('GraphicsProbe', () {
    late List<String> written;
    late StreamController<String> replies;
    late Duration now;
    late List<Duration> delays;
    late Map<Duration, Completer<void>> pendingDelays;

    GraphicsProbe probe({TerminalWinsize? winsize}) => GraphicsProbe(
          write: written.add,
          replies: replies.stream,
          winsize: () => winsize,
          elapsed: () => now,
          delay: (d) {
            delays.add(d);
            return (pendingDelays[d] ??= Completer<void>()).future;
          },
        );

    setUp(() {
      written = [];
      replies = StreamController<String>.broadcast(sync: true);
      now = Duration.zero;
      delays = [];
      pendingDelays = {};
    });

    tearDown(() => replies.close());

    test('writes the kitty query, then CSI 16 t, then DA1 — never CSI 14 t',
        () async {
      final result = probe().run();
      await pumpEventQueue();

      expect(written.join(), '\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\'
          '\x1b[16t'
          '\x1b[c');
      expect(written.join(), isNot(contains('\x1b[14t')));

      now = const Duration(milliseconds: 200);
      replies.add(kittyOk);
      replies.add('\x1b[6;20;10t');
      replies.add(da1);

      final caps = await result;
      expect(caps.kitty, isTrue);
      expect(caps.cellPixelSize, const CellPixelSize(10, 20));
    });

    test('a negative answer that came late is final', () async {
      final result = probe().run();
      await pumpEventQueue();

      now = const Duration(milliseconds: 200);
      replies.add(da1);

      final caps = await result;
      expect(caps.kitty, isFalse);
      expect(written.where((w) => w == '\x1b[c'), hasLength(1),
          reason: 'no re-probe');
    });

    test('a negative answer that came very early is probed once more '
        '(zellij answers before host detection finished, #5811)', () async {
      final result = probe().run();
      await pumpEventQueue();

      now = const Duration(milliseconds: 2);
      replies.add(da1);
      await pumpEventQueue();

      // The re-probe waits out the early window before asking again.
      expect(delays, contains(GraphicsProbe.defaultReprobeDelay));
      pendingDelays[GraphicsProbe.defaultReprobeDelay]!.complete();
      await pumpEventQueue();

      expect(written.where((w) => w == '\x1b[c'), hasLength(2));

      now = const Duration(milliseconds: 600);
      replies.add(kittyOk);
      replies.add(da1);

      final caps = await result;
      expect(caps.kitty, isTrue);
    });

    test('the re-probe happens at most once', () async {
      final result = probe().run();
      await pumpEventQueue();

      now = const Duration(milliseconds: 2);
      replies.add(da1);
      await pumpEventQueue();
      pendingDelays[GraphicsProbe.defaultReprobeDelay]!.complete();
      await pumpEventQueue();

      // Second answer is early AND negative relative to its own send.
      now = const Duration(milliseconds: 3);
      replies.add(da1);

      final caps = await result;
      expect(caps.kitty, isFalse);
      expect(written.where((w) => w == '\x1b[c'), hasLength(2));
    });

    test('a positive early answer is not re-probed', () async {
      final result = probe().run();
      await pumpEventQueue();

      now = const Duration(milliseconds: 1);
      replies.add(kittyOk);
      replies.add(da1);

      final caps = await result;
      expect(caps.kitty, isTrue);
      expect(written.where((w) => w == '\x1b[c'), hasLength(1));
    });

    test('no DA1 reply before the timeout gives the caps seen so far',
        () async {
      final result = probe(
              winsize: const TerminalWinsize(
                  columns: 80, rows: 24, pixelWidth: 800, pixelHeight: 480))
          .run();
      await pumpEventQueue();

      expect(delays, contains(GraphicsProbe.defaultTimeout));
      now = GraphicsProbe.defaultTimeout;
      pendingDelays[GraphicsProbe.defaultTimeout]!.complete();

      final caps = await result;
      expect(caps.kitty, isFalse);
      expect(caps.cellPixelSize, const CellPixelSize(10, 20),
          reason: 'tty pixel size still measured');
    });

    test('a reprobe of the cell size asks CSI 16 t + DA1 and keeps kitty',
        () async {
      const previous = GraphicsCaps(
          kitty: true, cellPixelSize: CellPixelSize(10, 20));
      final result = probe().reprobeCellSize(previous);
      await pumpEventQueue();

      expect(written.join(), '\x1b[16t\x1b[c');

      replies.add('\x1b[6;24;12t');
      replies.add(da1);

      final caps = await result;
      expect(caps.kitty, isTrue);
      expect(caps.cellPixelSize, const CellPixelSize(12, 24));
    });

    test('a cell-size reprobe with no answer keeps the previous size',
        () async {
      const previous = GraphicsCaps(
          kitty: true, cellPixelSize: CellPixelSize(10, 20));
      final result = probe().reprobeCellSize(previous);
      await pumpEventQueue();

      replies.add(da1);

      final caps = await result;
      expect(caps.cellPixelSize, const CellPixelSize(10, 20));
      expect(caps.cellPixelSizeKnown, isTrue);
    });
  });

  test('sixel in DA1 does not turn kitty on', () {
    expect(GraphicsCaps.parse(da1Sixel).kitty, isFalse);
  });
}
