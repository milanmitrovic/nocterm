import 'dart:async';

// `isEmpty` is a matcher in both packages; take the test package's.
import 'package:nocterm/nocterm.dart' hide isEmpty;
import 'package:test/test.dart';

import 'signal_backend_fake.dart';

/// A TerminalBinding registers dart:developer service extensions, so only one
/// can exist per isolate — hence this end-to-end check lives in its own file,
/// like the signal tests it borrows the fake backend from.
void main() {
  test(
      'enableColorSchemeUpdates turns on DEC 2031, queries once, surfaces '
      'notices on their own stream and turns the mode off at teardown',
      () async {
    final backend = FakeSignalBackend();
    final binding = TerminalBinding(Terminal(backend, size: const Size(80, 24)));

    binding.initialize(enableColorSchemeUpdates: true);

    expect(binding.colorSchemeUpdatesEnabled, isTrue);
    final startup = backend.output.toString();
    expect(startup, contains('\x1B[?2031h'), reason: 'mode 2031 enabled');
    expect(startup, contains('\x1b[?996n'),
        reason: 'initial colour-scheme query sent');

    // The terminal answers the query, then later reports a switch to light.
    final notices = <ColorSchemeNotice>[];
    final keys = <KeyboardEvent>[];
    binding.colorSchemeNotices.listen(notices.add);
    binding.keyboardEvents.listen(keys.add);

    backend.input.add('\x1b[?997;1n'.codeUnits);
    await Future<void>.delayed(Duration.zero);
    backend.input.add('\x1b[?997;2n'.codeUnits);
    await Future<void>.delayed(Duration.zero);

    expect(notices.map((n) => n.brightness),
        [Brightness.dark, Brightness.light]);
    expect(keys, isEmpty, reason: 'a report must not arrive as a keystroke');

    backend.output.clear(); // Only observe teardown writes.
    backend.terminate.add(143);
    await Future<void>.delayed(Duration.zero);

    expect(backend.output.toString(), contains('\x1B[?2031l'),
        reason: 'mode 2031 disabled before leaving the alternate screen');
  });
}
