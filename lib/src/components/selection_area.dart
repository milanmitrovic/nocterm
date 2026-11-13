import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:nocterm/nocterm.dart' hide TextAlign;

import '../rendering/mouse_region.dart';
import 'render_stack.dart';
import '../rendering/mouse_tracker.dart';
import '../text/selection_utils.dart' as selection_utils;
import 'selection_state.dart';

/// A widget that enables mouse text selection across all descendant [Text]
/// widgets (or any render object that mixes in [Selectable]).
///
/// Wrap a subtree with [SelectionArea] to allow click-and-drag selection:
///
/// ```dart
/// SelectionArea(
///   child: Column(children: [
///     Text('First paragraph'),
///     Text('Second paragraph'),
///   ]),
/// )
/// ```
///
/// Selection is driven from the top: the [SelectionArea] captures pointer
/// events, walks its render subtree to discover [Selectable] render objects,
/// and tells each one which character range to highlight.
class SelectionArea extends StatefulComponent {
  const SelectionArea({
    super.key,
    required this.child,
    this.selectionColor,
    this.onSelectionChanged,
    this.onSelectionCompleted,
  });

  /// The child widget tree containing [Text] widgets to make selectable.
  final Component child;

  /// The color used to highlight selected text.
  /// If null, defaults to [TuiThemeData.selectionColor].
  final Color? selectionColor;

  /// Called when the selection changes. The callback receives the currently
  /// selected text (possibly spanning multiple widgets), or an empty string
  /// when the selection is cleared.
  final ValueChanged<String>? onSelectionChanged;

  /// Called when a drag selection completes (mouse up).
  /// Receives the selected text (or empty string if nothing is selected).
  final ValueChanged<String>? onSelectionCompleted;

  @override
  State<SelectionArea> createState() => _SelectionAreaState();
}

class _SelectionAreaState extends State<SelectionArea> {
  bool _isActive = false;
  final Map<Object, SelectionRange> _ranges = {};

  void _onDragStarted() {
    if (!_isActive) {
      setState(() {
        _isActive = true;
      });
    }
    // Also update global state for backwards compatibility
    SelectionDragState.begin();
  }

  void _onDragEnded() {
    SelectionDragState.end();
    if (_isActive) {
      setState(() {
        _isActive = false;
        _ranges.clear();
      });
    }
  }

  void _updateRange(Object context, int minIndex, int maxIndex) {
    if (minIndex > maxIndex) return;
    _ranges[context] = SelectionRange(minIndex, maxIndex);
    // Also update global state for backwards compatibility
    SelectionDragState.updateRange(context, minIndex, maxIndex);
  }

  SelectionRange? _rangeFor(Object context) {
    return _ranges[context];
  }

  @override
  void dispose() {
    if (_isActive) {
      // Ensure global drag state is cleaned up even if the widget unmounts
      // while a drag is in progress.
      SelectionDragState.end();
      _isActive = false;
      _ranges.clear();
    }
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final effectiveColor = component.selectionColor ?? theme.selectionColor;

    return SelectionScope(
      isActive: _isActive,
      rangeFor: _rangeFor,
      updateRange: _updateRange,
      child: _SelectionAreaWidget(
        selectionColor: effectiveColor,
        onSelectionChanged: component.onSelectionChanged,
        onSelectionCompleted: component.onSelectionCompleted,
        onDragStarted: _onDragStarted,
        onDragEnded: _onDragEnded,
        onRangeUpdated: _updateRange,
        child: component.child,
      ),
    );
  }
}

/// Internal single-child render object component.
class _SelectionAreaWidget extends SingleChildRenderObjectComponent {
  const _SelectionAreaWidget({
    required super.child,
    required this.selectionColor,
    this.onSelectionChanged,
    this.onSelectionCompleted,
    this.onDragStarted,
    this.onDragEnded,
    this.onRangeUpdated,
  });

  final Color selectionColor;
  final ValueChanged<String>? onSelectionChanged;
  final ValueChanged<String>? onSelectionCompleted;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;
  final void Function(Object context, int minIndex, int maxIndex)?
      onRangeUpdated;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSelectionArea(
      selectionColor: selectionColor,
      onSelectionChanged: onSelectionChanged,
      onSelectionCompleted: onSelectionCompleted,
      onDragStarted: onDragStarted,
      onDragEnded: onDragEnded,
      onRangeUpdated: onRangeUpdated,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, covariant RenderSelectionArea renderObject) {
    renderObject
      ..selectionColor = selectionColor
      ..onSelectionChanged = onSelectionChanged
      ..onSelectionCompleted = onSelectionCompleted
      ..onDragStarted = onDragStarted
      ..onDragEnded = onDragEnded
      ..onRangeUpdated = onRangeUpdated;
  }
}

/// Render object that drives cross-widget text selection.
///
/// It extends [RenderMouseRegion] so it can capture pointer down/move/up
/// events, and it walks its render subtree to discover [Selectable] children.
class RenderSelectionArea extends RenderMouseRegion {
  RenderSelectionArea({
    required Color selectionColor,
    this.onSelectionChanged,
    this.onSelectionCompleted,
    this.onDragStarted,
    this.onDragEnded,
    this.onRangeUpdated,
  }) : _selectionColor = selectionColor;

  Color _selectionColor;
  Color get selectionColor => _selectionColor;
  set selectionColor(Color value) {
    if (_selectionColor == value) return;
    _selectionColor = value;
    // Push color to all currently-selected selectables
    for (final s in _cachedSelectables) {
      s.selectionColor = value;
    }
    markNeedsPaint();
  }

  ValueChanged<String>? onSelectionChanged;
  ValueChanged<String>? onSelectionCompleted;
  VoidCallback? onDragStarted;
  VoidCallback? onDragEnded;
  void Function(Object context, int minIndex, int maxIndex)? onRangeUpdated;

