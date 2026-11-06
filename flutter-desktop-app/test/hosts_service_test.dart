/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netscope/hosts/hosts_file.dart';
import 'package:netscope/hosts/hosts_service.dart';

void main() {
  HostsDocument document() => HostsDocument.parse('127.0.0.1 old.test\n');

  HostsProcessStarter statusStarter(String json) {
    return (_, args) async {
      final path = args[args.indexOf('--status') + 1];
      File(path).writeAsStringSync(json, flush: true);
      return Process.start('cmd.exe', <String>['/c', 'exit', '0']);
    };
  }

  test('declined elevation maps exit code 2', () async {
    final result = await HostsService.apply(
      document(),
      helperPath: 'fake-netscope-capture.exe',
      startProcess: (_, _) =>
          Process.start('cmd.exe', <String>['/c', 'exit', '2']),
    );
    expect(result.ok, isFalse);
    expect(result.message, contains('declined'));
  });

  test('successful status file is returned', () async {
    final result = await HostsService.apply(
      document(),
      helperPath: 'fake-netscope-capture.exe',
      startProcess: statusStarter('{"ok":true,"message":"hosts updated"}'),
    );
    expect(result.ok, isTrue);
    expect(result.message, 'hosts updated');
  });

  test('failed status message is returned', () async {
    final result = await HostsService.apply(
      document(),
      helperPath: 'fake-netscope-capture.exe',
      startProcess: statusStarter('{"ok":false,"message":"access denied"}'),
    );
    expect(result.ok, isFalse);
    expect(result.message, 'access denied');
  });

  test('non-zero helper exit is reported', () async {
    final result = await HostsService.apply(
      document(),
      helperPath: 'fake-netscope-capture.exe',
      startProcess: (_, _) =>
          Process.start('cmd.exe', <String>['/c', 'exit', '5']),
    );
    expect(result.ok, isFalse);
    expect(result.message, contains('exit 5'));
  });
}
