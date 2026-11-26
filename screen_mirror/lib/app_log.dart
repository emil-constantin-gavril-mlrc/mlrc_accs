import 'dart:io';

/// Single logging sink shared by the on-screen log panel and the two
/// externally readable streams, so a failing run can be diagnosed without
/// re-running it with a debugger attached.
///
/// Every log line goes to:
///  * **stdout** — on Android this lands in logcat under the `flutter` tag,
///    readable from the PC with
///    `adb -s <serial> logcat -d -s flutter:V` (no extra permissions);
///  * **a timestamped log file** — on Windows the directory comes from
///    `--dart-define=MLRC_LOG_DIR=<dir>` (run_app.ps1 points it at
///    `<repo>\logs`), so the PC log is a plain file read. On Android the
///    file falls back to the app's own cache directory, pullable with
///    `adb exec-out run-as com.example.screen_mirror cat <file>`.
class AppLog {
  AppLog._();

  static const String _configuredDir = String.fromEnvironment('MLRC_LOG_DIR');
  static File? _file;

  /// Absolute path of the active log file, or null when file logging is off.
  static String? filePath;

  /// Picks the first writable directory from the configured hint, the
  /// current working directory, and the system temp dir, in that order.
  static void init() {
    final fileName =
        'mlrc_${Platform.isAndroid ? 'android' : 'desktop'}_$pid.log';
    final candidates = <String>[
      if (_configuredDir.isNotEmpty) _configuredDir,
      Directory.current.path,
      Directory.systemTemp.path,
    ];
    for (final dir in candidates) {
      try {
        final file = File('$dir${Platform.pathSeparator}$fileName');
        file.createSync(recursive: true);
        file.writeAsStringSync(
          '# mlrc_accs log | role=${Platform.isAndroid ? 'android' : 'desktop'} '
          '| pid=$pid | started=${DateTime.now().toIso8601String()}\n',
        );
        _file = file;
        filePath = file.path;
        break;
      } catch (_) {
        // Not writable (sandbox, permissions); try the next candidate.
      }
    }
    line('[log] file logging: ${filePath ?? 'disabled, stdout only'}');
    line('[log] platform=${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion}');
  }

  /// Writes one timestamped line to stdout and the log file (flushed per
  /// line, so a crash never loses more than the crashing line).
  static void line(String message) {
    final stamped = '${DateTime.now().toIso8601String()} $message';
    // ignore: avoid_print
    print(stamped);
    final file = _file;
    if (file != null) {
      try {
        file.writeAsStringSync('$stamped\n',
            mode: FileMode.append, flush: true);
      } catch (_) {
        // Logging must never take the app down; drop the line instead.
      }
    }
  }
}