  // Selection state
  bool _isDragging = false;
  bool _pendingPostFrameSelection = false;

  /// Sorted list of selectables discovered on pointer-down.
  List<Selectable> _cachedSelectables = [];
  Map<Object, List<_SelectableEntry>> _contextLists = {};

  // Selectables cache to avoid walking the tree on every mouse move
  bool _selectablesCacheValid = false;
  List<Selectable>? _selectablesCache;
  Map<Object, List<_SelectableEntry>>? _contextListsCache;

  /// The position where the pointer was initially pressed.
  Offset _pressPosition = Offset.zero;

  /// Anchor (start of drag) selectable and char index.
  _SelectionPosition? _anchor;

  /// Focus (current drag position) selectable and char index.
  _SelectionPosition? _focus;

  /// The section boundary the press landed in (that of the nearest
  /// [RenderSelectionSection] around the pressed selectable, else of the
  /// innermost one under the press cell — see [_sectionKeyOf]); null when
  /// the press is in no section. A late anchor is only taken from it.
  Object? _pressSection;

  /// Index of the band the drag is clipped to — the band of the anchor's
  /// [SelectionSection] / [SelectionColumns] that holds the press cell —
  /// or null when the anchor sits in no band.
  int? _pressBand;

  /// Global columns `[left, right)` of [_pressBand] on the anchor's row;
  /// the pointer's column is held inside it for the rest of the drag.
  (double, double)? _pressBandColumns;

  // Cache invalidation

  void _invalidateSelectablesCache() {
    _selectablesCacheValid = false;
    _selectablesCache = null;
    _contextListsCache = null;
  }

  @override
  void markNeedsLayout() {
    super.markNeedsLayout();
    _invalidateSelectablesCache();
  }

  @override
  void adoptChild(RenderObject child) {
    super.adoptChild(child);
    _invalidateSelectablesCache();
  }

  @override
  void dropChild(RenderObject child) {
    super.dropChild(child);
    _invalidateSelectablesCache();
  }

