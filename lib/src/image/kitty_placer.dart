import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../rectangle.dart';
import 'kitty_encoder.dart';

/// The kitty image id for [bytes]: their 32-bit FNV-1a hash, never 0
/// (kitty reserves `i=0`).
///
/// Derived from content so one picture keeps one id across frames, widgets
/// and re-encodes: the terminal stores it once per session.
int kittyImageId(List<int> bytes) => _nonZero(_fnv1a(_fnvOffset, bytes));

const _fnvOffset = 0x811c9dc5;

int _fnv1a(int hash, List<int> bytes) {
  for (final byte in bytes) {
    hash ^= byte & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

int _nonZero(int hash) => hash == 0 ? 1 : hash;

/// Pixels to show through the kitty graphics protocol, named by [id].
class KittyImage {
  KittyImage._({
    required this.id,
    required this.key,
    required this.rgba,
    required this.width,
    required this.height,
  });

  /// An image of [width]x[height] RGBA [rgba] pixels.
  ///
  /// With a [contentKey] (a blob hash, say) the id comes from the key, and
  /// the pixels are not hashed; otherwise from the pixels and their shape.
  factory KittyImage.fromRgba(
    Uint8List rgba,
    int width,
    int height, {
    String? contentKey,
  }) {
    final int id;
    if (contentKey != null) {
      id = kittyImageId(utf8.encode(contentKey));
    } else {
      final shape = ByteData(8)
        ..setUint32(0, width)
        ..setUint32(4, height);
      id = _nonZero(_fnv1a(_fnv1a(_fnvOffset, shape.buffer.asUint8List()), rgba));
    }
    return KittyImage._(
      id: id,
      key: contentKey ?? id.toRadixString(16).padLeft(8, '0'),
      rgba: rgba,
      width: width,
      height: height,
    );
  }

  /// The kitty image id (`i=`).
  final int id;

  /// The content key given, or [id] in hex: what a spec snapshot records.
  final String key;

  final Uint8List rgba;
  final int width;
  final int height;

  /// The pixels as PNG (`f=100`), for the one transmission.
  Uint8List encodePng() {
    final image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      numChannels: 4,
    );
    return Uint8List.fromList(img.encodePng(image));
  }
}

/// One image shown in one slot this frame: [image] scaled into a
/// [columns]x[rows] cell box whose top-left cell is ([x], [y]), absolute.
class ImagePlacement {
  const ImagePlacement({
    required this.image,
    required this.placementId,
    required this.x,
    required this.y,
    required this.columns,
    required this.rows,
  });

  final KittyImage image;

  /// Stable per widget slot (`p=`), so moving it replaces, not duplicates.
  final int placementId;

  final int x;
  final int y;
  final int columns;
  final int rows;

  int get imageId => image.id;

  /// The cells covered, absolute.
  Rect get rect => Rect.fromLTWH(
      x.toDouble(), y.toDouble(), columns.toDouble(), rows.toDouble());

  bool _sameBox(ImagePlacement other) =>
      other.x == x &&
      other.y == y &&
      other.columns == columns &&
      other.rows == rows;

  @override
  String toString() =>
      'ImagePlacement(${image.key} i=$imageId p=$placementId '
      '@$x,$y ${columns}x$rows)';
}

/// Turns each frame's [ImagePlacement]s into kitty graphics commands,
/// sending only what changed since the last frame.
///
/// - an image id the terminal has not seen is transmitted (`a=t`) once per
///   session, in 4096-byte chunks;
/// - a placement that is new, moved or resized is placed (`a=p`) at its
///   cell — the same `i`/`p` replaces the old one;
/// - a placement gone from the frame is deleted with `d=i`, which keeps the
///   image data for when it comes back;
/// - placements ask for errors only (`q=1`): when the terminal has evicted
///   an image (kitty's storage quota), its `ENOENT` reply goes to
///   [handleReply], and the next flush sends and places it again.
///
/// Direct placement only: never unicode placeholders (`U=1`), never sixel.
class KittyPlacer {
  static int _nextPlacementId = 1;

  /// A new placement id, for one widget slot to keep for its lifetime.
  static int nextPlacementId() {
    final id = _nextPlacementId;
    _nextPlacementId = id >= 0xffffffff ? 1 : id + 1;
    return id;
  }

  /// How many times one image is re-sent after the terminal reported it
  /// gone, per session — a terminal that drops it straight away again
  /// (an image over its quota) is not fed it every frame.
  static const maxResends = 3;

  final Set<int> _transmitted = {};
  final Map<(int, int), ImagePlacement> _live = {};
  final Map<int, int> _resends = {};

  static final _reply = RegExp(r'^\x1b_G([^;\x1b]*);([^\x1b]*)\x1b\\$');

  /// Reads a terminal reply. An `ENOENT` for an image this placer sent
  /// means the terminal no longer has it: it is marked unsent and its
  /// placements forgotten, so the next [flush] transmits and places it
  /// again. Returns whether that happened — the caller owes a flush.
  ///
  /// Every other reply (an OK, another error, a DA1, the graphics probe's)
  /// changes nothing, and so does an image re-sent [maxResends] times.
  bool handleReply(String reply) {
    final m = _reply.firstMatch(reply);
    if (m == null || !m.group(2)!.startsWith('ENOENT')) return false;
    int? id;
    for (final kv in m.group(1)!.split(',')) {
      if (kv.startsWith('i=')) id = int.tryParse(kv.substring(2));
    }
    if (id == null || !_transmitted.contains(id)) return false;
    final resends = _resends[id] ?? 0;
    if (resends >= maxResends) return false;
    _resends[id] = resends + 1;
    _transmitted.remove(id);
    _live.removeWhere((key, _) => key.$1 == id);
    return true;
  }

  /// The commands that take the terminal from the last frame's placements
  /// to [placements].
  ///
  /// [fullRedraw]: the screen was cleared (which drops kitty placements),
  /// so every placement is placed again — still without re-transmitting.
  String flush(List<ImagePlacement> placements, {bool fullRedraw = false}) {
    final out = StringBuffer();
    final next = <(int, int), ImagePlacement>{
      for (final p in placements) (p.imageId, p.placementId): p,
    };

    for (final entry in _live.entries) {
      if (!next.containsKey(entry.key)) {
        out.write(KittyEncoder.deletePlacement(
            imageId: entry.key.$1, placementId: entry.key.$2));
      }
    }

    for (final entry in next.entries) {
      final p = entry.value;
      if (_transmitted.add(p.imageId)) {
        out.write(KittyEncoder.transmitPng(
            pngBytes: p.image.encodePng(), imageId: p.imageId));
      }
      final before = _live[entry.key];
      if (fullRedraw || before == null || !before._sameBox(p)) {
        out.write('\x1b[${p.y + 1};${p.x + 1}H');
        out.write(KittyEncoder.place(
          imageId: p.imageId,
          placementId: p.placementId,
          columns: p.columns,
          rows: p.rows,
          quiet: 1,
        ));
      }
    }

    _live
      ..clear()
      ..addAll(next);
    return out.toString();
  }

  /// Frees every image this placer transmitted (`d=I`: placements and
  /// data), for shutdown. The next [flush] starts from nothing.
  String clearAll() {
    final out = StringBuffer();
    for (final id in _transmitted) {
      out.write(KittyEncoder.deleteImage(imageId: id));
    }
    _transmitted.clear();
    _live.clear();
    _resends.clear();
    return out.toString();
  }
}
