import 'package:nocterm/src/utils/ansi_color_quantizer.dart';
import 'package:nocterm/src/utils/terminal_color_support.dart';

/// Linearly interpolate between two integers.
int _lerpInt(int a, int b, double t) {
  return (a + (b - a) * t).round();
}

/// Color constants which align with terminal colors.
///
/// This follows Flutter's pattern of having a separate Colors class
/// to avoid conflicts with Color instance members.
abstract class Colors {
  // Prevent instantiation
  Colors._();

  /// Completely opaque black.
  static const Color black = Color.fromRGB(24, 24, 28);

  /// Completely opaque red.
  static const Color red = Color.fromRGB(231, 97, 112);

  /// Completely opaque green.
  static const Color green = Color.fromRGB(139, 213, 152);

  /// Completely opaque yellow.
  static const Color yellow = Color.fromRGB(241, 213, 137);

  /// Completely opaque blue.
  static const Color blue = Color.fromRGB(139, 179, 244);

  /// Completely opaque magenta.
  static const Color magenta = Color.fromRGB(198, 160, 246);

  /// Completely opaque cyan.
  static const Color cyan = Color.fromRGB(139, 213, 202);

  /// Completely opaque white.
  static const Color white = Color.fromRGB(248, 248, 242);

  /// Completely opaque grey.
  static const Color grey = Color.fromRGB(146, 153, 166);

  /// Completely opaque gray (American spelling).
  static const Color gray = grey;

  // Bright/bold terminal colors

  /// Bright black (dark grey).
  static const Color brightBlack = Color.fromRGB(98, 104, 117);

  /// Bright red.
  static const Color brightRed = Color.fromRGB(255, 139, 148);

  /// Bright green.
  static const Color brightGreen = Color.fromRGB(163, 239, 178);

  /// Bright yellow.
  static const Color brightYellow = Color.fromRGB(255, 234, 170);

  /// Bright blue.
  static const Color brightBlue = Color.fromRGB(163, 203, 255);

  /// Bright magenta.
  static const Color brightMagenta = Color.fromRGB(224, 189, 255);

  /// Bright cyan.
  static const Color brightCyan = Color.fromRGB(163, 239, 228);

  /// Bright white.
  static const Color brightWhite = Color.fromRGB(255, 255, 255);
}

/// An immutable 32 bit color value in ARGB format.
///
/// This is a simplified version of Flutter's Color class for terminal use.
/// While terminals don't support true alpha blending, we can pre-blend colors
/// knowing what's behind them in the buffer.
class Color {
  /// The terminal's default color (resets to terminal default)
  static const Color defaultColor = Color._default();

  /// The alpha channel of this color in an 8 bit value, 0 to 255.
  ///
  /// A value of 0 means fully transparent, 255 means fully opaque.
  /// Colors with alpha < 255 will be blended with the background during rendering.
  final int alpha;

  /// The red component of this color, 0 to 255.
  final int red;

  /// The green component of this color, 0 to 255.
  final int green;

  /// The blue component of this color, 0 to 255.
  final int blue;

  /// Whether this is the default terminal color
  final bool isDefault;

  /// The 16-colour ANSI palette slot this color names, or null for an
  /// ordinary RGB color.
  ///
  /// When set, [toAnsi] emits the classic SGR 30–37/90–97 (foreground) and
  /// 40–47/100–107 (background) codes, so the terminal paints the cell from
  /// the *user's* palette — which is the point of naming a slot instead of a
  /// shade. [red]/[green]/[blue] then hold xterm's default palette values as
  /// an APPROXIMATION, used only where an RGB value is unavoidable (blending
  /// underneath a translucent color, luminance checks). They are not what the
  /// terminal will draw.
  final int? ansiIndex;

  /// Whether this color names a slot in the terminal's 16-colour palette.
  bool get isAnsiIndexed => ansiIndex != null;

  /// Creates a color from an integer value.
  ///
  /// The value should be in 0xRRGGBB format where:
  /// - RR is the red component (0-255)
  /// - GG is the green component (0-255)
  /// - BB is the blue component (0-255)
  ///
  /// The alpha channel defaults to 255 (fully opaque).
  const Color(int value)
      : alpha = 255,
        red = (value >> 16) & 0xFF,
        green = (value >> 8) & 0xFF,
        blue = value & 0xFF,
        isDefault = false,
        ansiIndex = null;

  /// Creates the default terminal color
  const Color._default()
      : alpha = 255,
        red = 0,
        green = 0,
        blue = 0,
        isDefault = true,
        ansiIndex = null;

