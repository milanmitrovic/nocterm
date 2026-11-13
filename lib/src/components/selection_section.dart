import 'package:nocterm/nocterm.dart' hide TextAlign;
import 'package:nocterm/src/framework/terminal_canvas.dart';

/// A vertical band of columns `[start, end)` inside a [SelectionSection] or
/// [SelectionColumns], in that widget's own local columns.
///
/// A null [end] runs the band to the widget's right edge.
class SelectionBand {
  const SelectionBand(this.start, [this.end]) : group = null;

  /// A band whose columns form a boundary of their own, shared with every
  /// band and [SelectionSection] of the same [group] under the same scope
  /// (scroll viewport, ungrouped section or area).
  ///
  /// For a panel that runs down beside rows of other boundaries — a
  /// sidebar beside a page whose rows are split into titled sections, all
  /// drawn as one line of text per row: the sidebar band of every row is
  /// one boundary, whatever section the rest of its row belongs to. A drag
  /// that starts in a grouped band selects that band's columns of every
  /// row of its group, and nothing else; a drag that starts elsewhere on
  /// the row never selects the grouped band's columns.
  const SelectionBand.grouped(Object this.group, this.start, [this.end]);

  /// First column of the band (inclusive).
  final int start;

  /// Column after the band's last one (exclusive), or null for the widget's
  /// right edge.
  final int? end;

  /// The boundary the band's columns belong to (see [SelectionBand.grouped]),
  /// or null for the boundary of the row it is on.
  final Object? group;

  @override
  bool operator ==(Object other) =>
      other is SelectionBand &&
      other.start == start &&
      other.end == end &&
      other.group == group;

  @override
  int get hashCode => Object.hash(start, end, group);

  @override
  String toString() => 'SelectionBand($start, ${end ?? 'end'}'
      '${group == null ? '' : ', group: $group'})';
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
///
/// A section is one render object, so it can only bound a subtree. Inside a
/// [ListView], where a visual section is many separately built rows, give
/// each row of the section a [SelectionSection] with the same [group]
/// instead: all sections that share a [group] (by `==`) under the same
/// scroll viewport (or the same enclosing section) form ONE boundary. A
/// drag that starts in a row of one group then never reaches the rows of
/// another, even though they scroll in one viewport.
class SelectionSection extends SingleChildRenderObjectComponent {
  const SelectionSection({
    super.key,
    this.columns,
    this.group,
    required Component child,
  }) : super(child: child);

  /// Column bands, local to this section, or null for one band spanning
  /// the whole section.
  final List<SelectionBand>? columns;

  /// The boundary this section is part of, or null for a boundary of its
  /// own. Sections with equal groups under one scroll viewport (or one
  /// enclosing section) are one boundary.
  final Object? group;

  @override
  RenderSelectionSection createRenderObject(BuildContext context) =>
      RenderSelectionSection(columns: columns, group: group);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderSelectionSection renderObject,
  ) {
    renderObject
      ..columns = columns
      ..group = group;
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
  RenderSelectionSection({super.columns, Object? group}) : _group = group;

  Object? _group;

  /// See [SelectionSection.group].
  Object? get group => _group;
  set group(Object? value) {
    if (_group == value) return;
    _group = value;
    // Like the bands, a group changes no pixels; the layout mark drops the
    // SelectionArea's cached grouping.
    markNeedsLayout();
  }
}

/// Render object of [SelectionColumns].
class RenderSelectionColumns extends RenderSelectionBands {
  RenderSelectionColumns({required List<SelectionBand> columns})
      : super(columns: columns);
}
