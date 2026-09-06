import 'brightness.dart';

/// A notification that the terminal's colour scheme changed.
///
/// Emitted when DEC private mode 2031 ("colour scheme updates") is enabled
/// and the terminal reports `CSI ? 997 ; <n> n`, either unsolicited (the
/// user switched their terminal or OS appearance) or as the reply to a
/// `CSI ? 996 n` query.
///
/// ## Treat the payload as "colours changed, re-read"
///
/// The `<n>` payload is **unreliable across terminals**. Support for mode
/// 2031 is recent and uneven: some emulators report the mode number back
/// instead of the scheme, some report only on an OS appearance change and
/// not on a per-profile theme switch, some send a notification whose
/// payload lags the palette they have already repainted with, and some
/// never answer the `CSI ? 996 n` query at all.
///
/// So an application should use [brightness] as a hint only, and treat the
/// arrival of a notice as the real signal: *something about the palette
/// changed — re-read it*. The authoritative read is still an OSC 10/11
/// query (`Terminal.getBackgroundColor`, or `detectTerminalBrightness`),
/// which reports the colour actually in force.
///
/// [reportedValue] is kept verbatim so an app can log what a given terminal
/// really sent without this class having to know every emulator's quirks.
class ColorSchemeNotice {
  /// Creates a notice with an already-decoded [brightness].
  const ColorSchemeNotice({
    required this.reportedValue,
    this.brightness,
  });

  /// Decodes a `CSI ? 997 ; <value> n` payload.
  ///
  /// `1` means dark, `2` means light; every other value decodes to a notice
  /// with a null [brightness] — the change still happened, we just cannot
  /// say which way it went.
  factory ColorSchemeNotice.fromReportedValue(int value) {
    return ColorSchemeNotice(
      reportedValue: value,
      brightness: switch (value) {
        1 => Brightness.dark,
        2 => Brightness.light,
        _ => null,
      },
    );
  }

  /// The raw `<n>` parameter the terminal sent.
  final int reportedValue;

  /// The scheme the terminal claims to be using now, or null when the
  /// payload was not one this package understands.
  ///
  /// A hint, not a fact — see the class docs.
  final Brightness? brightness;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorSchemeNotice &&
          other.runtimeType == runtimeType &&
          other.reportedValue == reportedValue &&
          other.brightness == brightness;

  @override
  int get hashCode => Object.hash(reportedValue, brightness);

  @override
  String toString() =>
      'ColorSchemeNotice(reportedValue: $reportedValue, brightness: $brightness)';
}