  /// Creates a color naming a slot in the terminal's 16-colour palette.
  ///
  /// [index] runs 0–15: 0–7 are the standard colours (black, red, green,
  /// yellow, blue, magenta, cyan, white) and 8–15 their bright variants.
  ///
  /// This is not the same as picking the equivalent shade with
  /// [Color.fromRGB]. An indexed colour is resolved by the terminal from the
  /// user's own palette, so it follows their theme — what you want when the
  /// app should look native wherever it runs, and what you do not want when
  /// a specific shade matters.
  ///
  /// It is an ordinary, fully opaque set colour: [isDefault] is false (it
  /// paints, rather than resetting to the terminal's default, which is
  /// [Color.defaultColor] / SGR 39/49), and canvas code that preserves an
  /// existing background when the incoming style names none treats it like
  /// any other colour.
  ///
  /// [withOpacity], [withAlpha] with a translucent value and [lerp] all drop
  /// the index and fall back to the approximate RGB (see [ansiIndex]) — a
  /// translucent colour has to be pre-blended into a shade, and a shade is
  /// not a palette slot.
  ///
  /// Instances are canonical: `Color.ansi(4)` returns the same object every
  /// time. Throws [RangeError] outside 0–15.
  factory Color.ansi(int index) {
    RangeError.checkValueInInterval(index, 0, 15, 'index',
        'ANSI palette indices run 0-15 (0-7 standard, 8-15 bright)');
    return _ansiPalette[index];
  }

  /// An indexed palette colour with its xterm-default RGB approximation.
  const Color._ansi(this.ansiIndex, this.red, this.green, this.blue)
      : alpha = 255,
        isDefault = false;

  /// The 16 palette slots, carrying xterm's default RGB values.
  ///
  /// Only an approximation — the terminal renders these from the user's
  /// palette — but a defined one, so blending and luminance stay sane.
  static const List<Color> _ansiPalette = [
    Color._ansi(0, 0, 0, 0), //          black
    Color._ansi(1, 205, 0, 0), //        red
    Color._ansi(2, 0, 205, 0), //        green
    Color._ansi(3, 205, 205, 0), //      yellow
    Color._ansi(4, 0, 0, 238), //        blue
    Color._ansi(5, 205, 0, 205), //      magenta
    Color._ansi(6, 0, 205, 205), //      cyan
    Color._ansi(7, 229, 229, 229), //    white
    Color._ansi(8, 127, 127, 127), //    bright black
    Color._ansi(9, 255, 0, 0), //        bright red
    Color._ansi(10, 0, 255, 0), //       bright green
    Color._ansi(11, 255, 255, 0), //     bright yellow
    Color._ansi(12, 92, 92, 255), //     bright blue
    Color._ansi(13, 255, 0, 255), //     bright magenta
    Color._ansi(14, 0, 255, 255), //     bright cyan
    Color._ansi(15, 255, 255, 255), //   bright white
  ];

  /// Creates a color from red, green, and blue components.
  ///
  /// The values must be between 0 and 255 inclusive.
  /// The alpha channel defaults to 255 (fully opaque).
  const Color.fromRGB(this.red, this.green, this.blue)
      : alpha = 255,
        assert(red >= 0 && red <= 255),
        assert(green >= 0 && green <= 255),
        assert(blue >= 0 && blue <= 255),
        isDefault = false,
        ansiIndex = null;

  /// Creates a color from alpha, red, green, and blue components.
  ///
  /// All values must be between 0 and 255 inclusive.
  /// - [alpha]: 0 (fully transparent) to 255 (fully opaque)
  /// - [red]: Red component
  /// - [green]: Green component
  /// - [blue]: Blue component
  const Color.fromARGB(this.alpha, this.red, this.green, this.blue)
      : assert(alpha >= 0 && alpha <= 255),
        assert(red >= 0 && red <= 255),
        assert(green >= 0 && green <= 255),
        assert(blue >= 0 && blue <= 255),
        isDefault = false,
        ansiIndex = null;

