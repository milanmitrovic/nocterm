/// Painting and measuring, for components that paint or measure
/// themselves the way nocterm's own components do.
///
/// These live outside `package:nocterm/nocterm.dart` so that importing
/// them is a choice: the canvas a render object's `paint` receives, the
/// width text is measured by, the wrapper text is wrapped with, and the
/// one type the mouse-wheel dispatch recognises as scrollable.
library;

export 'src/framework/terminal_canvas.dart' show TerminalCanvas;
export 'src/rendering/scrollable_render_object.dart'
    show ScrollableRenderObjectMixin;
export 'src/text/text_layout_engine.dart'
    show TextLayoutConfig, TextLayoutEngine, TextLayoutResult;
export 'src/utils/unicode_width.dart' show UnicodeWidth;
