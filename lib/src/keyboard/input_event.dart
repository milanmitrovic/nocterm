import '../theme/color_scheme_notice.dart';
import 'keyboard_event.dart';
import 'mouse_event.dart';

/// Base class for all input events (keyboard and mouse)
abstract class InputEvent {
  const InputEvent();
}

/// Keyboard input event
class KeyboardInputEvent extends InputEvent {
  final KeyboardEvent event;

  const KeyboardInputEvent(this.event);
}

/// Mouse input event
class MouseInputEvent extends InputEvent {
  final MouseEvent event;

  const MouseInputEvent(this.event);
}

/// Paste input event (from bracketed paste mode)
class PasteInputEvent extends InputEvent {
  final String text;

  const PasteInputEvent(this.text);
}

/// Colour-scheme change notification from the terminal.
///
/// Produced when DEC private mode 2031 is enabled and the terminal sends
/// `CSI ? 997 ; <n> n` — either unsolicited or as the reply to a
/// `CSI ? 996 n` query. It is parsed as its own event so the report can
/// never leak into the application as keystrokes.
class ColorSchemeInputEvent extends InputEvent {
  final ColorSchemeNotice notice;

  const ColorSchemeInputEvent(this.notice);
}
