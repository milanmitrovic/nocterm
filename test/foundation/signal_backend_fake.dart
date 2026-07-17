import 'dart:async';

import 'package:nocterm/nocterm.dart';

/// Fake backend with controllable signal streams that records everything
/// written to the terminal instead of touching a real tty.
///
/// Shared by terminate_signal_test.dart and sigint_shutdown_test.dart —
/// they are separate files because a TerminalBinding registers
/// dart:developer service extensions, so only one can exist per isolate.
class FakeSignalBackend implements TerminalBackend {
  final output = StringBuffer();
  final shutdown = StreamController<void>.broadcast();
  final terminate = StreamController<int>.broadcast();
  final input = StreamController<List<int>>.broadcast();
  int? exitCode;
  bool rawModeDisabled = false;

  @override
  void writeRaw(String data) => output.write(data);

  @override
  Size getSize() => const Size(80, 24);

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream => input.stream;

  @override
  Stream<Size>? get resizeStream => null;

  @override
  Stream<void>? get shutdownStream => shutdown.stream;

  @override
  Stream<int>? get terminateStream => terminate.stream;

  @override
  void enableRawMode() {}

  @override
  void disableRawMode() => rawModeDisabled = true;

  @override
  bool get isAvailable => true;

  @override
  void requestExit([int code = 0]) => exitCode = code;

  @override
  void notifySizeChanged(Size newSize) {}

  @override
  void dispose() {}
}
