import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'graphics_caps.dart';

final class _Winsize extends Struct {
  @Uint16()
  external int wsRow;

  @Uint16()
  external int wsCol;

  @Uint16()
  external int wsXpixel;

  @Uint16()
  external int wsYpixel;
}

typedef _IoctlNative = Int32 Function(
    Int32 fd, UnsignedLong request, VarArgs<(Pointer<_Winsize>,)> arg);
typedef _IoctlDart = int Function(int fd, int request, Pointer<_Winsize> arg);

_IoctlDart? _ioctl;
bool _ioctlLookedUp = false;

int? get _tiocgwinsz {
  if (Platform.isLinux) return 0x5413;
  if (Platform.isMacOS) return 0x40087468;
  return null;
}

/// `ioctl(stdout, TIOCGWINSZ)` — the tty's cell and pixel size.
///
/// Null when stdout is not a tty, the platform is not Linux/macOS, or the
/// call fails. Pixel fields may be zero (many terminals leave them unset);
/// [TerminalWinsize.cellPixelSize] treats that as "not reported".
TerminalWinsize? readTtyWinsize() {
  final request = _tiocgwinsz;
  if (request == null) return null;
  if (!stdout.hasTerminal) return null;

  if (!_ioctlLookedUp) {
    _ioctlLookedUp = true;
    try {
      _ioctl = DynamicLibrary.process()
          .lookupFunction<_IoctlNative, _IoctlDart>('ioctl');
    } on ArgumentError {
      _ioctl = null;
    }
  }
  final ioctl = _ioctl;
  if (ioctl == null) return null;

  final ws = calloc<_Winsize>();
  try {
    if (ioctl(1, request, ws) != 0) return null;
    return TerminalWinsize(
      columns: ws.ref.wsCol,
      rows: ws.ref.wsRow,
      pixelWidth: ws.ref.wsXpixel,
      pixelHeight: ws.ref.wsYpixel,
    );
  } finally {
    calloc.free(ws);
  }
}
