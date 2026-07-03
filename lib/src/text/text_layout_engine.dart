import 'package:characters/characters.dart';
import '../utils/unicode_width.dart';

/// How overflowing text should be handled
enum TextOverflow {
  /// Clip the overflowing text to fix its container
  clip,

  /// Use an ellipsis to indicate that the text has overflowed
  ellipsis,

  /// Render overflowing text outside of its container
  visible,
}

/// How the text should be aligned horizontally
enum TextAlign {
  /// Align the text on the left edge of the container
  left,

  /// Align the text on the right edge of the container
  right,

  /// Align the text in the center of the container
  center,

  /// Stretch lines of text to align both edges to the container
  justify,
}

/// Configuration for text layout
class TextLayoutConfig {
  final bool softWrap;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final int? maxLines;
  final int maxWidth;

  const TextLayoutConfig({
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.textAlign = TextAlign.left,
    this.maxLines,
    required this.maxWidth,
  });
}

/// Result of text layout calculation
class TextLayoutResult {
  final List<String> lines;

  /// For each entry in [lines], the offset (in UTF-16 code units) of that
  /// line's first character in the source text.
  ///
  /// This is the authoritative offset mapping: characters that exist in the
  /// source but in no layout line — `\n` separators and spaces dropped at a
  /// wrap boundary — are accounted for here. Consumers that map text offsets
  /// to visual positions (cursor painting, mouse hit testing, selection)
  /// must use these offsets instead of re-deriving them from line lengths,
  /// which is ambiguous once characters can be dropped.
  final List<int> lineStartOffsets;

  final int actualWidth;
  final int actualHeight;
  final bool didOverflowWidth;
  final bool didOverflowHeight;

  const TextLayoutResult({
    required this.lines,
    required this.lineStartOffsets,
    required this.actualWidth,
    required this.actualHeight,
    required this.didOverflowWidth,
    required this.didOverflowHeight,
  });
}

/// A wrapped line paired with the source offset of its first character
/// within the paragraph it was wrapped from.
class _WrappedLine {
  final String text;
  final int start;

  const _WrappedLine(this.text, this.start);
}

/// Engine for laying out text with word wrapping and overflow handling
class TextLayoutEngine {
  static const String _ellipsis = '...';

  /// Perform text layout with the given configuration
  static TextLayoutResult layout(String text, TextLayoutConfig config) {
    if (!config.softWrap || config.maxWidth == double.maxFinite.toInt()) {
      return _layoutNoWrap(text, config);
    }

    return _layoutWithWrap(text, config);
  }

  /// Layout text without wrapping (only handle explicit newlines)
  static TextLayoutResult _layoutNoWrap(String text, TextLayoutConfig config) {
    final lines = text.split('\n');
    final lineOffsets = <int>[];
    int offset = 0;
    for (final line in lines) {
      lineOffsets.add(offset);
      offset += line.length + 1; // +1 for the '\n' separator
    }
    final maxLineWidth = lines.fold(0, (max, line) {
      final width = UnicodeWidth.stringWidth(line);
      return width > max ? width : max;
    });

    // Apply maxLines constraint
    List<String> finalLines = lines;
    List<int> finalOffsets = lineOffsets;
    bool didOverflowHeight = false;

    if (config.maxLines != null && lines.length > config.maxLines!) {
      didOverflowHeight = true;
      finalLines = lines.take(config.maxLines!).toList();
      finalOffsets = lineOffsets.take(config.maxLines!).toList();

      if (config.overflow == TextOverflow.ellipsis && finalLines.isNotEmpty) {
        finalLines[finalLines.length - 1] =
            _addEllipsisToLine(finalLines.last, config.maxWidth);
      }
    }

    return TextLayoutResult(
      lines: finalLines,
      lineStartOffsets: finalOffsets,
      actualWidth: maxLineWidth,
      actualHeight: finalLines.length,
      didOverflowWidth: maxLineWidth > config.maxWidth,
      didOverflowHeight: didOverflowHeight,
    );
  }

