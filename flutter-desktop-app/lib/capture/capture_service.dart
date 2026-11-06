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

import '../models.dart';

/// Phase 1 capture source: polls Windows' own connection table.
///
/// It needs no admin rights and no driver. It sees current TCP/UDP endpoints
/// plus the DNS client cache; very short-lived connections can fall between
/// two snapshots. The Phase 2 ETW helper replaces this with realtime events.
class CaptureService {
  CaptureService({
    required this.onEvents,
    this.interval = const Duration(seconds: 2),
  });

  final void Function(List<NetworkEvent> events) onEvents;
  final Duration interval;

  Timer? _timer;
  bool _running = false;
  bool _polling = false;

  final Map<int, String> _processNames = {};
  final Map<int, String> _processPaths = {};
  final Map<String, String> _ipDomains = {};
  final List<_DnsEntry> _dnsEntries = [];
  final Set<String> _seenFlows = {};
  final Set<String> _seenDns = {};
  bool _dnsPrimed = false;

  DateTime _lastProcessRefresh = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDnsRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _refreshProcesses();
    await _refreshDns();
    await _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> _poll() async {
    if (!_running || _polling) return;
    _polling = true;
    try {
      final now = DateTime.now();
      if (now.difference(_lastProcessRefresh).inSeconds >= 20) {
        await _refreshProcesses();
      }
      if (now.difference(_lastDnsRefresh).inSeconds >= 10) {
        await _refreshDns();
      }

      final rows = await _netstat();
      final listeningPorts = <int>{
        for (final row in rows)
          if (row.state == 'LISTENING' || row.remotePort == 0) row.localPort,
      };

      final events = <NetworkEvent>[];
      for (final row in rows) {
        if (row.pid <= 0 || _skipProcess(row.pid)) continue;
        final direction = _direction(row, listeningPorts);
        final key = '${row.protocol}|${row.localIp}:${row.localPort}|'
            '${row.remoteIp}:${row.remotePort}|${row.pid}|${row.state}|'
            '${direction.name}';
        if (!_seenFlows.add(key)) continue;
        events.add(NetworkEvent(
          id: '$key|${now.microsecondsSinceEpoch}',
          timestamp: now.toUtc().toIso8601String(),
          direction: direction,
          pid: row.pid,
          processName: _processName(row.pid),
          processPath: _processPaths[row.pid] ?? '',
          protocol: row.protocol,
          state: row.state,
          localIp: row.localIp,
          localPort: row.localPort,
          remoteIp: row.remoteIp,
          remotePort: row.remotePort,
          domain: _ipDomains[row.remoteIp] ?? '',
        ));
      }

      for (final dns in _dnsEntries) {
        final key = 'dns|${dns.query}|${dns.answer}';
        if (!_seenDns.add(key)) continue;
        events.add(NetworkEvent(
          id: '$key|${now.microsecondsSinceEpoch}',
          timestamp: now.toUtc().toIso8601String(),
          direction: Direction.outbound,
          pid: 0,
          processName: '(dns)',
          protocol: 'dns',
          state: 'resolved',
          localIp: '',
          localPort: 0,
          remoteIp: dns.answer,
          remotePort: 53,
          domain: dns.query,
        ));
      }

      if (_seenFlows.length > 50000) _seenFlows.clear();
      if (_seenDns.length > 20000) _seenDns.clear();
      if (events.isNotEmpty) onEvents(events);
    } catch (_) {
      // A failed snapshot must never kill the timer.
    } finally {
      _polling = false;
    }
  }

  String _processName(int pid) {
    if (pid == 4) return 'System';
    if (pid == 0) return 'System Idle';
    return _processNames[pid] ?? '';
  }

  bool _skipProcess(int pid) {
    final name = _processName(pid).toLowerCase();
    return const {
      'netstat.exe',
      'powershell.exe',
      'pwsh.exe',
      'conhost.exe',
      'tasklist.exe',
      'netscope-capture.exe',
      'netscope.exe',
    }.contains(name);
  }

  Direction _direction(_NetRow row, Set<int> listeningPorts) {
    if (row.state == 'LISTENING' || row.remotePort == 0 || row.remoteIp.isEmpty) {
      return Direction.listening;
    }
    if (_isLoopback(row.remoteIp)) return Direction.loopback;
    if (listeningPorts.contains(row.localPort) &&
        !_isPrivate(row.remoteIp)) {
      return Direction.inbound;
    }
    return Direction.outbound;
  }

  static bool _isLoopback(String ip) =>
      ip == '127.0.0.1' || ip == '::1' || ip.startsWith('127.');

