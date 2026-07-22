import 'package:nocterm/nocterm.dart';
import 'package:nocterm/src/navigation/render_theater.dart';
import 'package:nocterm/src/rendering/scrollable_render_object.dart';

/// Depth-first dispatch of a mouse-wheel [event] to the scrollable render
/// object under [mousePos].
///
/// Shared by [TerminalBinding] and the test binding so wheel behavior is
/// identical in production and under `testNocterm` — the test binding
/// previously dropped wheel events entirely, so wheel-scroll regressions
/// were invisible to tests.
bool dispatchMouseWheelAtPosition(
    Element element, MouseEvent event, Offset mousePos, Offset currentOffset) {
  // TODO: This is a hack to handle RenderTheater specially for Navigator
  // Should be properly integrated into the render object hierarchy
  if (element.renderObject is RenderTheater) {
    final multiChildRenderObject = element as MultiChildRenderObjectElement;
    if (multiChildRenderObject.children.isNotEmpty) {
      final child = multiChildRenderObject.children.last;
      return dispatchMouseWheelAtPosition(
          child, event, mousePos, currentOffset);
    }
  }

  // Calculate this element's bounds if it has a render object
  Rect? elementBounds;
  RenderObject? renderObject;

  if (element is RenderObjectElement) {
    renderObject = element.renderObject;
    final size = renderObject.size;

    // Get the offset from parent data if available
    Offset localOffset = currentOffset;
    if (renderObject.parentData is BoxParentData) {
      final boxParentData = renderObject.parentData as BoxParentData;
      localOffset = currentOffset + boxParentData.offset;
    }

    elementBounds = Rect.fromLTWH(
      localOffset.dx,
      localOffset.dy,
      size.width,
      size.height,
    );
  }

  // Check if mouse is within this element's bounds
  bool isWithinBounds = elementBounds?.contains(mousePos) ?? true;

  if (!isWithinBounds) {
    return false; // Mouse is outside this element
  }

  // Try to dispatch to children first (depth-first, but only if within their bounds)
  bool handled = false;

  // Calculate offset for children
  Offset childrenOffset = currentOffset;
  if (element is RenderObjectElement && elementBounds != null) {
    // Use the element's actual position for its children
    childrenOffset = Offset(elementBounds.left, elementBounds.top);
  }

  // Visit children in reverse order to respect visual stacking
  // (last child is visually on top in Stack-like containers)
  final children = <Element>[];
  element.visitChildren((child) {
    children.add(child);
  });

  for (final child in children.reversed) {
    if (!handled) {
      handled =
          dispatchMouseWheelAtPosition(child, event, mousePos, childrenOffset);
    }
  }

  // If no child handled it and this element's render object is scrollable, handle it here
  if (!handled &&
      renderObject != null &&
      renderObject is ScrollableRenderObjectMixin) {
    final scrollableRenderObject = renderObject as ScrollableRenderObjectMixin;
    // Check if the render object implements scrolling through duck typing
    // This allows the RenderObject to handle scrolling without importing the mixin
    handled = scrollableRenderObject.handleMouseWheel(event);
  }

  return handled;
}
