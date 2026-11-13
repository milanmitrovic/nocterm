import 'dart:math' as math;

import 'package:nocterm/nocterm.dart' hide TextAlign;
import 'package:nocterm/src/framework/terminal_canvas.dart';

import '../text/text_layout_engine.dart';
import '../text/selection_utils.dart' as selection_utils;

/// Mixin that makes a [RenderObject] participate in text selection.
///
/// Any render object that displays selectable text should mix in this mixin
/// and implement [selectableText] and [selectableLayout].
///
/// A [SelectionArea] ancestor will discover these render objects by walking
/// the render subtree, and call [setSelectionRange] / [clearSelection] to
/// drive highlighting.
mixin Selectable on RenderObject {
  /// The plain-text content that can be selected.
  String get selectableText;

  /// The cached layout result (line-wrapped text).
  TextLayoutResult? get selectableLayout;

  int? _selectionStart;
  int? _selectionEnd;

  /// The color used to highlight selected text.
  Color? selectionColor;

  /// Current selection start (character index), or null if no selection.
  int? get selectionStart => _selectionStart;

  /// Current selection end (character index), or null if no selection.
  int? get selectionEnd => _selectionEnd;

  /// Whether this render object currently has a selection.
  bool get hasSelection =>
      _selectionStart != null &&
      _selectionEnd != null &&
      _selectionStart != _selectionEnd;

  /// Sets the selected character range. Pass null to clear.
  void setSelectionRange(int? start, int? end) {
    if (_selectionStart == start && _selectionEnd == end) return;
    _selectionStart = start;
    _selectionEnd = end;
    markNeedsPaint();
  }

  /// Clears the current selection, and its column clip.
  void clearSelection() {
    setSelectionRange(null, null);
    setSelectionClip(null, null);
  }

  int? _selectionClipLeft;
  int? _selectionClipRight;

  /// First column (local to this render object, inclusive) the selection
  /// is clipped to, or null for no left bound.
  int? get selectionClipLeft => _selectionClipLeft;

  /// Column after the last one (local, exclusive) the selection is clipped
  /// to, or null for no right bound.
  int? get selectionClipRight => _selectionClipRight;

  /// Whether the selection is clipped to a band of columns.
  bool get hasSelectionClip =>
      _selectionClipLeft != null || _selectionClipRight != null;

  /// Clips the selection to columns `[left, right)`, local to this render
  /// object: on every line, only the selected characters inside those
  /// columns are highlighted and copied. A [SelectionArea] sets this from
  /// a [SelectionSection]'s or [SelectionColumns]' band. Null bounds are
  /// open.
  void setSelectionClip(int? left, int? right) {
    if (_selectionClipLeft == left && _selectionClipRight == right) return;
    _selectionClipLeft = left;
    _selectionClipRight = right;
    markNeedsPaint();
  }

  /// Column (local to this render object) at which line [lineIndex] is
  /// painted — the text alignment's offset. Zero for left-aligned text.
  int selectionLineXOffset(int lineIndex) => 0;

  /// The selected `[start, end)` character range on line [lineIndex] of
  /// the layout, after the column clip; null when nothing on that line is
  /// selected.
  (int, int)? selectedRangeOnLine(int lineIndex) {
    final start = _selectionStart;
    final end = _selectionEnd;
    if (start == null || end == null || start == end) return null;
    final text = selectableText;
    final lines = selectableLayout?.lines ?? const <String>[];
    final selStart = math.min(start, end).clamp(0, text.length);
    final selEnd = math.max(start, end).clamp(0, text.length);
    final String line;
    final int lineStart;
    if (lines.isEmpty) {
      if (lineIndex != 0) return null;
      line = text;
      lineStart = 0;
    } else {
      if (lineIndex < 0 || lineIndex >= lines.length) return null;
      line = lines[lineIndex];
      lineStart = selection_utils.lineStartOffsets(text, lines)[lineIndex];
    }
    var a = math.max(selStart, lineStart);
    var b = math.min(selEnd, lineStart + line.length);
    if (a >= b) return null;
    if (hasSelectionClip) {
      final x0 = selectionLineXOffset(lineIndex);
      final (ca, cb) = selection_utils.charRangeForColumns(
        line,
        _selectionClipLeft == null ? null : _selectionClipLeft! - x0,
        _selectionClipRight == null ? null : _selectionClipRight! - x0,
      );
      a = math.max(a, lineStart + ca);
      b = math.min(b, lineStart + cb);
      if (a >= b) return null;
    }
    return (a, b);
  }

  /// Maps a local position (x, y) to a character index in [selectableText].
  ///
  /// Uses the layout result to determine which line the y coordinate falls on,
  /// then walks grapheme clusters on that line using [UnicodeWidth] to find the
  /// character at the x coordinate.
  int getCharacterIndexAtLocalPosition(Offset localPos) {
    return selection_utils.getCharacterIndexAtLocalPosition(
      localPos: localPos,
      text: selectableText,
      lines: selectableLayout?.lines ?? const [],
    );
  }

  /// Paints a single line of text with optional selection highlighting.
  ///
  /// This is extracted from [RenderTextField]'s `_paintLineWithSelection` so
  /// that any [Selectable] render object can reuse the same painting logic.
  void paintTextWithSelection(
    TerminalCanvas canvas,
    Offset offset,
    String line,
    TextStyle? style,
    int lineIndex,
  ) {
    // The line's own range: the selection on it, cut to the column clip.
    final range = selectedRangeOnLine(lineIndex);
    selection_utils.paintTextWithSelection(
      canvas: canvas,
      offset: offset,
      line: line,
      style: style,
      lineIndex: lineIndex,
      text: selectableText,
      lines: selectableLayout?.lines ?? const [],
      selectionStart: range?.$1,
      selectionEnd: range?.$2,
      selectionColor: selectionColor ?? Colors.blue,
    );
  }

  /// Computes the character offset of the start of each line in [text],
  /// given the layout [lines] (which don't contain `\n` characters).
  ///
  /// The layout engine strips `\n` when splitting into paragraphs, so the
  /// newline character sits at the offset immediately after each line's
  /// content rather than inside it.
  static List<int> lineStartOffsets(String text, List<String> lines) =>
      selection_utils.lineStartOffsets(text, lines);

  /// Computes the global paint offset of this render object by walking
  /// the parent chain and accumulating [BoxParentData] offsets.
  Offset get globalPaintOffset {
    double x = 0;
    double y = 0;
    RenderObject? node = this;
    while (node != null) {
      if (node.parentData is BoxParentData) {
        final pd = node.parentData as BoxParentData;
        x += pd.offset.dx;
        y += pd.offset.dy;
      }
      node = node.parent;
    }
    return Offset(x, y);
  }
}
