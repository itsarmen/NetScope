/*
 * Project : NetScope — Network Monitor & Malicious Request Detector
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

/// Direction of a captured network flow.
enum Direction { outbound, inbound, loopback, listening }

extension DirectionLabel on Direction {
  String get label => switch (this) {
        Direction.outbound => 'OUT',
        Direction.inbound => 'IN',
        Direction.loopback => 'LOOP',
        Direction.listening => 'LISTEN',
      };
}

/// Risk band derived from the 0-100 score.
enum Severity { info, low, medium, high, critical }

extension SeverityLabel on Severity {
  String get label => switch (this) {
        Severity.info => 'info',
        Severity.low => 'low',
        Severity.medium => 'medium',
        Severity.high => 'high',
        Severity.critical => 'critical',
      };

  int get rank => switch (this) {
        Severity.info => 0,
        Severity.low => 1,
        Severity.medium => 2,
        Severity.high => 3,
        Severity.critical => 4,
      };
}

Severity severityFromScore(int score) {
  if (score >= 80) return Severity.critical;
  if (score >= 60) return Severity.high;
  if (score >= 40) return Severity.medium;
  if (score >= 20) return Severity.low;
  return Severity.info;
}

/// One weighted explanation produced by the detection engine.
class RiskReason {
  const RiskReason(this.label, this.weight);

  final String label;
  final int weight;

  Map<String, dynamic> toJson() => {'label': label, 'weight': weight};

  factory RiskReason.fromJson(Map<String, dynamic> j) => RiskReason(
        '${j['label'] ?? ''}',
        (j['weight'] as num?)?.toInt() ?? 0,
      );
}

/// A single captured network flow (connection, listener or DNS resolution).
class NetworkEvent {
  NetworkEvent({
    this.id = '',
    this.timestamp = '',
    this.direction = Direction.outbound,
    this.pid = 0,
    this.processName = '',
    this.processPath = '',
    this.protocol = 'tcp',
    this.state = '',
    this.localIp = '',
    this.localPort = 0,
    this.remoteIp = '',
    this.remotePort = 0,
    this.domain = '',
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.durationMs,
    this.riskScore = 0,
    this.severity = Severity.info,
    this.reasons = const [],
  });

  String id;
  String timestamp;
  Direction direction;
  int pid;
  String processName;
  String processPath;
  String protocol;
  String state;
  String localIp;
  int localPort;
  String remoteIp;
  int remotePort;
  String domain;
  int bytesSent;
  int bytesReceived;
  int? durationMs;
  int riskScore;
  Severity severity;
  List<RiskReason> reasons;

  bool get isSuspicious => riskScore >= 40;

  String get processDisplay =>
      processName.isEmpty ? (pid > 0 ? 'pid $pid' : 'system') : processName;

  String get targetDisplay => domain.isNotEmpty ? domain : remoteIp;

  String get remoteDisplay {
    if (remoteIp.isEmpty) return '*';
    return remotePort > 0 ? '$remoteIp:$remotePort' : remoteIp;
  }

  String get localDisplay =>
      localPort > 0 ? '$localIp:$localPort' : localIp;

  String get timeDisplay {
    final d = DateTime.tryParse(timestamp);
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}:'
        '${l.second.toString().padLeft(2, '0')}';
  }

  String get dateTimeDisplay {
    final d = DateTime.tryParse(timestamp);
    if (d == null) return timestamp;
    final l = d.toLocal();
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${p2(l.month)}-${p2(l.day)} '
        '${p2(l.hour)}:${p2(l.minute)}:${p2(l.second)}';
  }

  factory NetworkEvent.fromJson(Map<String, dynamic> j) => NetworkEvent(
        id: '${j['id'] ?? ''}',
        timestamp: '${j['timestamp'] ?? ''}',
        direction: Direction.values.firstWhere(
          (d) => d.name == j['direction'],
          orElse: () => Direction.outbound,
        ),
        pid: (j['pid'] as num?)?.toInt() ?? 0,
        processName: '${j['processName'] ?? ''}',
        processPath: '${j['processPath'] ?? ''}',
        protocol: '${j['protocol'] ?? 'tcp'}',
        state: '${j['state'] ?? ''}',
        localIp: '${j['localIp'] ?? ''}',
        localPort: (j['localPort'] as num?)?.toInt() ?? 0,
        remoteIp: '${j['remoteIp'] ?? ''}',
        remotePort: (j['remotePort'] as num?)?.toInt() ?? 0,
        domain: '${j['domain'] ?? ''}',
        bytesSent: (j['bytesSent'] as num?)?.toInt() ?? 0,
        bytesReceived: (j['bytesReceived'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt(),
        riskScore: (j['riskScore'] as num?)?.toInt() ?? 0,
        severity: Severity.values.firstWhere(
          (s) => s.name == j['severity'],
          orElse: () => Severity.info,
        ),
        reasons: j['reasons'] is List
            ? (j['reasons'] as List)
                .whereType<Map>()
                .map((e) => RiskReason.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'direction': direction.name,
        'pid': pid,
        'processName': processName,
        'processPath': processPath,
        'protocol': protocol,
        'state': state,
        'localIp': localIp,
        'localPort': localPort,
        'remoteIp': remoteIp,
        'remotePort': remotePort,
        'domain': domain,
        'bytesSent': bytesSent,
        'bytesReceived': bytesReceived,
        if (durationMs != null) 'durationMs': durationMs,
        'riskScore': riskScore,
        'severity': severity.name,
        'reasons': reasons.map((r) => r.toJson()).toList(),
      };
}

/// Sidebar group kind.
enum GroupKind { all, suspicious, inbound, process, domain }

class GroupItem {
  GroupItem({required this.name, required this.kind, this.count = 0});

  final String name;
  final GroupKind kind;
  int count;

  String get display => switch (kind) {
        GroupKind.all => 'All activity',
        GroupKind.suspicious => 'Suspicious',
        GroupKind.inbound => 'Inbound',
        GroupKind.process => name,
        GroupKind.domain => name,
      };

  String get key => '${kind.name}:$name';
}
