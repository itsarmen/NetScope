/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:netscope/capture/detection.dart';
import 'package:netscope/capture/etw_service.dart';
import 'package:netscope/models.dart';

void main() {
  test('blocklisted domain is scored critical', () {
    final event = NetworkEvent(
      protocol: 'tcp',
      remoteIp: '1.2.3.4',
      remotePort: 443,
      domain: 'malware.test',
    );
    DetectionEngine().analyze(event);
    expect(event.severity, Severity.critical);
    expect(event.reasons, isNotEmpty);
  });

  test('private addresses do not trigger the raw-IP signal', () {
    final event = NetworkEvent(
      protocol: 'tcp',
      remoteIp: '192.168.1.20',
      remotePort: 445,
      domain: '',
    );
    DetectionEngine().analyze(event);
    expect(
      event.reasons.any((r) => r.label.contains('no DNS')),
      isFalse,
    );
  });

  test('public raw IP with a non-standard port is scored', () {
    final event = NetworkEvent(
      protocol: 'tcp',
      remoteIp: '8.8.4.4',
      remotePort: 4444,
      domain: '',
    );
    DetectionEngine().analyze(event);
    expect(event.riskScore, greaterThan(0));
    expect(event.severity.rank, greaterThanOrEqualTo(Severity.low.rank));
  });

  test('allowlisted domain is reset to info', () {
    final event = NetworkEvent(
      protocol: 'tcp',
      remoteIp: '1.2.3.4',
      remotePort: 443,
      domain: 'malware.test',
    );
    DetectionEngine(allowlist: {'malware.test'}).analyze(event);
    expect(event.severity, Severity.info);
    expect(event.riskScore, 0);
  });

  test('ETW flow line maps to a NetworkEvent', () {
    final service = EtwCaptureService(onEvents: (_) {});
    final event = service.eventFromJson(<String, dynamic>{
      'kind': 'flow',
      'id': 'flow-1',
      'ts': '2026-11-06T12:00:00.000Z',
      'direction': 'inbound',
      'pid': 1234,
      'process': 'chrome.exe',
      'processPath': r'C:\Program Files\chrome.exe',
      'protocol': 'tcp',
      'state': 'established',
      'localIp': '192.168.1.10',
      'localPort': 443,
      'remoteIp': '93.184.216.34',
      'remotePort': 51544,
      'domain': 'example.com',
      'bytesSent': 0,
      'bytesReceived': 0,
    });
    expect(event, isNotNull);
    expect(event!.processName, 'chrome.exe');
    expect(event.direction, Direction.inbound);
    expect(event.protocol, 'tcp');
    expect(event.domain, 'example.com');
    expect(event.remotePort, 51544);
  });

  test('ETW loopback accept keeps the server port local', () {
    final service = EtwCaptureService(onEvents: (_) {});
    final event = service.eventFromJson(<String, dynamic>{
      'kind': 'flow',
      'direction': 'loopback',
      'pid': 17896,
      'process': 'powershell.exe',
      'protocol': 'tcp',
      'state': 'established',
      'localIp': '127.0.0.1',
      'localPort': 54321,
      'remoteIp': '127.0.0.1',
      'remotePort': 50900,
    });
    expect(event, isNotNull);
    expect(event!.direction, Direction.loopback);
    expect(event.localPort, 54321);
    expect(event.remotePort, 50900);
  });

  test('ETW DNS line maps to a dns NetworkEvent', () {
    final service = EtwCaptureService(onEvents: (_) {});
    final event = service.eventFromJson(<String, dynamic>{
      'kind': 'dns',
      'id': 'dns-1',
      'ts': '2026-11-06T12:00:00.000Z',
      'pid': 1234,
      'process': 'chrome.exe',
      'query': 'example.com',
      'status': 'Success',
      'answers': ['93.184.216.34'],
    });
    expect(event, isNotNull);
    expect(event!.protocol, 'dns');
    expect(event.domain, 'example.com');
    expect(event.remoteIp, '93.184.216.34');
    expect(event.remotePort, 53);
  });

  test('unknown ETW line is ignored', () {
    final service = EtwCaptureService(onEvents: (_) {});
    expect(
      service.eventFromJson(<String, dynamic>{'kind': 'hello'}),
      isNull,
    );
  });
}
