/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:netscope/hosts/hosts_file.dart';

void main() {
  test('hosts parser keeps comments, blank lines and disabled entries', () {
    const text = '# header\r\n'
        '\r\n'
        '127.0.0.1 localhost # loopback\r\n'
        '# 0.0.0.0 blocked.test\r\n';
    final document = HostsDocument.parse(text);

    expect(document.entries, hasLength(2));
    expect(document.entries[0].ip, '127.0.0.1');
    expect(document.entries[0].hostnames, ['localhost']);
    expect(document.entries[0].comment, 'loopback');
    expect(document.entries[0].enabled, isTrue);
    expect(document.entries[1].hostnames, ['blocked.test']);
    expect(document.entries[1].enabled, isFalse);
    expect(document.serialize(), text);
  });

  test('enabling and disabling keeps comments and uses CRLF', () {
    final document = HostsDocument.parse(
      '0.0.0.0 blocked.test # keep this',
    );
    document.setEnabled(0, false);
    expect(document.serialize(), '# 0.0.0.0\tblocked.test # keep this');

    final reloaded = HostsDocument.parse(document.serialize());
    expect(reloaded.entries.single.enabled, isFalse);
    reloaded.setEnabled(0, true);
    expect(reloaded.serialize(), '0.0.0.0\tblocked.test # keep this');
  });

  test('addOrUpdate creates a new mapping or updates the existing one', () {
    final document = HostsDocument.parse('127.0.0.1 localhost\r\n');
    expect(document.addOrUpdate('0.0.0.0', 'Example.COM'), isFalse);
    expect(document.entries.last.hostnames, ['example.com']);

    expect(document.addOrUpdate('127.0.0.1', 'example.com'), isTrue);
    expect(document.entries, hasLength(2));
    expect(document.findByHostname('EXAMPLE.com')?.ip, '127.0.0.1');
  });

  test('removeHostname removes one name without dropping the entry', () {
    final document = HostsDocument.parse(
      '10.0.0.5 first.test second.test # shared\r\n',
    );
    document.removeHostname('first.test');
    expect(document.entries.single.hostnames, ['second.test']);
    expect(document.entries.single.comment, 'shared');
    expect(document.serialize(), contains('10.0.0.5\tsecond.test'));
  });

  test('invalid IP and empty hostname are rejected', () {
    final document = HostsDocument.parse('127.0.0.1 localhost\r\n');
    expect(document.addOrUpdate('not-an-ip', 'example.com'), isFalse);
    expect(document.addOrUpdate('0.0.0.0', '   '), isFalse);
    expect(document.entries, hasLength(1));
  });
}