  static bool _isPrivate(String ip) {
    if (ip.isEmpty) return true;
    if (ip.contains(':')) {
      final low = ip.toLowerCase();
      return low == '::1' || low.startsWith('fe80') || low.startsWith('fc') ||
          low.startsWith('fd');
    }
    final parts = ip.split('.');
    if (parts.length != 4) return true;
    final a = int.tryParse(parts[0]) ?? 0;
    final b = int.tryParse(parts[1]) ?? 0;
    if (a == 10 || a == 127 || a == 0) return true;
    if (a == 169 && b == 254) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  Future<List<_NetRow>> _netstat() async {
    final result = await Process.run('netstat', ['-ano']);
    final rows = <_NetRow>[];
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      final text = line.trim();
      if (!(text.startsWith('TCP') || text.startsWith('UDP'))) continue;
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      final protocol = parts[0].toLowerCase();
      final local = _parseAddress(parts[1]);
      final remote = _parseAddress(parts[2]);
      if (local == null || remote == null) continue;

      String state;
      int pid;
      if (protocol == 'tcp') {
        if (parts.length < 5) continue;
        state = parts[3];
        pid = int.tryParse(parts[4]) ?? 0;
      } else {
        state = 'UDP';
        pid = int.tryParse(parts[3]) ?? 0;
      }
      rows.add(_NetRow(
        protocol: protocol,
        localIp: local.$1,
        localPort: local.$2,
        remoteIp: remote.$1,
        remotePort: remote.$2,
        state: state,
        pid: pid,
      ));
    }
    return rows;
  }

  (String, int)? _parseAddress(String raw) {
    if (raw == '*:*' || raw.isEmpty) return ('', 0);
    var host = raw;
    var port = 0;
    if (raw.startsWith('[')) {
      final close = raw.indexOf(']');
      if (close < 0) return null;
      host = raw.substring(1, close);
      final rest = raw.substring(close + 1);
      if (rest.startsWith(':')) port = int.tryParse(rest.substring(1)) ?? 0;
    } else {
      final split = raw.lastIndexOf(':');
      if (split < 0) return null;
      host = raw.substring(0, split);
      port = int.tryParse(raw.substring(split + 1)) ?? 0;
    }
    if (host == '0.0.0.0' || host == '::' || host == '*') host = '';
    return (host, port);
  }

  Future<void> _refreshProcesses() async {
    _lastProcessRefresh = DateTime.now();
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-CimInstance Win32_Process | '
            'Select-Object ProcessId,Name,ExecutablePath | '
            'ConvertTo-Json -Compress',
      ]);
      final text = '${result.stdout}'.trim();
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      final list = decoded is List ? decoded : [decoded];
      for (final item in list) {
        if (item is! Map) continue;
        final pid = (item['ProcessId'] as num?)?.toInt() ?? 0;
        if (pid <= 0) continue;
        _processNames[pid] = '${item['Name'] ?? ''}';
        _processPaths[pid] = '${item['ExecutablePath'] ?? ''}';
      }
    } catch (_) {}
  }

  Future<void> _refreshDns() async {
    _lastDnsRefresh = DateTime.now();
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"Get-DnsClientCache | Where-Object { $_.Data } | "
            r"Select-Object Entry,Data | ConvertTo-Json -Compress",
      ]);
      final text = '${result.stdout}'.trim();
      if (text.isEmpty) return;
      final decoded = jsonDecode(text);
      final list = decoded is List ? decoded : [decoded];
      final ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
      _dnsEntries.clear();
      for (final item in list) {
        if (item is! Map) continue;
        final name = '${item['Entry'] ?? item['Name'] ?? ''}'.trim();
        final data = '${item['Data'] ?? ''}'.trim();
        if (name.isEmpty || data.isEmpty) continue;
        if (!ipv4.hasMatch(data)) continue;
        if (_isPrivate(data)) continue;
        _ipDomains[data] = name;
        _dnsEntries.add(_DnsEntry(name, data));
        if (!_dnsPrimed) _seenDns.add('dns|$name|$data');
      }
      _dnsPrimed = true;
    } catch (_) {}
  }
}

class _NetRow {
  const _NetRow({
    required this.protocol,
    required this.localIp,
    required this.localPort,
    required this.remoteIp,
    required this.remotePort,
    required this.state,
    required this.pid,
  });

  final String protocol;
  final String localIp;
  final int localPort;
  final String remoteIp;
  final int remotePort;
  final String state;
  final int pid;
}

class _DnsEntry {
  const _DnsEntry(this.query, this.answer);

  final String query;
  final String answer;
}