  /// Layout text with word wrapping
  static TextLayoutResult _layoutWithWrap(
      String text, TextLayoutConfig config) {
    final List<String> wrappedLines = [];
    final List<int> lineOffsets = [];
    final paragraphs = text.split('\n');

    int paragraphStart = 0;
    for (final paragraph in paragraphs) {
      if (paragraph.isEmpty) {
        wrappedLines.add('');
        lineOffsets.add(paragraphStart);
      } else {
        for (final wrapped in _wrapParagraph(paragraph, config.maxWidth)) {
          wrappedLines.add(wrapped.text);
          lineOffsets.add(paragraphStart + wrapped.start);
        }
      }
      paragraphStart += paragraph.length + 1; // +1 for the '\n' separator
    }

    // Apply maxLines constraint
    List<String> finalLines = wrappedLines;
    List<int> finalOffsets = lineOffsets;
    bool didOverflowHeight = false;

    if (config.maxLines != null && wrappedLines.length > config.maxLines!) {
      didOverflowHeight = true;
      finalLines = wrappedLines.take(config.maxLines!).toList();
      finalOffsets = lineOffsets.take(config.maxLines!).toList();

      if (config.overflow == TextOverflow.ellipsis && finalLines.isNotEmpty) {
        finalLines[finalLines.length - 1] =
            _addEllipsisToLine(finalLines.last, config.maxWidth);
      }
    }

    // Calculate actual width
    final actualWidth = finalLines.fold(0, (max, line) {
      final width = UnicodeWidth.stringWidth(line);
      return width > max ? width : max;
    });

    return TextLayoutResult(
      lines: finalLines,
      lineStartOffsets: finalOffsets,
      actualWidth: actualWidth,
      actualHeight: finalLines.length,
      didOverflowWidth: actualWidth > config.maxWidth,
      didOverflowHeight: didOverflowHeight,
    );
  }

  /// Wrap a single paragraph into multiple lines.
  ///
  /// Each returned line carries the offset of its first character within
  /// [paragraph], so characters dropped at wrap boundaries (see the space
  /// handling below) stay accounted for in the offset mapping.
  static List<_WrappedLine> _wrapParagraph(String paragraph, int maxWidth) {
    final List<_WrappedLine> lines = [];
    final words = _splitIntoWords(paragraph);

    String currentLine = '';
    int currentLineWidth = 0;
    int currentLineStart = 0;
    int tokenStart = 0;

    for (final word in words) {
      final wordWidth = UnicodeWidth.stringWidth(word);

      if (currentLineWidth == 0) {
        // First word on line
        if (wordWidth > maxWidth) {
          // Word is too long - need to break it
          final brokenWords = _breakLongWord(word, maxWidth);
          int partStart = tokenStart;
          for (int i = 0; i < brokenWords.length - 1; i++) {
            lines.add(_WrappedLine(brokenWords[i], partStart));
            partStart += brokenWords[i].length;
          }
          currentLine = brokenWords.last;
          currentLineStart = partStart;
          currentLineWidth = UnicodeWidth.stringWidth(brokenWords.last);
        } else {
          currentLine = word;
          currentLineStart = tokenStart;
          currentLineWidth = wordWidth;
        }
      } else if (currentLineWidth + wordWidth <= maxWidth) {
        // Word fits on current line
        currentLine += word;
        currentLineWidth += wordWidth;
      } else {
        // Word doesn't fit - start new line
        lines.add(_WrappedLine(currentLine, currentLineStart));

        if (word == ' ') {
          // A space token that straddles the wrap boundary would otherwise
          // seed the next line with a leading space, indenting it. Drop it.
          // The dropped character still occupies a source offset — the next
          // line starts after it.
          currentLine = '';
          currentLineWidth = 0;
          currentLineStart = tokenStart + word.length;
        } else if (wordWidth > maxWidth) {
          // Word is too long for a line by itself
          final brokenWords = _breakLongWord(word, maxWidth);
          int partStart = tokenStart;
          for (int i = 0; i < brokenWords.length - 1; i++) {
            lines.add(_WrappedLine(brokenWords[i], partStart));
            partStart += brokenWords[i].length;
          }
          currentLine = brokenWords.last;
          currentLineStart = partStart;
          currentLineWidth = UnicodeWidth.stringWidth(brokenWords.last);
        } else {
          currentLine = word;
          currentLineStart = tokenStart;
          currentLineWidth = wordWidth;
        }
      }

      tokenStart += word.length;
    }

    // Add remaining line
    if (currentLine.isNotEmpty) {
      lines.add(_WrappedLine(currentLine, currentLineStart));
    }

    return lines;
  }

  /// Split text into words, preserving spaces and considering break opportunities
  static List<String> _splitIntoWords(String text) {
    final List<String> words = [];
    final StringBuffer currentWord = StringBuffer();

    String? prevGrapheme;
    for (final grapheme in text.characters) {
      // Check for break opportunities
      if (_canBreakAfter(prevGrapheme, grapheme)) {
        if (currentWord.isNotEmpty) {
          words.add(currentWord.toString());
          currentWord.clear();
        }
        if (grapheme == ' ') {
          words.add(' ');
        } else {
          currentWord.write(grapheme);
        }
      } else {
        currentWord.write(grapheme);
      }
      prevGrapheme = grapheme;
    }

    if (currentWord.isNotEmpty) {
      words.add(currentWord.toString());
    }

    return words;
  }