  /// Converts this color to an ANSI escape code.
  ///
  /// If [background] is true, returns a background color code.
  /// Otherwise returns a foreground color code.
  String toAnsi({bool background = false}) {
    if (isDefault) {
      // Reset to default colors
      if (background) {
        return '\x1b[49m'; // Reset background to default
      }
      return '\x1b[39m'; // Reset foreground to default
    }
    final slot = ansiIndex;
    if (slot != null) {
      // A palette slot, not a shade: emit the classic SGR codes so the
      // terminal resolves it against the user's own palette. Never
      // truecolor, and never quantized — both would pin down the shade,
      // which is exactly what naming a slot avoids.
      //   0-7  -> 30-37 (fg) / 40-47 (bg)
      //   8-15 -> 90-97 (fg) / 100-107 (bg)
      final base =
          slot < 8 ? (background ? 40 : 30) : (background ? 100 : 90);
      return '\x1b[${base + (slot & 7)}m';
    }
    if (supportsTruecolor()) {
      if (background) {
        return '\x1b[48;2;$red;$green;${blue}m';
      }
      return '\x1b[38;2;$red;$green;${blue}m';
    }

    final index = quantizeRgbToAnsi256(red, green, blue);
    if (background) {
      return '\x1b[48;5;${index}m';
    }
    return '\x1b[38;5;${index}m';
  }

  /// The alpha channel, as a double from 0.0 (fully transparent) to 1.0 (fully opaque).
  double get a => alpha / 255.0;

  /// The red channel, as a double from 0.0 to 1.0.
  double get r => red / 255.0;

  /// The green channel, as a double from 0.0 to 1.0.
  double get g => green / 255.0;

  /// The blue channel, as a double from 0.0 to 1.0.
  double get b => blue / 255.0;

  /// Returns a new color with the given opacity.
  ///
  /// The [opacity] must be between 0.0 (fully transparent) and 1.0 (fully opaque).
  Color withOpacity(double opacity) {
    assert(opacity >= 0.0 && opacity <= 1.0);
    return Color.fromARGB((255.0 * opacity).round(), red, green, blue);
  }

  /// Returns a new color with the given alpha value.
  ///
  /// The [alpha] must be between 0 and 255.
  ///
  /// An indexed colour asked for full opacity — which it already has — is
  /// returned unchanged rather than being flattened into its approximate
  /// RGB. Any other alpha drops the index: a translucent colour has to be
  /// pre-blended into a shade, and a shade is not a palette slot.
  Color withAlpha(int alpha) {
    assert(alpha >= 0 && alpha <= 255);
    if (ansiIndex != null && alpha == this.alpha) {
      return this;
    }
    return Color.fromARGB(alpha, red, green, blue);
  }

  /// Blends the [foreground] color over the [background] color using alpha compositing.
  ///
  /// Uses the "source over" blending mode. If the foreground is fully opaque,
  /// returns the foreground color. If fully transparent, returns the background.
  ///
  /// This implements Flutter's alpha blending formula:
  /// ```
  /// result = foreground * alpha + background * (1 - alpha)
  /// ```
  static Color alphaBlend(Color foreground, Color background) {
    final double alpha = foreground.a;

    // Optimization: fully opaque foreground
    if (alpha == 1.0) {
      return foreground;
    }

    // Optimization: fully transparent foreground
    if (alpha == 0.0) {
      return background;
    }

    final double invAlpha = 1.0 - alpha;

    // Blend formula: result = fg * alpha + bg * (1 - alpha)
    // We normalize to 0-1 range for calculation, then convert back to 0-255
    return Color.fromRGB(
      (foreground.r * 255 * alpha + background.r * 255 * invAlpha)
          .round()
          .clamp(0, 255),
      (foreground.g * 255 * alpha + background.g * 255 * invAlpha)
          .round()
          .clamp(0, 255),
      (foreground.b * 255 * alpha + background.b * 255 * invAlpha)
          .round()
          .clamp(0, 255),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is Color &&
        other.isDefault == isDefault &&
        other.ansiIndex == ansiIndex &&
        other.alpha == alpha &&
        other.red == red &&
        other.green == green &&
        other.blue == blue;
  }

  /// Linearly interpolate between two colors.
  ///
  /// The [t] argument represents position on the timeline, with 0.0 meaning
  /// that the interpolation has not started, returning [a] (or something
  /// equivalent to [a]), 1.0 meaning that the interpolation has finished,
  /// returning [b] (or something equivalent to [b]), and values in between
  /// meaning that the interpolation is at the relevant point on the timeline
  /// between [a] and [b].
  ///
  /// The interpolation can be extrapolated beyond 0.0 and 1.0, so negative
  /// values and values greater than 1.0 are valid (and can easily be generated
  /// by curves such as `Curves.elasticInOut`). Each channel will be clamped to
  /// the range 0 to 255.
  ///
  /// If either color is null, this function linearly interpolates from a
  /// transparent instance of the other color.
  static Color? lerp(Color? a, Color? b, double t) {
    if (identical(a, b)) {
      return a;
    }
    if (a == null) {
      return b!.withAlpha((b.alpha * t).round().clamp(0, 255));
    }
    if (b == null) {
      return a.withAlpha((a.alpha * (1.0 - t)).round().clamp(0, 255));
    }
    return Color.fromARGB(
      _lerpInt(a.alpha, b.alpha, t).clamp(0, 255),
      _lerpInt(a.red, b.red, t).clamp(0, 255),
      _lerpInt(a.green, b.green, t).clamp(0, 255),
      _lerpInt(a.blue, b.blue, t).clamp(0, 255),
    );
  }

  @override
  int get hashCode => Object.hash(alpha, red, green, blue, isDefault, ansiIndex);

  @override
  String toString() => isDefault
      ? 'Color.defaultColor'
      : ansiIndex != null
          ? 'Color.ansi($ansiIndex)'
          : alpha == 255
              ? 'Color(r: $red, g: $green, b: $blue)'
              : 'Color(a: $alpha, r: $red, g: $green, b: $blue)';
}

/// A color represented using [alpha], [hue], [saturation], and [value].
///
/// Useful for color computations like rotating through the color spectrum.
class HSVColor {
  const HSVColor.fromAHSV(this.alpha, this.hue, this.saturation, this.value)
      : assert(alpha >= 0.0 && alpha <= 1.0),
        assert(hue >= 0.0 && hue <= 360.0),
        assert(saturation >= 0.0 && saturation <= 1.0),
        assert(value >= 0.0 && value <= 1.0);

