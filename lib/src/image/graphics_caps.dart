import 'dart:async';

/// Size of one terminal cell in pixels.
class CellPixelSize {
  const CellPixelSize(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CellPixelSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'CellPixelSize($width x $height)';
}

/// The tty's own idea of its size, as `TIOCGWINSZ` reports it.
///
/// [pixelWidth] / [pixelHeight] are `ws_xpixel` / `ws_ypixel`; many
/// terminals leave them at zero, which means "not reported".
class TerminalWinsize {
  const TerminalWinsize({
    required this.columns,
    required this.rows,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final int columns;
  final int rows;
  final int pixelWidth;
  final int pixelHeight;

  /// Cell size derived from the pixel and cell counts, or null when the tty
  /// did not report pixels.
  CellPixelSize? get cellPixelSize {
    if (columns <= 0 || rows <= 0 || pixelWidth <= 0 || pixelHeight <= 0) {
      return null;
    }
    final w = pixelWidth ~/ columns;
    final h = pixelHeight ~/ rows;
    if (w <= 0 || h <= 0) return null;
    return CellPixelSize(w, h);
  }
}

/// What the terminal can do with graphics, as learned by probing it.
///
/// Produced from the terminal's replies by [GraphicsCaps.parse]; the probe
/// itself (what to write, when to give up, when to ask again) is
/// [GraphicsProbe]. The live value for the running app is [current].
class GraphicsCaps {
  const GraphicsCaps({
    required this.kitty,
    required this.cellPixelSize,
    this.cellPixelSizeKnown = true,
  });

  /// Cell size assumed when nothing measured it.
  static const fallbackCellPixelSize = CellPixelSize(8, 16);

  /// Before (or without) a probe: no kitty graphics, and an assumed cell.
  static const unknown = GraphicsCaps(
    kitty: false,
    cellPixelSize: fallbackCellPixelSize,
    cellPixelSizeKnown: false,
  );

  /// Whether the kitty graphics protocol answered the `a=q` query.
  final bool kitty;

  /// Pixel size of one cell; [fallbackCellPixelSize] when not measured.
  final CellPixelSize cellPixelSize;

  /// False when [cellPixelSize] is the assumed fallback, not a measurement.
  final bool cellPixelSizeKnown;

  static GraphicsCaps _current = unknown;
  static final StreamController<GraphicsCaps> _changes =
      StreamController<GraphicsCaps>.broadcast(sync: true);

  /// The caps of the terminal this process is drawing to.
  ///
  /// [unknown] until a [GraphicsProbe] run by the binding finishes.
  static GraphicsCaps get current => _current;
  static set current(GraphicsCaps value) {
    if (value == _current) return;
    _current = value;
    _changes.add(value);
  }

  /// Emits each new [current] value.
  static Stream<GraphicsCaps> get changes => _changes.stream;

  /// Parses the terminal's replies to a [GraphicsProbe] query.
  ///
  /// [replies] is the reply text in arrival order. Kitty graphics are on iff
  /// an `ESC _ G i=31;OK ESC \` reply appears before the first DA1 reply
  /// (`CSI ? … c`) — every terminal answers DA1, and answers in order, so
  /// DA1 is the "that's all" sentinel. The cell size comes from a
  /// `CSI 6 ; h ; w t` reply, else from [winsize]'s pixel counts, else it is
  /// the [fallbackCellPixelSize] marked unknown.
  static GraphicsCaps parse(String replies, {TerminalWinsize? winsize}) {
    final da1 = _da1Pattern.firstMatch(replies);
    final beforeDa1 = da1 == null ? replies : replies.substring(0, da1.start);

    final kitty = _kittyReplyPattern
        .allMatches(beforeDa1)
        .any((m) => _isOkForProbeId(m.group(1)!, m.group(2)!));

    final measured = parseCellPixelSize(replies) ?? winsize?.cellPixelSize;
    return GraphicsCaps(
      kitty: kitty,
      cellPixelSize: measured ?? fallbackCellPixelSize,
      cellPixelSizeKnown: measured != null,
    );
  }

  /// The cell size in a `CSI 6 ; height ; width t` reply, if [replies]
  /// contains one.
  static CellPixelSize? parseCellPixelSize(String replies) {
    final m = _cellSizePattern.firstMatch(replies);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final w = int.parse(m.group(2)!);
    if (w <= 0 || h <= 0) return null;
    return CellPixelSize(w, h);
  }

  /// Whether [replies] contains a DA1 reply.
  static bool containsDa1(String replies) => _da1Pattern.hasMatch(replies);

  static bool _isOkForProbeId(String params, String message) {
    if (message != 'OK') return false;
    return params.split(',').contains('i=${GraphicsProbe.probeImageId}');
  }

  static final _da1Pattern = RegExp(r'\x1b\[\?[0-9;]*c');
  static final _kittyReplyPattern = RegExp(r'\x1b_G([^;\x1b]*);([^\x1b]*)\x1b\\');
  static final _cellSizePattern = RegExp(r'\x1b\[6;(\d+);(\d+)t');

  GraphicsCaps copyWith({
    bool? kitty,
    CellPixelSize? cellPixelSize,
    bool? cellPixelSizeKnown,
  }) =>
      GraphicsCaps(
        kitty: kitty ?? this.kitty,
        cellPixelSize: cellPixelSize ?? this.cellPixelSize,
        cellPixelSizeKnown: cellPixelSizeKnown ?? this.cellPixelSizeKnown,
      );

  @override
  bool operator ==(Object other) =>
      other is GraphicsCaps &&
      other.kitty == kitty &&
      other.cellPixelSize == cellPixelSize &&
      other.cellPixelSizeKnown == cellPixelSizeKnown;

  @override
  int get hashCode => Object.hash(kitty, cellPixelSize, cellPixelSizeKnown);

  @override
  String toString() => 'GraphicsCaps(kitty: $kitty, cell: '
      '${cellPixelSize.width}x${cellPixelSize.height}'
      '${cellPixelSizeKnown ? '' : ' (assumed)'})';
}

/// Asks the terminal for its [GraphicsCaps].
///
/// Writes a kitty graphics `a=q` query, `CSI 16 t` (cell size in pixels)
/// and DA1, in that order, then reads replies until the DA1 reply arrives or
/// [timeout] passes. Replies must come from the binding's input parser
/// (see `TerminalBinding.terminalReplies`), never a raw stdin read, so they
/// do not leak into the app as keystrokes.
///
/// Never asks `CSI 14 t` (window size in pixels): inside zellij it reports
/// the wrong window (#5835).
///
/// **Re-probe once:** zellij answers queries itself, and right after a pane
/// starts it may answer before it has detected the host terminal's graphics
/// support (#5811). So a negative answer that arrived within [earlyAnswer]
/// of the query is asked once more, after [reprobeDelay].
class GraphicsProbe {
  GraphicsProbe({
    required void Function(String data) write,
    required Stream<String> replies,
    TerminalWinsize? Function()? winsize,
    Duration Function()? elapsed,
    Future<void> Function(Duration duration)? delay,
    this.timeout = defaultTimeout,
    this.earlyAnswer = defaultEarlyAnswer,
    this.reprobeDelay = defaultReprobeDelay,
  })  : _write = write,
        _replies = replies,
        _winsize = winsize ?? _noWinsize,
        _elapsed = elapsed ?? _stopwatchElapsed(),
        _delay = delay ?? _realDelay;

  /// Image id used by the `a=q` query; the OK reply echoes it.
  static const probeImageId = 31;

  /// Kitty graphics query: a 1x1 RGB image, query only (`a=q`), never stored.
  static const kittyQuery =
      '\x1b_Gi=$probeImageId,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\';

  /// Report text area cell size in pixels: replies `CSI 6 ; h ; w t`.
  static const cellSizeQuery = '\x1b[16t';

  /// Primary device attributes; the reply ends every probe round.
  static const da1Query = '\x1b[c';

  static const defaultTimeout = Duration(seconds: 1);
  static const defaultEarlyAnswer = Duration(milliseconds: 50);
  static const defaultReprobeDelay = Duration(milliseconds: 250);

  final Duration timeout;
  final Duration earlyAnswer;
  final Duration reprobeDelay;

  final void Function(String) _write;
  final Stream<String> _replies;
  final TerminalWinsize? Function() _winsize;
  final Duration Function() _elapsed;
  final Future<void> Function(Duration) _delay;

  /// Full probe: kitty support and cell size, with the one early re-probe.
  Future<GraphicsCaps> run() async {
    final first = await _round(const [kittyQuery, cellSizeQuery, da1Query]);
    final firstCaps = GraphicsCaps.parse(first.text, winsize: _winsize());
    if (!shouldReprobe(firstCaps, first.answeredAfter)) return firstCaps;

    await _delay(reprobeDelay);
    final second = await _round(const [kittyQuery, cellSizeQuery, da1Query]);
    final secondCaps = GraphicsCaps.parse(second.text, winsize: _winsize());
    if (!secondCaps.cellPixelSizeKnown && firstCaps.cellPixelSizeKnown) {
      return secondCaps.copyWith(
        cellPixelSize: firstCaps.cellPixelSize,
        cellPixelSizeKnown: true,
      );
    }
    return secondCaps;
  }

  /// Cell size only (after a resize): keeps [previous]'s kitty answer, and
  /// its cell size when nothing new was measured.
  Future<GraphicsCaps> reprobeCellSize(GraphicsCaps previous) async {
    final round = await _round(const [cellSizeQuery, da1Query]);
    final measured = GraphicsCaps.parseCellPixelSize(round.text) ??
        _winsize()?.cellPixelSize;
    if (measured == null) return previous;
    return previous.copyWith(cellPixelSize: measured, cellPixelSizeKnown: true);
  }

  /// Whether a first answer should be asked again: it was negative and came
  /// back within [earlyAnswer] of the query. [answeredAfter] is null when
  /// the DA1 reply never came (timeout) — that is not an early answer.
  bool shouldReprobe(GraphicsCaps caps, Duration? answeredAfter) =>
      !caps.kitty && answeredAfter != null && answeredAfter <= earlyAnswer;

  Future<_Round> _round(List<String> queries) async {
    final buffer = StringBuffer();
    final done = Completer<Duration?>();
    final sentAt = _elapsed();
    final sub = _replies.listen((reply) {
      buffer.write(reply);
      if (!done.isCompleted && GraphicsCaps.containsDa1(buffer.toString())) {
        done.complete(_elapsed() - sentAt);
      }
    });
    for (final q in queries) {
      _write(q);
    }
    unawaited(_delay(timeout).then((_) {
      if (!done.isCompleted) done.complete(null);
    }));
    try {
      final answeredAfter = await done.future;
      return _Round(buffer.toString(), answeredAfter);
    } finally {
      await sub.cancel();
    }
  }

  static TerminalWinsize? _noWinsize() => null;

  static Duration Function() _stopwatchElapsed() {
    final sw = Stopwatch()..start();
    return () => sw.elapsed;
  }

  static Future<void> _realDelay(Duration d) => Future<void>.delayed(d);
}

class _Round {
  _Round(this.text, this.answeredAfter);

  final String text;

  /// Time from query to DA1 reply; null on timeout.
  final Duration? answeredAfter;
}