  /// Check if we can break between two graphemes
  static bool _canBreakAfter(String? prev, String next) {
    if (prev == null) return false;

    // Always break on spaces
    if (next == ' ' || prev == ' ') return true;

    // Break after hyphens
    if (prev == '-') return true;

    // Break after slashes (for URLs)
    if (prev == '/') return true;

    // Zero-width space is an explicit break opportunity
    if (prev == '\u200B' || next == '\u200B') return true;

    // CJK characters can break between each other
    if (_isCJK(prev) && _isCJK(next)) return true;

    return false;
  }

  /// Check if a grapheme is a CJK character
  static bool _isCJK(String grapheme) {
    if (grapheme.isEmpty) return false;
    final rune = grapheme.runes.first;

    // CJK Unified Ideographs
    if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x20000 && rune <= 0x2A6DF)) {
      return true;
    }

    // Hiragana, Katakana
    if ((rune >= 0x3040 && rune <= 0x309F) ||
        (rune >= 0x30A0 && rune <= 0x30FF)) {
      return true;
    }

    // Hangul
    if (rune >= 0xAC00 && rune <= 0xD7AF) {
      return true;
    }

    return false;
  }

  /// Break a long word that doesn't fit on a single line
  static List<String> _breakLongWord(String word, int maxWidth) {
    final List<String> parts = [];
    String currentPart = '';
    int currentWidth = 0;

    // Use grapheme clusters to avoid breaking multi-codepoint characters
    for (final grapheme in word.characters) {
      final graphemeW = UnicodeWidth.graphemeWidth(grapheme);

      if (currentWidth + graphemeW > maxWidth && currentPart.isNotEmpty) {
        parts.add(currentPart);
        currentPart = grapheme;
        currentWidth = graphemeW;
      } else {
        currentPart += grapheme;
        currentWidth += graphemeW;
      }
    }

    if (currentPart.isNotEmpty) {
      parts.add(currentPart);
    }

    return parts.isEmpty ? [''] : parts;
  }

  /// Add ellipsis to a line, truncating as needed
  static String _addEllipsisToLine(String line, int maxWidth) {
    final ellipsisWidth = UnicodeWidth.stringWidth(_ellipsis);
    final lineWidth = UnicodeWidth.stringWidth(line);

    if (lineWidth <= maxWidth - ellipsisWidth) {
      return line + _ellipsis;
    }

    // Truncate line to make room for ellipsis using grapheme clusters
    String truncated = '';
    int width = 0;

    for (final grapheme in line.characters) {
      final graphemeW = UnicodeWidth.graphemeWidth(grapheme);

      if (width + graphemeW + ellipsisWidth > maxWidth) {
        break;
      }

      truncated += grapheme;
      width += graphemeW;
    }

    return truncated + _ellipsis;
  }

  /// Calculate horizontal offset for a line based on alignment
  static double calculateAlignmentOffset(
    String line,
    int maxWidth,
    TextAlign textAlign,
  ) {
    final lineWidth = UnicodeWidth.stringWidth(line);

    switch (textAlign) {
      case TextAlign.left:
        return 0;
      case TextAlign.right:
        return (maxWidth - lineWidth).toDouble();
      case TextAlign.center:
        return (maxWidth - lineWidth) / 2;
      case TextAlign.justify:
        // Justify is handled separately with word spacing
        return 0;
    }
  }

  /// Apply justification to a line by adding spaces between words
  static String justifyLine(String line, int maxWidth,
      {bool isLastLine = false}) {
    if (isLastLine) {
      return line; // Don't justify last line of paragraph
    }

    final words = _splitIntoWords(line).where((w) => w != ' ').toList();
    if (words.length <= 1) {
      return line; // Can't justify single word
    }

    final totalWordWidth =
        words.fold(0, (sum, word) => sum + UnicodeWidth.stringWidth(word));
    final totalSpaces = maxWidth - totalWordWidth;
    final gaps = words.length - 1;

    if (gaps == 0) return line;

    final spacesPerGap = totalSpaces ~/ gaps;
    final extraSpaces = totalSpaces % gaps;

    final buffer = StringBuffer();
    for (int i = 0; i < words.length; i++) {
      buffer.write(words[i]);
      if (i < words.length - 1) {
        final spaces = spacesPerGap + (i < extraSpaces ? 1 : 0);
        buffer.write(' ' * spaces);
      }
    }

    return buffer.toString();
  }
}