  final double alpha;
  final double hue;
  final double saturation;
  final double value;

  HSVColor withHue(double hue) {
    return HSVColor.fromAHSV(alpha, hue % 360.0, saturation, value);
  }

  Color toColor() {
    final double chroma = saturation * value;
    final double secondary =
        chroma * (1.0 - (((hue / 60.0) % 2.0) - 1.0).abs());
    final double match = value - chroma;

    double red, green, blue;
    if (hue < 60.0) {
      red = chroma;
      green = secondary;
      blue = 0.0;
    } else if (hue < 120.0) {
      red = secondary;
      green = chroma;
      blue = 0.0;
    } else if (hue < 180.0) {
      red = 0.0;
      green = chroma;
      blue = secondary;
    } else if (hue < 240.0) {
      red = 0.0;
      green = secondary;
      blue = chroma;
    } else if (hue < 300.0) {
      red = secondary;
      green = 0.0;
      blue = chroma;
    } else {
      red = chroma;
      green = 0.0;
      blue = secondary;
    }

    return Color.fromARGB(
      (alpha * 255).round(),
      ((red + match) * 255).round(),
      ((green + match) * 255).round(),
      ((blue + match) * 255).round(),
    );
  }
}

/// The thickness of the glyphs used to draw the text.
///
/// Simplified version of Flutter's FontWeight for terminal use.
enum FontWeight {
  /// Normal font weight (W400).
  normal,

  /// Bold font weight (W700).
  bold,

  /// Dim/light font weight (W300).
  dim,
}

/// Whether to use italics.
enum FontStyle {
  /// Use upright glyphs.
  normal,

  /// Use italic glyphs.
  italic,
}

/// A linear decoration to draw near the text.
class TextDecoration {
  const TextDecoration._(this._mask);

  final int _mask;

  /// No decoration.
  static const TextDecoration none = TextDecoration._(0x0);

  /// Draw a line underneath the text.
  static const TextDecoration underline = TextDecoration._(0x1);

  /// Draw a line through the text (strikethrough).
  static const TextDecoration lineThrough = TextDecoration._(0x2);

  /// Draw a line above the text (overline).
  static const TextDecoration overline = TextDecoration._(0x4);

  /// Combines multiple decorations.
  factory TextDecoration.combine(List<TextDecoration> decorations) {
    int mask = 0;
    for (final decoration in decorations) {
      mask |= decoration._mask;
    }
    return TextDecoration._(mask);
  }

  /// Whether this decoration contains underline.
  bool get contains => _mask != 0;

  /// Whether this decoration contains underline.
  bool get hasUnderline => (_mask & underline._mask) != 0;

  /// Whether this decoration contains line through.
  bool get hasLineThrough => (_mask & lineThrough._mask) != 0;

  /// Whether this decoration contains overline.
  bool get hasOverline => (_mask & overline._mask) != 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is TextDecoration && other._mask == _mask;
  }