  // Gesture handling

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _updateSelectionAnnotation();
  }

  MouseTrackerAnnotation? _selectionAnnotation;

  @override
  MouseTrackerAnnotation? get annotation =>
      _selectionAnnotation ?? super.annotation;

  /// Whether the left mouse button is currently pressed inside this region.
  bool _isLeftButtonPressed = false;

  void _updateSelectionAnnotation() {
    _selectionAnnotation = MouseTrackerAnnotation(
      onEnter: (event) {
        if (event.button == MouseButton.left) {
          final leftDown = event.pressed || event.isPrimaryButtonDown;
          if (leftDown && !_isLeftButtonPressed) {
            _isLeftButtonPressed = true;
            _handlePointerDown(event);
          } else if (!leftDown) {
            _isLeftButtonPressed = false;
          }
        }
      },
      onExit: (event) {
        if (_isDragging) {
          // End drag when leaving the region. Otherwise a subsequent release
          // outside this region may never be dispatched back here.
          _isLeftButtonPressed = false;
          _handlePointerUp(event);
          return;
        }
        _isLeftButtonPressed = false;
      },
      onHover: (event) {
        if (event.button == MouseButton.wheelUp ||
            event.button == MouseButton.wheelDown) {
          if (_isDragging || event.isPrimaryButtonDown) {
            _handlePointerMove(event);
            _schedulePostFrameSelectionUpdate(event);
          }
          return;
        }

        if (event.button == MouseButton.left) {
          final leftDown = event.pressed || event.isPrimaryButtonDown;
          if (leftDown && !_isLeftButtonPressed) {
            _isLeftButtonPressed = true;
            _handlePointerDown(event);
          } else if (!leftDown && _isLeftButtonPressed) {
            _isLeftButtonPressed = false;
            _handlePointerUp(event);
          } else if (leftDown && _isLeftButtonPressed) {
            // Dragging
            _handlePointerMove(event);
          }
        }
      },
      renderObject: this,
    );
  }

  // Pointer event handlers
  void _handlePointerDown(MouseEvent event) {
    final localPos = Offset(event.x.toDouble(), event.y.toDouble());
    _pressPosition = localPos;
    if (!_isDragging) {
      onDragStarted?.call();
    }

    // Collect and sort selectables
    _cachedSelectables = _collectSelectables(this);
    _contextLists = _buildContextLists(_cachedSelectables);

    // Clear existing selections
    for (final s in _cachedSelectables) {
      s.clearSelection();
    }
    _pressBand = null;
    _pressBandColumns = null;

    // Hit-test to find which selectable contains the pointer
    final hit = _hitTestSelectables(localPos);
    _pressSection = hit != null
        ? _sectionKeyAbove(hit as RenderObject)
        : _sectionKeyOf(_innermostSectionAt(localPos));
    if (hit != null) {
      final localOffset = _globalToSelectableLocal(localPos, hit);
      final charIndex = hit.getCharacterIndexAtLocalPosition(localOffset);
      final contextKey = _contextKeyForSelectable(hit);
      final id = _selectionIdForSelectable(hit);
      final entries = _contextLists[contextKey];
      final entry = entries == null ? null : _entryForId(entries, id);

      _anchor = _SelectionPosition(
        context: contextKey,
        selectableId: id,
        offset: charIndex,
        orderIndex: entry == null ? null : entries!.indexOf(entry),
      );
      _focus = _SelectionPosition(
        context: contextKey,
        selectableId: id,
        offset: charIndex,
        orderIndex: entry == null ? null : entries!.indexOf(entry),
      );
      _setPressBand(entry);
      if (entries != null) {
        _updateSelectionRangeForViewport(
            entries, contextKey, _anchor!, _focus!);
      }
    } else {
      _anchor = null;
      _focus = null;
      // Don't set anchor/focus — will be set on first move
    }

    _isDragging = true; // Always start drag, even from whitespace
    _notifySelectionChanged();
  }

  void _handlePointerMove(MouseEvent event) {
    if (!_isDragging) return;

    final localPos = Offset(event.x.toDouble(), event.y.toDouble());
    _cachedSelectables = _collectSelectables(this);
    if (_cachedSelectables.isEmpty) return;
    _contextLists = _buildContextLists(_cachedSelectables);

    // Late anchor: first selectable the pointer touches becomes the anchor.
    if (_anchor == null) {
      final hit = _hitTestSelectables(localPos, section: _pressSection);
      if (hit != null) {
        final contextKey = _contextKeyForSelectable(hit);
        final id = _selectionIdForSelectable(hit);
        final localOffset = _globalToSelectableLocal(localPos, hit);
        final focusIndex = _focusIndexFromPress(hit, localPos, localOffset);
        final anchorIndex = _anchorIndexFromPress(hit);
        final entries = _contextLists[contextKey];
        final entry = entries == null ? null : _entryForId(entries, id);
        _anchor = _SelectionPosition(
          context: contextKey,
          selectableId: id,
          offset: anchorIndex,
          orderIndex: entry == null ? null : entries!.indexOf(entry),
        );
        _focus = _SelectionPosition(
          context: contextKey,
          selectableId: id,
          offset: focusIndex,
          orderIndex: entry == null ? null : entries!.indexOf(entry),
        );
        _setPressBand(entry);
      }
      _notifySelectionChanged();
      return;
    }

    final contextKey = _anchor!.context;
    final entries = _contextLists[contextKey];
    if (entries == null || entries.isEmpty) {
      _anchor = null;
      _focus = null;
      _notifySelectionChanged();
      return;
    }

    final anchorEntry = _entryForId(entries, _anchor!.selectableId);
    Selectable? anchorSelectable = anchorEntry?.selectable;
    if (anchorSelectable == null) {
      final reanchorEntry =
          _entryByClampedIndex(entries, _anchor!.orderIndex) ??
              _entryForId(
                entries,
                _anchor!.selectableId,
              );
      final reanchor = reanchorEntry?.selectable ??
          _hitTestSelectablesInContext(_pressPosition, entries) ??
          _nearestSelectableInContext(_pressPosition, entries);
      if (reanchor == null) {
        _anchor = null;
        _focus = null;
        _notifySelectionChanged();
        return;
      }
      final reanchorId = _selectionIdForSelectable(reanchor);
      final reanchorEntryResolved = _entryForId(entries, reanchorId);
      anchorSelectable = reanchor;
      _anchor = _SelectionPosition(
        context: contextKey,
        selectableId: reanchorId,
        offset: _anchorIndexFromPress(reanchor),
        orderIndex: reanchorEntryResolved == null
            ? null
            : entries.indexOf(reanchorEntryResolved),
      );
    }
    if (_anchor!.orderIndex == null && anchorEntry != null) {
      _anchor!.orderIndex = entries.indexOf(anchorEntry);
    }

    // Inside a band, the pointer's column is held in the band and only the
    // rows that take part in it can take the focus.
    final pointer = _clampToPressBand(localPos);
    final candidates = _pressBandColumns == null
        ? entries
        : entries.where(_isFocusCandidate).toList();
    final hit = _hitTestSelectablesInContext(pointer, candidates);
    final focusSelectable =
        hit ?? _nearestSelectableInContext(pointer, candidates);
    if (focusSelectable != null) {
      final localOffset = _globalToSelectableLocal(pointer, focusSelectable);
      final focusId = _selectionIdForSelectable(focusSelectable);
      final focusEntry = _entryForId(entries, focusId);
      _focus = _SelectionPosition(
        context: contextKey,
        selectableId: focusId,
        offset: _focusIndexFromPress(focusSelectable, pointer, localOffset),
        orderIndex: focusEntry == null ? null : entries.indexOf(focusEntry),
      );

      _updateSelectionRanges(
        entries,
        _anchor!,
        _focus!,
      );

      _updateSelectionRangeForViewport(entries, contextKey, _anchor!, _focus!);
    }

    _notifySelectionChanged();
  }

  void _updateSelectionRangeForViewport(
    List<_SelectableEntry> entries,
    Object contextKey,
    _SelectionPosition anchor,
    _SelectionPosition focus,
  ) {
    final scope =
        contextKey is _SectionGroupKey ? contextKey.scope : contextKey;
    if (scope is! RenderListViewport) return;
    final anchorEntry = _entryForId(entries, anchor.selectableId);
    final focusEntry = _entryForId(entries, focus.selectableId);
    final anchorIndex = anchorEntry?.listIndex;
    final focusIndex = focusEntry?.listIndex;
    if (anchorIndex == null || focusIndex == null) return;
    final minIndex = math.min(anchorIndex, focusIndex);
    final maxIndex = math.max(anchorIndex, focusIndex);
    onRangeUpdated?.call(scope, minIndex, maxIndex);
  }

  void _handlePointerUp(MouseEvent event) {
    if (_isDragging) {
      _handlePointerMove(event);
      onDragEnded?.call();
      markNeedsLayout();
    }
    _isDragging = false;
    // Keep selection visible (don't clear on mouse up)
    if (onSelectionCompleted == null) return;
    onSelectionCompleted!(_collectSelectedText());
  }

  /// Schedules a post-frame callback to re-apply selection after layout.
  ///
  /// When a wheel event fires during a drag, the scroll offset changes before
  /// layout runs. [_handlePointerMove] applies selection to the items currently
  /// in the tree, but the subsequent layout pass may remove and rebuild items
  /// (via [_forceBuildSelectionRange]). Those newly built items are fresh
  /// instances with no selection set, causing gaps. This callback re-applies
  /// selection after layout has completed.
  void _schedulePostFrameSelectionUpdate(MouseEvent event) {
    if (_pendingPostFrameSelection) return;
    _pendingPostFrameSelection = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pendingPostFrameSelection = false;
      if (!_isDragging) return;
      if (_anchor == null || _focus == null) return;

      _cachedSelectables = _collectSelectables(this);
      if (_cachedSelectables.isEmpty) return;
      _contextLists = _buildContextLists(_cachedSelectables);

      final contextKey = _anchor!.context;
      final entries = _contextLists[contextKey];
      if (entries == null || entries.isEmpty) return;

      // Re-resolve anchor and focus entries in the new entry list.
      final anchorEntry = _entryForId(entries, _anchor!.selectableId);
      final focusEntry = _entryForId(entries, _focus!.selectableId);
      if (anchorEntry != null) {
        _anchor!.orderIndex = entries.indexOf(anchorEntry);
      }
      if (focusEntry != null) {
        _focus!.orderIndex = entries.indexOf(focusEntry);
      }

      _updateSelectionRanges(entries, _anchor!, _focus!);
      _updateSelectionRangeForViewport(entries, contextKey, _anchor!, _focus!);
      _notifySelectionChanged();
    });
  }

  // Subtree walking
  /// Walks the render subtree rooted at [root] and collects all [Selectable]
  /// render objects, sorted in reading order (top-to-bottom, left-to-right).
  ///
  /// Results are cached to avoid walking the entire tree on every mouse move
  /// during drag selection. The cache is invalidated when layout changes.
  List<Selectable> _collectSelectables(RenderObject root) {
    if (_selectablesCacheValid && _selectablesCache != null) {
      return _selectablesCache!;
    }

    final result = <Selectable>[];
    void visit(RenderObject node) {
      if (node is Selectable) {
        result.add(node);
      }
      node.visitChildren(visit);
    }

    root.visitChildren(visit);

    // Sort by global paint position (y first, then x)
    result.sort((a, b) {
      final aPos = a.globalPaintOffset;
      final bPos = b.globalPaintOffset;
      final yCompare = aPos.dy.compareTo(bPos.dy);
      if (yCompare != 0) return yCompare;
      return aPos.dx.compareTo(bPos.dx);
    });

    _selectablesCache = result;
    _selectablesCacheValid = true;
    return result;
  }

  Object _selectionIdForSelectable(Selectable selectable) {
    final ro = selectable as RenderObject;
    return ro.selectionId ?? ro;
  }

  /// The group [selectable] is selected in: its nearest ungrouped
  /// [RenderSelectionSection] or scroll viewport ancestor (the nearest one
  /// wins), else this area — narrowed to the [SelectionSection.group] of
  /// the nearest grouped section below that scope, when there is one. A
  /// drag never leaves the group it started in.
  Object _contextKeyForSelectable(Selectable selectable) {
    Object? group;
    RenderObject? node = (selectable as RenderObject).parent;
    while (node != null && node != this) {
      if (node is RenderSelectionSection && node.group != null) {
        group ??= node.group;
      } else if (node is RenderSelectionSection ||
          node is RenderListViewport ||
          node is RenderSingleChildViewport) {
        return _grouped(node, group);
      }
      node = node.parent;
    }
    return _grouped(this, group);
  }

  static Object _grouped(Object scope, Object? group) =>
      group == null ? scope : _SectionGroupKey(scope, group);

  /// The scope a grouped section's group lives in: its nearest ungrouped
  /// [RenderSelectionSection] or scroll viewport ancestor, else this area.
  Object _scopeAbove(RenderObject ro) {
    RenderObject? node = ro.parent;
    while (node != null && node != this) {
      if ((node is RenderSelectionSection && node.group == null) ||
          node is RenderListViewport ||
          node is RenderSingleChildViewport) {
        return node;
      }
      node = node.parent;
    }
    return this;
  }

  /// The boundary [section] stands for: itself, or for a grouped section
  /// its group within its scope — so every row of one group compares equal.
  Object? _sectionKeyOf(RenderSelectionSection? section) {
    if (section == null) return null;
    final group = section.group;
    if (group == null) return section;
    return _SectionGroupKey(_scopeAbove(section), group);
  }

  /// The boundary of the nearest [RenderSelectionSection] above [ro] inside
  /// this area, or null.
  Object? _sectionKeyAbove(RenderObject ro) {
    RenderObject? node = ro.parent;
    while (node != null && node != this) {
      if (node is RenderSelectionSection) return _sectionKeyOf(node);
      node = node.parent;
    }
    return null;
  }

  /// The innermost [RenderSelectionSection] whose bounds hold [globalPos].
  RenderSelectionSection? _innermostSectionAt(Offset globalPos) {
    RenderSelectionSection? found;
    void visit(RenderObject node) {
      if (node is RenderSelectionSection && node.hasSize) {
        final o = _globalPaintOffsetOf(node);
        final r = Rect.fromLTWH(o.dx, o.dy, node.size.width, node.size.height);
        if (r.contains(globalPos)) found = node;
      }
      node.visitChildren(visit);
    }

    visitChildren(visit);
    return found;
  }

  /// The global column bands `[left, right)` [selectable] is clipped by: its
  /// nearest [RenderSelectionColumns], or the [RenderSelectionSection] that
  /// bounds it when that one declares columns; null when it is in no band.
  List<(double, double)>? _bandsForSelectable(Selectable selectable) {
    RenderObject? node = (selectable as RenderObject).parent;
    while (node != null && node != this) {
      if (node is RenderSelectionBands) {
        final bands = node.columns;
        if (bands == null) return null;
        final origin = _globalPaintOffsetOf(node).dx;
        final width = node.hasSize ? node.size.width : double.infinity;
        return [
          for (final b in bands)
            (
              origin + b.start,
              origin +
                  (b.end == null ? width : math.min(b.end!.toDouble(), width)),
            ),
        ];
      }
      node = node.parent;
    }
    return null;
  }

  int? _listIndexForSelectable(Selectable selectable) {
    RenderObject? node = selectable as RenderObject;
    while (node != null && node != this) {
      final parent = node.parent;
      if (parent is RenderListViewport) {
        final pd = node.parentData;
        if (pd is ListViewParentData) {
          return pd.index;
        }
      }
      node = parent;
    }
    return null;
  }

  /// Builds context lists from selectables, using cache when available.
  Map<Object, List<_SelectableEntry>> _buildContextLists(
      List<Selectable> selectables) {
    if (_selectablesCacheValid && _contextListsCache != null) {
      return _contextListsCache!;
    }

    final lists = <Object, List<_SelectableEntry>>{};
    final baseBounds = _selectionAreaBounds();
    for (final selectable in selectables) {
      final ro = selectable as RenderObject;
      final origin = selectable.globalPaintOffset;
      final bounds = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        ro.hasSize ? ro.size.width : 0,
        ro.hasSize ? ro.size.height : 0,
      );
      // A row a clip hides entirely (one scrolled out of a ClipRect window,
      // say) takes no part in a selection: it is neither hit, nor between
      // anchor and focus, nor copied. Rows a scroll viewport hides stay, so
      // a drag that scrolls keeps the rows it scrolled past.
      if (_clipBoundsForSelectable(selectable, baseBounds, viewports: false) ==
          null) {
        continue;
      }
      final clip = _clipBoundsForSelectable(selectable, baseBounds);
      final contextKey = _contextKeyForSelectable(selectable);
      final entry = _SelectableEntry(
        selectable: selectable,
        id: _selectionIdForSelectable(selectable),
        contextKey: contextKey,
        bounds: bounds,
        listIndex: _listIndexForSelectable(selectable),
        bands: _bandsForSelectable(selectable),
        visibleColumns: clip != null &&
                (clip.left > bounds.left || clip.right < bounds.right)
            ? (clip.left, clip.right)
            : null,
      );
      lists.putIfAbsent(contextKey, () => []).add(entry);
    }

    for (final list in lists.values) {
      list.sort(_compareByPosition);
    }

    _contextListsCache = lists;
    return lists;
  }

  int _compareByPosition(_SelectableEntry a, _SelectableEntry b) {
    final yCompare = a.bounds.top.compareTo(b.bounds.top);
    if (yCompare != 0) return yCompare;
    return a.bounds.left.compareTo(b.bounds.left);
  }

  _SelectableEntry? _entryForId(
      List<_SelectableEntry> entries, Object selectableId) {
    for (final entry in entries) {
      if (entry.id == selectableId) return entry;
    }
    return null;
  }

  _SelectableEntry? _entryByClampedIndex(
      List<_SelectableEntry> entries, int? index) {
    if (entries.isEmpty || index == null) return null;
    final clamped = index.clamp(0, entries.length - 1);
    return entries[clamped];
  }

  // Hit testing selectables
  /// Returns the [Selectable] whose bounds contain [globalPos], or null.
  /// With a [section] boundary (see [_sectionKeyOf]), only one inside it.
  Selectable? _hitTestSelectables(
    Offset globalPos, {
    Object? section,
  }) {
    final baseBounds = _selectionAreaBounds();
    for (final s in _cachedSelectables) {
      if (section != null && _sectionKeyAbove(s as RenderObject) != section) {
        continue;
      }
      final origin = s.globalPaintOffset;
      final ro = s as RenderObject;
      if (!ro.hasSize) continue;
      final sBounds = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        ro.size.width,
        ro.size.height,
      );
      final clipBounds = _clipBoundsForSelectable(s, baseBounds);
      if (clipBounds == null) continue;
      final visibleBounds = _intersectRect(sBounds, clipBounds);
      if (visibleBounds == null) continue;
      if (globalPos.dx >= visibleBounds.left &&
          globalPos.dx < visibleBounds.right &&
          globalPos.dy >= visibleBounds.top &&
          globalPos.dy < visibleBounds.bottom) {
        return s;
      }
    }
    return null;
  }

  /// Returns the nearest [Selectable] to [globalPos] when the pointer is
  /// outside all selectables (e.g. dragging past the last line).
  Selectable? _hitTestSelectablesInContext(
    Offset globalPos,
    List<_SelectableEntry> entries,
  ) {
    final baseBounds = _selectionAreaBounds();
    for (final entry in entries) {
      final s = entry.selectable;
      final ro = s as RenderObject;
      if (!ro.hasSize) continue;
      final sBounds = entry.bounds;
      final clipBounds = _clipBoundsForSelectable(s, baseBounds);
      if (clipBounds == null) continue;
      final visibleBounds = _intersectRect(sBounds, clipBounds);
      if (visibleBounds == null) continue;
      if (globalPos.dx >= visibleBounds.left &&
          globalPos.dx < visibleBounds.right &&
          globalPos.dy >= visibleBounds.top &&
          globalPos.dy < visibleBounds.bottom) {
        return s;
      }
    }
    return null;
  }

  Selectable? _nearestSelectableInContext(
    Offset globalPos,
    List<_SelectableEntry> entries,
  ) {
    if (entries.isEmpty) return null;

    final baseBounds = _selectionAreaBounds();
    Selectable? nearest;
    double minDy = double.infinity;
    double minDx = double.infinity;

    for (final entry in entries) {
      final s = entry.selectable;
      final ro = s as RenderObject;
      if (!ro.hasSize) continue;
      final sBounds = entry.bounds;
      final clipBounds = _clipBoundsForSelectable(s, baseBounds);
      if (clipBounds == null) continue;
      final visibleBounds = _intersectRect(sBounds, clipBounds);
      if (visibleBounds == null) continue;
      // Prefer vertical proximity first, then horizontal proximity.
      final dy = globalPos.dy < visibleBounds.top
          ? visibleBounds.top - globalPos.dy
          : (globalPos.dy >= visibleBounds.bottom
              ? globalPos.dy - (visibleBounds.bottom - 1)
              : 0.0);
      final dx = globalPos.dx < visibleBounds.left
          ? visibleBounds.left - globalPos.dx
          : (globalPos.dx >= visibleBounds.right
              ? globalPos.dx - (visibleBounds.right - 1)
              : 0.0);
      if (dy < minDy || (dy == minDy && dx < minDx)) {
        minDy = dy;
        minDx = dx;
        nearest = s;
      }
    }

    return nearest;
  }

  int _anchorIndexFromPress(Selectable selectable) {
    final ro = selectable as RenderObject;
    if (!ro.hasSize) {
      final localOffset = _globalToSelectableLocal(_pressPosition, selectable);
      return selectable.getCharacterIndexAtLocalPosition(localOffset);
    }
    final origin = selectable.globalPaintOffset;
    final top = origin.dy;
    final bottom = origin.dy + ro.size.height;
    if (_pressPosition.dy < top) {
      return 0;
    }
    if (_pressPosition.dy >= bottom) {
      return selectable.selectableText.length;
    }
    final localOffset = _globalToSelectableLocal(_pressPosition, selectable);
    return selectable.getCharacterIndexAtLocalPosition(localOffset);
  }

  int _focusIndexFromPress(
    Selectable selectable,
    Offset globalPos,
    Offset localOffset,
  ) {
    final ro = selectable as RenderObject;
    if (!ro.hasSize) {
      return selectable.getCharacterIndexAtLocalPosition(localOffset);
    }
    final origin = selectable.globalPaintOffset;
    final top = origin.dy;
    final bottom = origin.dy + ro.size.height;
    final isInside = globalPos.dy >= top && globalPos.dy < bottom;
    if (globalPos.dy < top) {
      return 0;
    }
    if (globalPos.dy >= bottom) {
      return selectable.selectableText.length;
    }
    // If press started below this selectable and we're dragging upward into it,
    // snap focus to end-of-line for initial row entry.
    if (!isInside &&
        _pressPosition.dy >= bottom &&
        globalPos.dy < _pressPosition.dy) {
      return selectable.selectableText.length;
    }
    return selectable.getCharacterIndexAtLocalPosition(localOffset);
  }

  /// Converts a position in the SelectionArea's coordinate space to a
  /// position local to the given [Selectable].
  Offset _globalToSelectableLocal(Offset globalPos, Selectable selectable) {
    final origin = selectable.globalPaintOffset;
    return Offset(globalPos.dx - origin.dx, globalPos.dy - origin.dy);
  }

  // Cross-widget selection logic
  /// Updates the per-widget selection ranges based on the current anchor and
  /// focus positions.
  void _updateSelectionRanges(
    List<_SelectableEntry> entries,
    _SelectionPosition anchor,
    _SelectionPosition focus,
  ) {
    final anchorEntry = _entryForId(entries, anchor.selectableId);
    final focusEntry = _entryForId(entries, focus.selectableId);
    if (anchorEntry == null || focusEntry == null) return;

    final anchorIdx = entries.indexOf(anchorEntry);
    final focusIdx = entries.indexOf(focusEntry);
    if (anchorIdx < 0 || focusIdx < 0) return;

    final forward = anchorIdx < focusIdx ||
        (anchorIdx == focusIdx && anchor.offset <= focus.offset);

    int startIdx = math.min(anchorIdx, focusIdx);
    int endIdx = math.max(anchorIdx, focusIdx);

    for (int i = 0; i < entries.length; i++) {
      final s = entries[i].selectable;
      s.selectionColor = _selectionColor;

      if (i < startIdx || i > endIdx) {
        // Outside the selection span
        s.clearSelection();
      } else if (anchorIdx == focusIdx) {
        // Single widget selection
        final len = s.selectableText.length;
        final start = anchor.offset.clamp(0, len);
        final end = focus.offset.clamp(0, len);
        s.setSelectionRange(start, end);
      } else if (i == anchorIdx) {
        // Anchor widget
        if (forward) {
          final len = s.selectableText.length;
          final start = anchor.offset.clamp(0, len);
          s.setSelectionRange(start, len);
        } else {
          final len = s.selectableText.length;
          final end = anchor.offset.clamp(0, len);
          s.setSelectionRange(0, end);
        }
      } else if (i == focusIdx) {
        // Focus widget
        if (forward) {
          final len = s.selectableText.length;
          final end = focus.offset.clamp(0, len);
          s.setSelectionRange(0, end);
        } else {
          final len = s.selectableText.length;
          final start = focus.offset.clamp(0, len);
          s.setSelectionRange(start, len);
        }
      } else {
        // Widgets between anchor and focus: fully selected
        s.setSelectionRange(0, s.selectableText.length);
      }

      if (i >= startIdx && i <= endIdx) _applyBandClip(entries[i]);
    }
  }

  /// Clips [entry]'s selection to the drag's band (see [SelectionColumns]
  /// for how bands meet rows without any): its own band of the same index,
  /// band 0 for a drag that started in no band, nothing for a row with no
  /// such band, and no clip at all for an unsplit row under band 0 — and in
  /// every case to the columns a clip leaves visible, so text a clip hides
  /// is never highlighted or copied.
  void _applyBandClip(_SelectableEntry entry) {
    final s = entry.selectable;
    final bands = entry.bands;
    final band = _pressBand;
    (double, double)? columns;
    if (bands == null) {
      if (band != null && band != 0) {
        s.clearSelection();
        return;
      }
    } else {
      final index = band ?? 0;
      if (index >= bands.length) {
        s.clearSelection();
        return;
      }
      columns = bands[index];
    }
    final visible = entry.visibleColumns;
    if (visible != null) {
      columns = columns == null
          ? visible
          : (
              math.max(columns.$1, visible.$1),
              math.min(columns.$2, visible.$2),
            );
    }
    if (columns == null) {
      s.setSelectionClip(null, null);
      return;
    }
    final (left, right) = columns;
    if (right <= left) {
      s.clearSelection();
      return;
    }
    final originX = s.globalPaintOffset.dx;
    s.setSelectionClip(
      (left - originX).round(),
      right.isFinite ? (right - originX).round() : null,
    );
  }

  /// Sets the drag's band from the anchor [entry]: the band holding the
  /// press column, or the nearest band to a press in a gap between them.
  void _setPressBand(_SelectableEntry? entry) {
    final bands = entry?.bands;
    if (bands == null || bands.isEmpty) {
      _pressBand = null;
      _pressBandColumns = null;
      return;
    }
    final x = _pressPosition.dx;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < bands.length; i++) {
      final (left, right) = bands[i];
      final distance = x < left
          ? left - x
          : x >= right
              ? x - right + 1
              : 0.0;
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    _pressBand = best;
    _pressBandColumns = bands[best];
  }

  /// [pos] with its column held inside the drag's band — up to the column
  /// just past it, where the caret sits after the band's last cell.
  Offset _clampToPressBand(Offset pos) {
    final columns = _pressBandColumns;
    if (columns == null) return pos;
    final (left, right) = columns;
    final maxX = right.isFinite ? right : pos.dx;
    if (maxX < left) return Offset(left, pos.dy);
    return Offset(pos.dx.clamp(left, maxX).toDouble(), pos.dy);
  }

  /// Whether [entry] can take the focus of a drag inside a band: it takes
  /// part in the band ([_applyBandClip]) and reaches into its columns.
  bool _isFocusCandidate(_SelectableEntry entry) {
    final band = _pressBand!;
    final bands = entry.bands;
    if (bands == null) return band == 0;
    if (band >= bands.length) return false;
    final (left, right) = bands[band];
    return entry.bounds.left < right && entry.bounds.right > left;
  }

  /// Notifies the callback with the currently selected text.
  void _notifySelectionChanged() {
    if (onSelectionChanged == null) return;
    onSelectionChanged!(_collectSelectedText());
  }

  String _collectSelectedText() {
    return _collectSelectedTextFromVisible();
  }

  String _collectSelectedTextFromVisible() {
    final buf = StringBuffer();
    int? lastBottomRow;

    for (final s in _cachedSelectables) {
      if (!s.hasSelection) continue;
      if (!_appendSelectedTextFromSelectable(buf, s, lastBottomRow)) {
        continue;
      }
      lastBottomRow = _lastBottomRow;
    }
    return buf.toString();
  }

  @visibleForTesting
  String debugAppendSelectedText({
    required String initial,
    required String text,
    required List<String> lines,
    required int start,
    required int end,
    required int topRow,
    required int height,
    int? lastBottomRow,
  }) {
    final buf = StringBuffer(initial);
    _appendSelectedText(
      buf,
      text: text,
      lines: lines,
      start: start,
      end: end,
      topRow: topRow,
      height: height,
      lastBottomRow: lastBottomRow,
    );
    return buf.toString();
  }

  int? _lastBottomRow;

  bool _appendSelectedTextFromSelectable(
    StringBuffer buf,
    Selectable s,
    int? lastBottomRow,
  ) {
    if (s.hasSelectionClip) {
      return _appendClippedTextFromSelectable(buf, s, lastBottomRow);
    }
    final text = s.selectableText;
    final len = text.length;
    final rawStart = math.min(s.selectionStart!, s.selectionEnd!);
    final rawEnd = math.max(s.selectionStart!, s.selectionEnd!);
    final start = rawStart.clamp(0, len);
    final end = rawEnd.clamp(0, len);
    if (start >= end) return false;

    final ro = s as RenderObject;
    final origin = s.globalPaintOffset;
    final height = ro.hasSize ? ro.size.height.ceil() : 1;
    final layout = s.selectableLayout;
    final lines = layout?.lines;
    _appendSelectedText(
      buf,
      text: text,
      lines: lines,
      start: start,
      end: end,
      topRow: origin.dy.floor(),
      height: height,
      lastBottomRow: lastBottomRow,
    );
    return true;
  }

  /// [_appendSelectedText] for a selectable whose selection is clipped to a
  /// band: each line's clipped run, joined by the same rules — a newline
  /// when the run is on a lower row than the last text written, a space
  /// otherwise.
  bool _appendClippedTextFromSelectable(
    StringBuffer buf,
    Selectable s,
    int? lastBottomRow,
  ) {
    final text = s.selectableText;
    final lines = s.selectableLayout?.lines ?? const <String>[];
    final topRow = s.globalPaintOffset.dy.floor();
    final lineCount = lines.isEmpty ? 1 : lines.length;
    var wrote = false;
    for (var li = 0; li < lineCount; li++) {
      final range = s.selectedRangeOnLine(li);
      if (range == null) continue;
      final lineRow = topRow + li;
      if (buf.isNotEmpty) {
        if (lastBottomRow != null && lineRow > lastBottomRow) {
          buf.write('\n');
        } else {
          buf.write(' ');
        }
      }
      lastBottomRow = lineRow;
      buf.write(text.substring(range.$1, range.$2));
      wrote = true;
    }
    if (wrote) _lastBottomRow = lastBottomRow;
    return wrote;
  }

  void _appendSelectedText(
    StringBuffer buf, {
    required String text,
    required List<String>? lines,
    required int start,
    required int end,
    required int topRow,
    required int height,
    required int? lastBottomRow,
  }) {
    if (start >= end) return;

    if (lines != null && lines.length > 1) {
      // Multi-line: iterate lines, only include visible ones
      final lineStarts = selection_utils.lineStartOffsets(text, lines);
      for (int li = 0; li < lines.length; li++) {
        final lineRow = topRow + li;

        final lineStart = lineStarts[li];
        final lineEnd = lineStart + lines[li].length;
        final selStart = math.max(start, lineStart);
        final selEnd = math.min(end, lineEnd);
        if (selStart >= selEnd) continue;

        if (buf.isNotEmpty) {
          if (lastBottomRow != null && lineRow > lastBottomRow) {
            buf.write('\n');
          } else {
            buf.write(' ');
          }
        }
        lastBottomRow = lineRow;
        buf.write(text.substring(selStart, selEnd));
      }
      _lastBottomRow = lastBottomRow;
      return;
    }

    // Single-line (or no layout)
    final bottomRow = topRow + height - 1;

    if (buf.isNotEmpty) {
      if (lastBottomRow != null && topRow > lastBottomRow) {
        buf.write('\n');
      } else {
        buf.write(' ');
      }
    }
    _lastBottomRow = bottomRow;
    buf.write(text.substring(start, end));
  }

  /// Global paint offset of this render object.
  Offset _globalPaintOffset() => _globalPaintOffsetOf(this);

  Rect _selectionAreaBounds() {
    final baseOffset = _globalPaintOffset();
    return Rect.fromLTWH(
      baseOffset.dx,
      baseOffset.dy,
      hasSize ? size.width : double.infinity,
      hasSize ? size.height : double.infinity,
    );
  }

  /// Global paint offset of any render object.
  static Offset _globalPaintOffsetOf(RenderObject node) {
    double x = 0;
    double y = 0;
    RenderObject? current = node;
    while (current != null) {
      if (current.parentData is BoxParentData) {
        final pd = current.parentData as BoxParentData;
        x += pd.offset.dx;
        y += pd.offset.dy;
      }
      current = current.parent;
    }
    return Offset(x, y);
  }

  static bool _isViewport(RenderObject node) =>
      node is RenderListViewport || node is RenderSingleChildViewport;

  /// Whether [node] clips what its subtree paints to its own bounds: a
  /// scroll viewport, a [RenderClipRect] or a [RenderStack] that clips.
  static bool _clipsToBounds(RenderObject node) =>
      _isViewport(node) ||
      (node is RenderClipRect && node.clipBehavior != Clip.none) ||
      (node is RenderStack && node.clipBehavior != Clip.none);

  /// Walk the parent chain of [selectable] up to this SelectionArea,
  /// intersecting with the bounds of every clip encountered (see
  /// [_clipsToBounds]); null when they hide [selectable] entirely.
  ///
  /// With [viewports] false the walk asks only whether the clips between
  /// [selectable] and its nearest scroll viewport hide it — a row scrolled
  /// out of a viewport still takes part in a drag that scrolls; one cut
  /// off by a [ClipRect] window does not.
  Rect? _clipBoundsForSelectable(
    Selectable selectable,
    Rect baseBounds, {
    bool viewports = true,
  }) {
    final ro = selectable as RenderObject;
    Rect? clip = baseBounds;
    if (!viewports) {
      final origin = selectable.globalPaintOffset;
      clip = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        ro.hasSize ? math.max(ro.size.width, 1) : 1,
        ro.hasSize ? math.max(ro.size.height, 1) : 1,
      );
    }
    RenderObject? node = ro.parent;
    while (node != null && node != this) {
      if (!viewports && _isViewport(node)) break;
      if (_clipsToBounds(node)) {
        final vpOffset = _globalPaintOffsetOf(node);
        final vpBounds = Rect.fromLTWH(
          vpOffset.dx,
          vpOffset.dy,
          node.hasSize ? node.size.width : double.infinity,
          node.hasSize ? node.size.height : double.infinity,
        );
        clip = clip == null ? vpBounds : _intersectRect(clip, vpBounds);
        if (clip == null) return null; // fully clipped
      }
      node = node.parent;
    }
    return clip;
  }

  /// Intersect two rects, returning null if the result is empty.
  static Rect? _intersectRect(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    if (left >= right || top >= bottom) return null;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool hitTestSelf(Offset position) => true;
}

