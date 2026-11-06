/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app_paths.dart';
import '../capture/helper_locator.dart';
import 'hosts_file.dart';

class HostsApplyResult {
  const HostsApplyResult(this.ok, this.message);

  final bool ok;
  final String message;
}

typedef HostsProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Reads the Windows hosts file and applies edits through the self-elevating
/// capture helper (`--apply-hosts`). Reading needs no admin rights.
class HostsService {
  static String get hostsPath {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$root\\System32\\drivers\\etc\\hosts';
  }

  static Future<HostsDocument> load() async {
    final file = File(hostsPath);
    if (!await file.exists()) {
      return HostsDocument.parse('', path: hostsPath);
    }
    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return HostsDocument.parse(text, path: hostsPath);
  }

  static Future<HostsApplyResult> addHost(
    String hostname,
    String ip, {
    String? helperPath,
  }) async {
    final host = HostsDocument.normalizeHost(hostname);
    if (host.isEmpty) {
      return const HostsApplyResult(false, 'This event has no domain name.');
    }
    final document = await load();
    document.addOrUpdate(ip, host);
    return apply(document, helperPath: helperPath);
  }

  static Future<HostsApplyResult> removeHost(
    String hostname, {
    String? helperPath,
  }) async {
    final host = HostsDocument.normalizeHost(hostname);
    if (host.isEmpty) {
      return const HostsApplyResult(false, 'This event has no domain name.');
    }
    final document = await load();
    if (document.findByHostname(host) == null) {
      return HostsApplyResult(false, '$host is not present in the hosts file.');
    }
    document.removeHostname(host);
    return apply(document, helperPath: helperPath);
  }

  static Future<HostsApplyResult> apply(
    HostsDocument document, {
    String? helperPath,
    HostsProcessStarter? startProcess,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final content = document.serialize();
    if (content.trim().isEmpty) {
      return const HostsApplyResult(
        false,
        'Refusing to write an empty hosts file.',
      );
    }
    final helper = helperPath ?? findCaptureHelper();
    if (helper == null) {
      return const HostsApplyResult(
        false,
        'netscope-capture.exe was not found next to the app.',
      );
    }

    final directory = Directory(AppPaths.dataDir());
    await directory.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final source = File(
      '${directory.path}${Platform.pathSeparator}hosts-$stamp.pending',
    );
    final status = File(
      '${directory.path}${Platform.pathSeparator}hosts-$stamp.status',
    );

    Process? process;
    try {
      await source.writeAsString(content, flush: true);
      if (await status.exists()) await status.delete();

      final starter =
          startProcess ??
          (String executable, List<String> arguments) =>
              Process.start(executable, arguments);
      process = await starter(helper, <String>[
        '--apply-hosts',
        source.path,
        '--status',
        status.path,
      ]);

      final deadline = DateTime.now().add(timeout);
      int? exitCode;
      unawaited(process.exitCode.then((code) => exitCode = code));
      while (DateTime.now().isBefore(deadline)) {
        if (await status.exists()) break;
        if (exitCode != null && exitCode != 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      if (await status.exists()) {
        final text = await status.readAsString();
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          return HostsApplyResult(
            decoded['ok'] == true,
            '${decoded['message'] ?? 'Hosts file updated.'}',
          );
        }
      }

      if (exitCode == 2) {
        return const HostsApplyResult(
          false,
          'Administrator approval was declined.',
        );
      }
      if (exitCode != null && exitCode != 0) {
        return HostsApplyResult(
          false,
          'The helper could not update the hosts file (exit $exitCode).',
        );
      }
      return const HostsApplyResult(
        false,
        'Timed out waiting for the elevated helper.',
      );
    } catch (error) {
      return HostsApplyResult(false, 'Could not update hosts: $error');
    } finally {
      if (await source.exists()) {
        try {
          await source.delete();
        } catch (_) {}
      }
      if (await status.exists()) {
        try {
          await status.delete();
        } catch (_) {}
      }
      process?.kill();
    }
  }
}
