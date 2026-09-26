import '../framework/framework.dart';

/// Global selection drag state used to coordinate behavior across widgets.
class SelectionDragState {
  static int _activeCount = 0;
  static final Map<Object, SelectionRange> _ranges = {};

  /// Whether a selection drag is currently active.
  static bool get isActive => _activeCount > 0;

  /// Mark selection drag as active.
  static void begin() {
    _activeCount++;
  }

  /// Mark selection drag as inactive.
  static void end() {
    if (_activeCount > 0) {
      _activeCount--;
    }
    if (_activeCount == 0) {
      // A viewport reads its range during layout; dropping it must reach
      // the next layout, which a frame no longer runs by default.
      _ranges.keys.forEach(_markNeedsLayout);
      _ranges.clear();
    }
  }

  static void updateRange(Object context, int minIndex, int maxIndex) {
    if (minIndex > maxIndex) return;
    _ranges[context] = SelectionRange(minIndex, maxIndex);
    _markNeedsLayout(context);
  }

  /// A range is keyed by the viewport that reads it in `performLayout`.
  /// The bindings reuse the root constraints while the size holds, so a
  /// frame no longer re-lays out the whole tree: a changed range has to
  /// dirty its reader, or the viewport keeps building the old one.
  static void _markNeedsLayout(Object context) {
    if (context is RenderObject && !RenderObject.layoutInProgress) {
      context.markNeedsLayout();
    }
  }

  static SelectionRange? rangeFor(Object context) {
    return _ranges[context];
  }
}

class SelectionRange {
  SelectionRange(this.minIndex, this.maxIndex);

  final int minIndex;
  final int maxIndex;
}
