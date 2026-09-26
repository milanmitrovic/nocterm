import 'package:nocterm/nocterm.dart' hide TextAlign;
import 'package:nocterm/src/framework/terminal_canvas.dart';

import '../text/text_layout_engine.dart';

// Re-export text related enums
export '../text/text_layout_engine.dart' show TextOverflow, TextAlign;

/// Render object for displaying text
class RenderText extends RenderObject with Selectable {
  RenderText({
    required String text,
    TextStyle? style,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    TextAlign textAlign = TextAlign.left,
    int? maxLines,
  })  : _text = text,
        _style = style,
        _softWrap = softWrap,
        _overflow = overflow,
        _textAlign = textAlign,
        _maxLines = maxLines;

  String _text;
  String get text => _text;
  set text(String value) {
    if (_text == value) return;
    _text = value;
    _textLayoutStale = true;
    markNeedsLayout();
  }

  TextStyle? _style;
  TextStyle? get style => _style;
  set style(TextStyle? value) {
    if (_style == value) return;
    _style = value;
    markNeedsPaint();
  }

  bool _softWrap;
  bool get softWrap => _softWrap;
  set softWrap(bool value) {
    if (_softWrap == value) return;
    _softWrap = value;
    _textLayoutStale = true;
    markNeedsLayout();
  }

  TextOverflow _overflow;
  TextOverflow get overflow => _overflow;
  set overflow(TextOverflow value) {
    if (_overflow == value) return;
    _overflow = value;
    _textLayoutStale = true;
    markNeedsLayout();
  }

  TextAlign _textAlign;
  TextAlign get textAlign => _textAlign;
  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    markNeedsPaint();
  }

  int? _maxLines;
  int? get maxLines => _maxLines;
  set maxLines(int? value) {
    if (_maxLines == value) return;
    _maxLines = value;
    _textLayoutStale = true;
    markNeedsLayout();
  }

  TextLayoutResult? _layoutResult;

  /// Whether a setter changed an input of the text layout since the last
  /// one ran. With [_laidOutWidth] this is the whole key: the engine reads
  /// the text, softWrap, overflow, maxLines and the max width, and nothing
  /// else (textAlign is applied at paint).
  bool _textLayoutStale = true;
  int? _laidOutWidth;

  @override
  String get selectableText => _text;

  @override
  TextLayoutResult? get selectableLayout => _layoutResult;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void performLayout() {
    // For text alignment to work properly, we need to use the actual constraint width
    // When in a Column without stretch, we get infinite width, so we use intrinsic width
    final maxWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth.toInt()
        : double.maxFinite.toInt();

    // Debug: print constraint info
    // print('RenderText layout: text="$_text", constraints=$constraints, maxWidth=$maxWidth');

    // With no relayout boundaries, any dirty descendant re-lays out every
    // text on screen. Only redo the text layout when its inputs moved;
    // otherwise re-constrain the size against the new constraints.
    if (_textLayoutStale ||
        _layoutResult == null ||
        _laidOutWidth != maxWidth) {
      final config = TextLayoutConfig(
        softWrap: _softWrap,
        overflow: _overflow,
        textAlign: _textAlign,
        maxLines: _maxLines,
        maxWidth: maxWidth,
      );

      _layoutResult = TextLayoutEngine.layout(_text, config);
      _textLayoutStale = false;
      _laidOutWidth = maxWidth;
    }

    size = constraints.constrain(Size(
      _layoutResult!.actualWidth.toDouble(),
      _layoutResult!.actualHeight.toDouble(),
    ));
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);

    if (_layoutResult == null) return;

    final lines = _layoutResult!.lines;
    // Use the actual size width for alignment, not the constraint
    // The size has been constrained during layout
    final alignmentWidth = size.width.toInt();
    final style = _style;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Check if this is the last line of a paragraph for justification
      bool isLastLine = i == lines.length - 1;
      if (i < lines.length - 1) {
        // Check if next line starts a new paragraph (was preceded by newline)
        // This is a simplification - proper implementation would track paragraph boundaries
        isLastLine = false;
      }

      // Apply justification if needed
      String displayLine = line;
      if (_textAlign == TextAlign.justify && !isLastLine) {
        displayLine = TextLayoutEngine.justifyLine(line, alignmentWidth,
            isLastLine: isLastLine);
      }

      // Calculate horizontal offset based on text alignment
      final xOffset = offset.dx +
          TextLayoutEngine.calculateAlignmentOffset(
            displayLine,
            alignmentWidth,
            _textAlign,
          );

      // Apply clipping if needed
      if (_overflow == TextOverflow.clip && constraints.maxWidth.isFinite) {
        // The TextLayoutEngine already handles truncation, so we just paint what it gave us
        // But we might need to clip at the canvas level for safety
      }

      // Use selection-aware painting if there is an active selection
      if (hasSelection) {
        paintTextWithSelection(
          canvas,
          Offset(xOffset, offset.dy + i),
          displayLine,
          style,
          i,
        );
      } else {
        canvas.drawText(
          Offset(xOffset, offset.dy + i),
          displayLine,
          style: _style,
        );
      }
    }
  }
}
