import 'dart:async';

import 'package:nocterm/nocterm.dart';
import 'package:test/test.dart';

import 'signal_backend_fake.dart';

void main() {
  test('shutdown event (SIGINT) with no interceptor still restores '
      'terminal state and exits', () async {
    final backend = FakeSignalBackend();
    final binding = TerminalBinding(Terminal(backend, size: const Size(80, 24)));
    binding.initialize();
    backend.output.clear(); // Only observe teardown writes.

    backend.shutdown.add(null);
    await Future<void>.delayed(Duration.zero);

    expect(binding.shouldExit, isTrue);
    expect(backend.exitCode, 0);
    expect(backend.output.toString(), contains('\x1B[?1003l'),
        reason: 'motion tracking off');
    expect(backend.rawModeDisabled, isTrue);
  });
}
