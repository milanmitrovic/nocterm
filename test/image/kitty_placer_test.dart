import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:nocterm/src/image/kitty_placer.dart';
import 'package:test/test.dart';

const _apc = '\x1b_G';
const _st = '\x1b\\';

/// A solid [width]x[height] RGBA image of one grey [level].
KittyImage _image(int width, int height, {int level = 7, String? key}) =>
    KittyImage.fromRgba(
      Uint8List(width * height * 4)..fillRange(0, width * height * 4, level),
      width,
      height,
      contentKey: key,
    );

ImagePlacement _at(KittyImage image, int placementId, int x, int y,
        {int columns = 10, int rows = 4}) =>
    ImagePlacement(
      image: image,
      placementId: placementId,
      x: x,
      y: y,
      columns: columns,
      rows: rows,
    );

/// A placement asks for errors only (`q=1`): OK stays quiet, but a
/// failure — the terminal evicted the image — is reported.
String _place(int id, int pid, int columns, int rows) =>
    '${_apc}a=p,i=$id,p=$pid,c=$columns,r=$rows,C=1,q=1$_st';

String _delete(int id, int pid) => '${_apc}a=d,d=i,i=$id,p=$pid,q=2$_st';

/// Every APC graphics command in [out], without its payload.
List<String> _controls(String out) => RegExp(r'\x1b_G([^;\x1b]*)')
    .allMatches(out)
    .map((m) => m.group(1)!)
    .toList();

int _transmits(String out) =>
    _controls(out).where((c) => c.startsWith('a=t')).length;

