import 'package:nocterm/nocterm.dart' hide TextAlign;
import 'package:nocterm/src/framework/terminal_canvas.dart';

/// A vertical band of columns `[start, end)` inside a [SelectionSection] or
/// [SelectionColumns], in that widget's own local columns.
///
/// A null [end] runs the band to the widget's right edge.
class SelectionBand {
  const SelectionBand(this.start, [this.end]);

  /// First column of the band (inclusive).
  final int start;

  /// Column after the band's last one (exclusive), or null for the widget's
  /// right edge.
  final int? end;

  @override
  bool operator ==(Object other) =>
      other is SelectionBand && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SelectionBand($start, ${end ?? 'end'})';
}

/// A selection boundary inside a [SelectionArea].
///
/// A drag that starts inside a [SelectionSection] stays inside it: the
/// selection is grouped by the nearest [SelectionSection] or scroll
/// viewport ancestor of each [Selectable] (the nearest one wins), and only
/// the group the press landed in can be selected. Wrap each visually
/// separate panel (a title bar, a status line, a body) in its own section
/// so a drag in one never sweeps into another.
///
/// [columns] splits the section into side-by-side panels that share rows —
/// a text column and a sidebar drawn as one line of text per row, say. The
/// band containing the press cell (or the nearest one, for a press in a
/// gap between bands) becomes the clip region: the drag cannot leave it,
/// and every selected [Selectable] is highlighted and copied only on the
/// columns inside that band. A selection over several rows of one band
/// reads top to bottom within the band.
///
/// When only some rows of a section are split, leave [columns] null and
/// wrap those rows in [SelectionColumns] instead.
class SelectionSection extends SingleChildRenderObjectComponent {
  const SelectionSection({
    super.key,
    this.columns,
    required Component child,
  }) : super(child: child);

  /// Column bands, local to this section, or null for one band spanning
  /// the whole section.
  final List<SelectionBand>? columns;

  @override
  RenderSelectionSection createRenderObject(BuildContext context) =>
      RenderSelectionSection(columns: columns);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSelectionSection renderObject,
  ) {
    renderObject.columns = columns;
  }
}

/// Declares column bands for the [Selectable]s under it, without being a
/// selection boundary.
///
/// For a [SelectionSection] in which only some rows are split into
/// side-by-side panels — a page whose header runs the full width above a
/// text | sidebar split — wrap each split row in a [SelectionColumns] with
/// the same [columns]. Bands are matched by INDEX across rows: a drag that
/// starts in band `i` of one row is clipped to band `i` of every row it
/// covers.
///
/// Band 0 is the primary band: it is the one that continues into rows with
/// no bands. A drag that starts in band 0 also selects the unsplit rows it
/// covers, in full, and a drag that starts in an unsplit row selects band 0
/// of the split rows it reaches. A drag that starts in any other band
/// selects only that band.
class SelectionColumns extends SingleChildRenderObjectComponent {
  const SelectionColumns({
    super.key,
    required this.columns,
    required Component child,
  }) : super(child: child);

  /// Column bands, local to this widget.
  final List<SelectionBand> columns;

  @override
  RenderSelectionColumns createRenderObject(BuildContext context) =>
      RenderSelectionColumns(columns: columns);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSelectionColumns renderObject,
  ) {
    renderObject.columns = columns;
  }
}

/// Pass-through single-child render object carrying selection bands.
abstract class RenderSelectionBands extends RenderObject
    with RenderObjectWithChildMixin<RenderObject> {
  RenderSelectionBands({List<SelectionBand>? columns}) : _columns = columns;

  List<SelectionBand>? _columns;

  /// The bands this render object declares, local to it; null for none.
  List<SelectionBand>? get columns => _columns;
  set columns(List<SelectionBand>? value) {
    if (_sameBands(_columns, value)) return;
    _columns = value;
    // Bands change no pixels until the next drag; the SelectionArea reads
    // them afresh on every press. A layout mark invalidates its caches.
    markNeedsLayout();
  }

  static bool _sameBands(List<SelectionBand>? a, List<SelectionBand>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! BoxParentData) {
      child.parentData = BoxParentData();
    }
  }

  @override
  void performLayout() {
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
    } else {
      size = constraints.constrain(Size.zero);
    }
  }

  @override
  void paint(TerminalCanvas canvas, Offset offset) {
    super.paint(canvas, offset);
    if (child != null) {
      final pd = child!.parentData as BoxParentData;
      child!.paint(canvas, offset + pd.offset);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, {required Offset position}) {
    if (child == null) return false;
    final pd = child!.parentData as BoxParentData;
    return child!.hitTest(result, position: position - pd.offset);
  }
}

/// Render object of [SelectionSection].
class RenderSelectionSection extends RenderSelectionBands {
  RenderSelectionSection({super.columns});
}

/// Render object of [SelectionColumns].
class RenderSelectionColumns extends RenderSelectionBands {
  RenderSelectionColumns({required List<SelectionBand> columns})
      : super(columns: columns);
}