  @override
  int get hashCode => _mask.hashCode;
}

/// An immutable style describing how to format and paint text.
///
/// This is a simplified version of Flutter's TextStyle for terminal use.
/// It follows Flutter's naming conventions to make it familiar for Flutter developers.
class TextStyle {
  /// The color to use when painting the text.
  ///
  /// In Flutter terminology, this is the foreground color.
  final Color? color;

  /// The color to use as the background for the text.
  final Color? backgroundColor;

  /// The typeface thickness to use when painting the text.
  final FontWeight? fontWeight;

  /// The typeface variant to use when drawing the letters.
  final FontStyle? fontStyle;

  /// The decorations to paint near the text (e.g., underline).
  final TextDecoration? decoration;

  /// Whether to reverse the foreground and background colors.
  ///
  /// This is a terminal-specific feature not present in Flutter's TextStyle.
  final bool reverse;

  /// OSC 8 hyperlink target for this text.
  ///
  /// When non-null, the rendered cells are wrapped in OSC 8 escape
  /// sequences so the terminal makes them clickable (usually Cmd/Ctrl+
  /// click). This is a terminal-specific feature not present in Flutter's
  /// TextStyle. Emission happens in the frame flush path, not in [toAnsi].
  final String? hyperlink;

  /// Creates a text style.
  const TextStyle({
    this.color,
    this.backgroundColor,
    this.fontWeight,
    this.fontStyle,
    this.decoration,
    this.reverse = false,
    this.hyperlink,
  });

  /// Creates a copy of this text style but with the given fields replaced.
  TextStyle copyWith({
    Color? color,
    Color? backgroundColor,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    TextDecoration? decoration,
    bool? reverse,
    String? hyperlink,
  }) {
    return TextStyle(
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      decoration: decoration ?? this.decoration,
      reverse: reverse ?? this.reverse,
      hyperlink: hyperlink ?? this.hyperlink,
    );
  }

  /// Merge this style with another, with the other style taking precedence.
  TextStyle merge(TextStyle? other) {
    if (other == null) return this;
    return copyWith(
      color: other.color,
      backgroundColor: other.backgroundColor,
      fontWeight: other.fontWeight,
      fontStyle: other.fontStyle,
      decoration: other.decoration,
      reverse: other.reverse,
      hyperlink: other.hyperlink,
    );
  }

  /// Converts this text style to ANSI escape codes.
  String toAnsi() {
    final codes = <String>[];

    if (color != null) {
      codes.add(color!.toAnsi());
    }
    if (backgroundColor != null) {
      codes.add(backgroundColor!.toAnsi(background: true));
    }

    // Handle font weight
    if (fontWeight == FontWeight.bold) {
      codes.add('\x1b[1m');
    } else if (fontWeight == FontWeight.dim) {
      codes.add('\x1b[2m');
    }

    // Handle font style
    if (fontStyle == FontStyle.italic) {
      codes.add('\x1b[3m');
    }

    // Handle decorations
    if (decoration != null) {
      if (decoration!.hasUnderline) {
        codes.add('\x1b[4m');
      }
      if (decoration!.hasLineThrough) {
        codes.add('\x1b[9m');
      }
      if (decoration!.hasOverline) {
        codes.add('\x1b[53m');
      }
    }

    if (reverse) {
      codes.add('\x1b[7m');
    }

    return codes.join();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is TextStyle &&
        other.color == color &&
        other.backgroundColor == backgroundColor &&
        other.fontWeight == fontWeight &&
        other.fontStyle == fontStyle &&
        other.decoration == decoration &&
        other.reverse == reverse &&
        other.hyperlink == hyperlink;
  }

  @override
  int get hashCode => Object.hash(
        color,
        backgroundColor,
        fontWeight,
        fontStyle,
        decoration,
        reverse,
        hyperlink,
      );

  @override
  String toString() => 'TextStyle('
      '${color != null ? 'color: $color, ' : ''}'
      '${backgroundColor != null ? 'backgroundColor: $backgroundColor, ' : ''}'
      '${fontWeight != null ? 'fontWeight: $fontWeight, ' : ''}'
      '${fontStyle != null ? 'fontStyle: $fontStyle, ' : ''}'
      '${decoration != null ? 'decoration: $decoration, ' : ''}'
      '${reverse ? 'reverse: true, ' : ''}'
      '${hyperlink != null ? 'hyperlink: $hyperlink' : ''}'
      ')';

  /// ANSI reset code to clear all formatting.
  static const String reset = '\x1b[0m';
}
