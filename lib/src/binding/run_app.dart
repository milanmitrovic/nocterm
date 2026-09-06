import 'package:nocterm/nocterm.dart';

import 'run_app_stub.dart'
    if (dart.library.io) 'run_app_io.dart'
    if (dart.library.html) 'run_app_web.dart';

/// Run a TUI application.
///
/// Automatically detects the platform:
/// - Native (Linux, macOS): Uses StdioBackend, checks for shell mode
/// - Web: Uses WebBackend with static bridge for WASM/JS apps
///
/// On native platforms, also checks for nocterm shell mode for IDE debugging.
///
/// If [backend] is provided, it will be used instead of the default backend.
/// This is useful for custom I/O scenarios, such as:
/// - Writing to `/dev/tty` directly while redirecting stdout to `/dev/null`
/// - Custom terminal emulation
/// - Testing with mock backends
///
/// [enableColorSchemeUpdates] opts into DEC private mode 2031, which asks the
/// terminal to report when its colour scheme changes. Notices arrive on
/// [TerminalBinding.colorSchemeNotices]; see that stream's docs for why the
/// payload should be treated as "colours changed, re-read" rather than as a
/// reading. Off by default.
Future<void> runApp(
  Component app, {
  bool enableHotReload = true,
  TerminalBackend? backend,
  bool enableColorSchemeUpdates = false,
}) {
  return runAppImpl(
    app,
    enableHotReload: enableHotReload,
    backend: backend,
    enableColorSchemeUpdates: enableColorSchemeUpdates,
  );
}