void main() {
  group('kitty image id', () {
    test('is the 32-bit FNV-1a hash of the content', () {
      // Published FNV-1a 32 test vectors.
      expect(kittyImageId(utf8.encode('a')), 0xe40c292c);
      expect(kittyImageId(utf8.encode('foobar')), 0xbf9cf968);
    });

    test('is never zero (kitty reserves i=0)', () {
      expect(kittyImageId(const []), isNot(0));
    });

    test('the same pixels give the same id, other pixels another', () {
      expect(_image(4, 2).id, _image(4, 2).id);
      expect(_image(4, 2).id, isNot(_image(4, 2, level: 8).id));
      expect(_image(4, 2).id, isNot(_image(2, 4).id),
          reason: 'same bytes, different shape');
    });

    test('an explicit content key names the image instead of its pixels', () {
      final keyed = _image(4, 2, key: 'blob-1');
      expect(keyed.id, kittyImageId(utf8.encode('blob-1')));
      expect(keyed.key, 'blob-1');
      expect(_image(8, 8, level: 1, key: 'blob-1').id, keyed.id);
    });
  });

  group('KittyPlacer.flush', () {
    test('the first frame transmits the image, then places it at its cell',
        () {
      final image = _image(40, 20);
      final out = KittyPlacer().flush([_at(image, 1, 3, 2)]);

      expect(_controls(out).first,
          'a=t,f=100,i=${image.id},q=2,m=0', reason: 'one small chunk');
      final payload = RegExp(r';([^\x1b]*)\x1b\\').firstMatch(out)!.group(1)!;
      final png = img.decodePng(base64Decode(payload))!;
      expect([png.width, png.height], [40, 20]);

      expect(out, endsWith('\x1b[3;4H${_place(image.id, 1, 10, 4)}'));
    });

    test('a frame with the same placements writes nothing', () {
      final placer = KittyPlacer();
      final image = _image(40, 20);
      placer.flush([_at(image, 1, 3, 2)]);

      expect(placer.flush([_at(image, 1, 3, 2)]), '');
    });

    test('a moved image is placed again, never transmitted again', () {
      final placer = KittyPlacer();
      final image = _image(40, 20);
      placer.flush([_at(image, 1, 3, 2)]);

      final out = placer.flush([_at(image, 1, 3, 9)]);

      expect(out, '\x1b[10;4H${_place(image.id, 1, 10, 4)}');
    });

    test('a resized image is placed again with its new cell size', () {
      final placer = KittyPlacer();
      final image = _image(40, 20);
      placer.flush([_at(image, 1, 3, 2)]);

      final out = placer.flush([_at(image, 1, 3, 2, columns: 20, rows: 8)]);

      expect(out, '\x1b[3;4H${_place(image.id, 1, 20, 8)}');
    });

    test('a vanished placement is deleted, keeping the image data', () {
      final placer = KittyPlacer();
      final image = _image(40, 20);
      placer.flush([_at(image, 1, 3, 2)]);

      expect(placer.flush([]), _delete(image.id, 1));
      expect(placer.flush([]), '', reason: 'deleted once');

      final back = placer.flush([_at(image, 1, 3, 2)]);
      expect(_transmits(back), 0, reason: 'd=i kept the data');
      expect(back, '\x1b[3;4H${_place(image.id, 1, 10, 4)}');
    });

    test('a full redraw places everything again without transmitting', () {
      final placer = KittyPlacer();
      final a = _image(40, 20);
      final b = _image(40, 20, level: 9);
      placer.flush([_at(a, 1, 0, 0), _at(b, 2, 0, 10)]);

      final out =
          placer.flush([_at(a, 1, 0, 0), _at(b, 2, 0, 10)], fullRedraw: true);

      expect(out,
          '\x1b[1;1H${_place(a.id, 1, 10, 4)}\x1b[11;1H${_place(b.id, 2, 10, 4)}');
    });

    test('one image in two slots is transmitted once and placed twice', () {
      final image = _image(40, 20);
      final out =
          KittyPlacer().flush([_at(image, 1, 0, 0), _at(image, 2, 20, 0)]);

      expect(_transmits(out), 1);
      expect(out, contains(_place(image.id, 1, 10, 4)));
      expect(out, contains(_place(image.id, 2, 10, 4)));
    });

    test('a swapped image deletes the old placement and places the new', () {
      final placer = KittyPlacer();
      final a = _image(40, 20);
      final b = _image(40, 20, level: 9);
      placer.flush([_at(a, 1, 0, 0)]);

      final out = placer.flush([_at(b, 1, 0, 0)]);

      expect(out, startsWith(_delete(a.id, 1)));
      expect(_transmits(out), 1);
      expect(out, endsWith(_place(b.id, 1, 10, 4)));
    });

    test('a large image is sent in 4096-byte chunks, keys on the first only',
        () {
      // Noise does not compress, so the PNG is far above one chunk.
      var seed = 1;
      final noise = Uint8List(64 * 64 * 4);
      for (var i = 0; i < noise.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        noise[i] = seed >> 16;
      }
      final image = KittyImage.fromRgba(noise, 64, 64);

      final out = KittyPlacer().flush([_at(image, 1, 0, 0)]);

      final chunks = RegExp(r'\x1b_G([^;]*);([^\x1b]*)\x1b\\')
          .allMatches(out)
          .where((m) => m.group(1)!.startsWith('a=t') ||
              m.group(1)!.startsWith('m='))
          .toList();
      expect(chunks.length, greaterThan(2));
      expect(chunks.first.group(1), 'a=t,f=100,i=${image.id},q=2,m=1');
      for (final middle in chunks.skip(1).take(chunks.length - 2)) {
        expect(middle.group(1), 'm=1');
        expect(middle.group(2)!.length, 4096);
      }
      expect(chunks.last.group(1), 'm=0');
      final payload = chunks.map((m) => m.group(2)).join();
      expect(img.decodePng(base64Decode(payload))!.width, 64);
    });

    test('never uses unicode placeholders or sixel', () {
      final placer = KittyPlacer();
      final image = _image(40, 20);
      final out = placer.flush([_at(image, 1, 3, 2)]) +
          placer.flush([_at(image, 1, 5, 2)]) +
          placer.flush([]);

      expect(out, isNot(contains('U=1')));
      expect(out, isNot(contains('\x1bP')), reason: 'no DCS / sixel');
      expect(_controls(out).where((c) => c.startsWith('a=T')), isEmpty,
          reason: 'transmit-and-display would re-send data per place');
    });
  });

  group('KittyPlacer.clearAll', () {
    test('frees every transmitted image, and the next frame sends it again',
        () {
      final placer = KittyPlacer();
      final a = _image(40, 20);
      final b = _image(40, 20, level: 9);
      placer.flush([_at(a, 1, 0, 0), _at(b, 2, 0, 10)]);

      final cleared = placer.clearAll();

      expect(cleared, contains('${_apc}a=d,d=I,i=${a.id},q=2$_st'));
      expect(cleared, contains('${_apc}a=d,d=I,i=${b.id},q=2$_st'));
      expect(placer.clearAll(), '');
      expect(_transmits(placer.flush([_at(a, 1, 0, 0)])), 1);
    });
  });

  group('KittyPlacer.handleReply (the terminal evicted an image)', () {
    String enoent(int id, int pid) =>
        '${_apc}i=$id,p=$pid;ENOENT:No image with id: $id$_st';

    test('ENOENT for a placed image: the next flush sends and places it again',
        () {
      final placer = KittyPlacer();
      final a = _image(40, 20);
      final b = _image(40, 20, level: 9);
      final frame = [_at(a, 1, 0, 0), _at(b, 2, 0, 10)];
      placer.flush(frame);

      expect(placer.handleReply(enoent(a.id, 1)), isTrue,
          reason: 'state changed: a flush is owed');

      final out = placer.flush(frame);
      expect(_controls(out).where((c) => c.startsWith('a=t')),
          ['a=t,f=100,i=${a.id},q=2,m=0'],
          reason: 'a re-sent, b (still stored) not');
      expect(out, contains('\x1b[1;1H${_place(a.id, 1, 10, 4)}'));
      expect(out, isNot(contains('a=p,i=${b.id},')));
    });

    test('an image re-sent this way comes back after a full flush too', () {
      final placer = KittyPlacer();
      final a = _image(40, 20);
      placer.flush([_at(a, 1, 0, 0)]);
      placer.handleReply(enoent(a.id, 1));
      placer.flush([_at(a, 1, 0, 0)]);

      // Stored again: an unchanged frame writes nothing.
      expect(placer.flush([_at(a, 1, 0, 0)]), '');
    });

    for (final (name, reply) in [
      ('an OK', '${_apc}i=7;OK$_st'),
      ('another error', '${_apc}i=7;EINVAL:bad$_st'),
      ('a DA1 reply', '\x1b[?62;22c'),
      ('the graphics probe\'s reply', '${_apc}i=31;OK$_st'),
    ]) {
      test('$name changes nothing', () {
        final placer = KittyPlacer();
        final a = _image(40, 20);
        placer.flush([_at(a, 1, 0, 0)]);

        expect(placer.handleReply(reply), isFalse);
        expect(placer.flush([_at(a, 1, 0, 0)]), '');
      });
    }

    test('ENOENT for an id this placer never sent changes nothing', () {
      final placer = KittyPlacer();
      final a = _image(40, 20);
      placer.flush([_at(a, 1, 0, 0)]);

      expect(placer.handleReply(enoent(a.id ^ 1, 1)), isFalse);
      expect(placer.flush([_at(a, 1, 0, 0)]), '');
    });

    test('an image the terminal keeps refusing is re-sent a few times only',
        () {
      final placer = KittyPlacer();
      final a = _image(40, 20);
      final frame = [_at(a, 1, 0, 0)];
      placer.flush(frame);
      var resends = 0;
      for (var i = 0; i < 10; i++) {
        if (!placer.handleReply(enoent(a.id, 1))) break;
        resends += _transmits(placer.flush(frame));
      }
      expect(resends, KittyPlacer.maxResends);
    });
  });
}
