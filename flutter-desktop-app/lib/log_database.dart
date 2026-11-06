/*
 * Project : NetScope — Network Monitor & Malicious Request Detector
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'app_paths.dart';
import 'models.dart';

/// SQLite persistence for captured network events and the allowlist.
class NetworkDatabase {
  NetworkDatabase(this.path);

  final String path;
  late final Database _db;
  PreparedStatement? _insert;

  static String defaultPath() => AppPaths.file('network.db');

  void open() {
    Directory(File(path).parent.path).createSync(recursive: true);
    _db = sqlite3.open(path);
    _migrate();
  }

  void _migrate() {
    _db.execute('PRAGMA journal_mode=WAL;');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id             TEXT PRIMARY KEY,
        timestamp      TEXT,
        direction      TEXT,
        pid            INTEGER,
        process_name   TEXT,
        process_path   TEXT,
        protocol       TEXT,
        state          TEXT,
        local_ip       TEXT,
        local_port     INTEGER,
        remote_ip      TEXT,
        remote_port    INTEGER,
        domain         TEXT,
        bytes_sent     INTEGER,
        bytes_received INTEGER,
        duration_ms    INTEGER,
        risk_score     INTEGER,
        severity       TEXT,
        reasons        TEXT,
        received_at    TEXT
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS allowlist (
        entry      TEXT PRIMARY KEY,
        created_at TEXT
      );
    ''');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_events_remote ON events(remote_ip);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_events_domain ON events(domain);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_events_process ON events(process_name);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_events_ts ON events(timestamp);');
    _db.execute('CREATE INDEX IF NOT EXISTS idx_events_sev ON events(severity);');
  }

  int count() =>
      _db.select('SELECT COUNT(*) AS c FROM events;').first['c'] as int;

  void insert(List<NetworkEvent> events) {
    if (events.isEmpty) return;
    final stmt = _insert ??= _db.prepare('''
      INSERT OR IGNORE INTO events
        (id, timestamp, direction, pid, process_name, process_path, protocol,
         state, local_ip, local_port, remote_ip, remote_port, domain,
         bytes_sent, bytes_received, duration_ms, risk_score, severity,
         reasons, received_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
    ''');

    final received = DateTime.now().toUtc().toIso8601String();
    _db.execute('BEGIN;');
    try {
      for (final e in events) {
        stmt.execute([
          e.id,
          e.timestamp,
          e.direction.name,
          e.pid,
          e.processName,
          e.processPath,
          e.protocol,
          e.state,
          e.localIp,
          e.localPort,
          e.remoteIp,
          e.remotePort,
          e.domain,
          e.bytesSent,
          e.bytesReceived,
          e.durationMs,
          e.riskScore,
          e.severity.name,
          jsonEncode(e.reasons.map((r) => r.toJson()).toList()),
          received,
        ]);
      }
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<NetworkEvent> loadAll({int limit = 100000}) {
    final rows = _db.select('''
      SELECT id, timestamp, direction, pid, process_name, process_path,
             protocol, state, local_ip, local_port, remote_ip, remote_port,
             domain, bytes_sent, bytes_received, duration_ms, risk_score,
             severity, reasons
      FROM events ORDER BY timestamp ASC LIMIT ?;
    ''', [limit]);
    return rows.map(_rowToEvent).toList();
  }

  NetworkEvent _rowToEvent(Row row) {
    final reasonsRaw = row['reasons'] as String?;
    var reasons = const <RiskReason>[];
    if (reasonsRaw != null && reasonsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(reasonsRaw);
        if (decoded is List) {
          reasons = decoded
              .whereType<Map>()
              .map((e) => RiskReason.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }
    return NetworkEvent(
      id: '${row['id'] ?? ''}',
      timestamp: '${row['timestamp'] ?? ''}',
      direction: Direction.values.firstWhere(
        (d) => d.name == row['direction'],
        orElse: () => Direction.outbound,
      ),
      pid: (row['pid'] as int?) ?? 0,
      processName: '${row['process_name'] ?? ''}',
      processPath: '${row['process_path'] ?? ''}',
      protocol: '${row['protocol'] ?? 'tcp'}',
      state: '${row['state'] ?? ''}',
      localIp: '${row['local_ip'] ?? ''}',
      localPort: (row['local_port'] as int?) ?? 0,
      remoteIp: '${row['remote_ip'] ?? ''}',
      remotePort: (row['remote_port'] as int?) ?? 0,
      domain: '${row['domain'] ?? ''}',
      bytesSent: (row['bytes_sent'] as int?) ?? 0,
      bytesReceived: (row['bytes_received'] as int?) ?? 0,
      durationMs: row['duration_ms'] as int?,
      riskScore: (row['risk_score'] as int?) ?? 0,
      severity: Severity.values.firstWhere(
        (s) => s.name == row['severity'],
        orElse: () => Severity.info,
      ),
      reasons: reasons,
    );
  }

  Set<String> loadAllowlist() {
    final rows = _db.select('SELECT entry FROM allowlist;');
    return rows.map((r) => '${r['entry']}').toSet();
  }

  void addAllowlist(String entry) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) return;
    _db.execute(
      'INSERT OR IGNORE INTO allowlist (entry, created_at) VALUES (?, ?);',
      [trimmed, DateTime.now().toUtc().toIso8601String()],
    );
  }

  void clear() {
    _db.execute('DELETE FROM events;');
  }

  void dispose() {
    try {
      _insert?.close();
    } catch (_) {}
    _db.close();
  }
}
