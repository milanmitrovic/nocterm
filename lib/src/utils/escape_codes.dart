class EscapeCodes {
  const EscapeCodes._();

  static const disable = _Disable._();
  static const enable = _Enable._();

  static const resetDeviceAttributes = '\x1B[c';
  static const hideCursor = '\x1b[?25l';
  static const showCursor = '\x1b[?25h';
  static const clearScreen = '\x1b[2J';
  static const clearLine = '\x1b[2K';
  static const moveCursorHome = '\x1b[H';
  static const alternateBuffer = '\x1b[?1049h';
  static const mainBuffer = '\x1b[?1049l';

  /// DSR query for the terminal's current colour scheme.
  ///
  /// The reply comes back as `CSI ? 997 ; <n> n`, the same shape as an
  /// unsolicited mode-2031 notification. Send it once after enabling
  /// `EscapeCodes.enable.colorSchemeUpdates` so an app gets an initial answer
  /// instead of waiting for the user to change themes.
  static const queryColorScheme = '\x1b[?996n';
}

class _Disable {
  const _Disable._();

  String get motionTracking => '\x1B[?1003l';
  String get sgrMouseMode => '\x1B[?1006l';
  String get buttonEventTracking => '\x1B[?1002l';
  String get basicMouseTracking => '\x1B[?1000l';
  String get bracketedPasteMode => '\x1B[?2004l';

  /// Pop kitty keyboard mode from the stack.
  String get kittyKeyboard => '\x1B[<u';

  /// Reset xterm modifyOtherKeys mode to disabled.
  String get modifyOtherKeys => '\x1B[>4;0m';

  /// Stop colour-scheme change notifications (DEC private mode 2031).
  ///
  /// Deliberately absent from [values]: that list is written
  /// unconditionally at teardown, and mode 2031 is opt-in, so it is
  /// disabled only by whoever enabled it.
  String get colorSchemeUpdates => '\x1B[?2031l';

  List<String> get values => [
        motionTracking,
        sgrMouseMode,
        buttonEventTracking,
        basicMouseTracking,
        bracketedPasteMode,
        kittyKeyboard,
        modifyOtherKeys,
      ];
}

class _Enable {
  const _Enable._();

  String get motionTracking => '\x1B[?1003h';
  String get sgrMouseMode => '\x1B[?1006h';
  String get buttonEventTracking => '\x1B[?1002h';
  String get basicMouseTracking => '\x1B[?1000h';
  String get bracketedPasteMode => '\x1B[?2004h';

  /// Push kitty keyboard mode with flags:
  /// - Bit 0 (1): Disambiguate escape codes
  /// This is sufficient for detecting Shift+Enter, Ctrl+Enter, etc.
  String get kittyKeyboard => '\x1B[>1u';

  /// Enable xterm modifyOtherKeys mode (level 1).
  String get modifyOtherKeys => '\x1B[>4;1m';

  /// Ask the terminal to report colour-scheme changes (DEC private mode
  /// 2031). While enabled the terminal sends `CSI ? 997 ; <n> n` whenever
  /// its palette flips between dark and light.
  ///
  /// Deliberately absent from [values]: this is opt-in, and [values] is
  /// applied to every app at startup.
  String get colorSchemeUpdates => '\x1B[?2031h';

  List<String> get values => [
        motionTracking,
        sgrMouseMode,
        buttonEventTracking,
        basicMouseTracking,
        bracketedPasteMode,
        kittyKeyboard,
        modifyOtherKeys,
      ];
}
