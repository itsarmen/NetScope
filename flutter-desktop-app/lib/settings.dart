/*
 * Project : NetScope — Network Monitor & Malicious Request Detector
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

class AppSettings {
  AppSettings({
    this.captureEnabled = true,
    this.pollIntervalMs = 2000,
    this.detectEnabled = true,
    this.live = true,
  });

  bool captureEnabled;
  int pollIntervalMs;
  bool detectEnabled;
  bool live;

  AppSettings copyWith({
    bool? captureEnabled,
    int? pollIntervalMs,
    bool? detectEnabled,
    bool? live,
  }) =>
      AppSettings(
        captureEnabled: captureEnabled ?? this.captureEnabled,
        pollIntervalMs: pollIntervalMs ?? this.pollIntervalMs,
        detectEnabled: detectEnabled ?? this.detectEnabled,
        live: live ?? this.live,
      );

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        captureEnabled: j['captureEnabled'] != false,
        pollIntervalMs: ((j['pollIntervalMs'] as num?)?.toInt() ?? 2000)
            .clamp(500, 60000),
        detectEnabled: j['detectEnabled'] != false,
        live: j['live'] != false,
      );

  Map<String, dynamic> toJson() => {
        'captureEnabled': captureEnabled,
        'pollIntervalMs': pollIntervalMs,
        'detectEnabled': detectEnabled,
        'live': live,
      };
}

/// Loads/saves settings next to the database in %LOCALAPPDATA%.
class SettingsStore {
  SettingsStore(this.path);

  final String path;

  static String defaultPath() => AppPaths.file('settings.json');

  AppSettings load() {
    try {
      final file = File(path);
      if (!file.existsSync()) return AppSettings();
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) {
        return AppSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // corrupt/missing -> defaults
    }
    return AppSettings();
  }

  void save(AppSettings settings) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(settings.toJson()));
    } catch (_) {
      // ignore persistence errors
    }
  }
}