/// The boundary formed by every [RenderSelectionSection] whose
/// [RenderSelectionSection.group] equals [group] under [scope] — a scroll
/// viewport, an ungrouped section or the [RenderSelectionArea].
@immutable
class _SectionGroupKey {
  const _SectionGroupKey(this.scope, this.group);

  final Object scope;
  final Object group;

  @override
  bool operator ==(Object other) =>
      other is _SectionGroupKey &&
      identical(other.scope, scope) &&
      other.group == group;

  @override
  int get hashCode => Object.hash(identityHashCode(scope), group);
}

class _SelectionPosition {
  _SelectionPosition({
    required this.context,
    required this.selectableId,
    required this.offset,
    this.orderIndex,
  });

  final Object context;
  final Object selectableId;
  final int offset;
  int? orderIndex;
}

class _SelectableEntry {
  _SelectableEntry({
    required this.selectable,
    required this.id,
    required this.contextKey,
    required this.bounds,
    required this.listIndex,
    this.bands,
    this.visibleColumns,
  });

  final Selectable selectable;
  final Object id;
  final Object contextKey;
  final Rect bounds;
  final int? listIndex;

  /// Global column bands this selectable is clipped by, or null.
  final List<(double, double)>? bands;

  /// Global columns `[left, right)` a clip leaves visible of this
  /// selectable, when a clip hides some of its columns; else null.
  final (double, double)? visibleColumns;
}
