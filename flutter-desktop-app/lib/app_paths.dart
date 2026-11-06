/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:io';

/// Resolves the per-user data directory and migrates the old NetMonitor
/// directory on first launch so existing history is not lost.
class AppPaths {
  static const appName = 'NetScope';
  static const _legacyName = 'NetMonitor';

  static String dataDir() {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
    final current = Directory('$base${Platform.pathSeparator}$appName');
    final legacy = Directory('$base${Platform.pathSeparator}$_legacyName');
    try {
      if (!current.existsSync() && legacy.existsSync()) {
        current.createSync(recursive: true);
        for (final name in const [
          'network.db',
          'network.db-wal',
          'network.db-shm',
          'settings.json',
        ]) {
          final source =
              File('${legacy.path}${Platform.pathSeparator}$name');
          if (source.existsSync()) {
            source.copySync(
              '${current.path}${Platform.pathSeparator}$name',
            );
          }
        }
      }
    } catch (_) {
      // Migration is best effort; fall through to the new path.
    }
    return current.path;
  }

  static String file(String name) =>
      '${dataDir()}${Platform.pathSeparator}$name';
}
