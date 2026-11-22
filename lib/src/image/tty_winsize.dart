// Reads the controlling tty's TIOCGWINSZ, including the pixel size.
// Native only; the stub answers null where dart:ffi is unavailable.
export 'tty_winsize_stub.dart' if (dart.library.ffi) 'tty_winsize_ffi.dart';
