import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

import 'signal_backend_fake.dart';

void main() {
  test('terminate event (SIGTERM/SIGHUP) restores terminal state and exits '
      'with the signal exit code, bypassing component routing', () async {
    final backend = FakeSignalBackend();
    final binding = TerminalBinding(Terminal(backend, size: const Size(80, 24)));
    binding.initialize();
    backend.output.clear(); // Only observe teardown writes.

    backend.terminate.add(143); // 128 + SIGTERM
    await Future<void>.delayed(Duration.zero);

    expect(binding.shouldExit, isTrue);
    expect(backend.exitCode, 143);
    final out = backend.output.toString();
    expect(out, contains('\x1B[?1003l'), reason: 'motion tracking off');
    expect(out, contains('\x1B[?1006l'), reason: 'SGR mouse mode off');
    expect(out, contains('\x1B[?1002l'), reason: 'button tracking off');
    expect(out, contains('\x1B[?1000l'), reason: 'basic mouse tracking off');
    expect(out, contains('\x1b[?25h'), reason: 'cursor shown');
    expect(out, contains('\x1b[?1049l'), reason: 'left alternate screen');
    expect(backend.rawModeDisabled, isTrue);
  });
}
