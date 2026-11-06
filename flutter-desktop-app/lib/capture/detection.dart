/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import '../models.dart';
import 'blocklist.dart';

/// Metadata-based risk scoring. No TLS decryption is involved: the engine
/// looks at destinations, domains, ports, process paths and direction.
class DetectionEngine {
  DetectionEngine({Set<String> allowlist = const {}})
      : _allowlist = {...allowlist};

  final Set<String> _allowlist;

  void setAllowlist(Set<String> entries) {
    _allowlist
      ..clear()
      ..addAll(entries);
  }

  bool isAllowlisted(NetworkEvent e) =>
      (e.domain.isNotEmpty && _allowlist.contains(e.domain)) ||
      (e.remoteIp.isNotEmpty && _allowlist.contains(e.remoteIp)) ||
      (e.processName.isNotEmpty && _allowlist.contains(e.processName));

  void analyze(NetworkEvent e) {
    if (isAllowlisted(e)) {
      e.riskScore = 0;
      e.severity = Severity.info;
      e.reasons = const [];
      return;
    }

    final reasons = <RiskReason>[];
    if (e.protocol == 'dns') {
      _analyzeDns(e, reasons);
    } else {
      _analyzeFlow(e, reasons);
    }

    final score = reasons
        .fold<int>(0, (sum, reason) => sum + reason.weight)
        .clamp(0, 100);
    e.riskScore = score;
    e.severity = severityFromScore(score);
    e.reasons = reasons;
  }

  void _analyzeDns(NetworkEvent e, List<RiskReason> reasons) {
    if (isBlockedDomain(e.domain)) {
      reasons.add(const RiskReason('DNS query for a blocklisted domain', 100));
    }
    if (_looksDga(e.domain)) {
      reasons.add(const RiskReason('Domain looks algorithmically generated', 40));
    }
    if (_looksLikeTunneling(e.domain)) {
      reasons.add(const RiskReason('Long, multi-label DNS name (tunneling?)', 35));
    }
  }

  void _analyzeFlow(NetworkEvent e, List<RiskReason> reasons) {
    if (isBlockedDomain(e.domain)) {
      reasons.add(const RiskReason('Destination domain is blocklisted', 100));
    }
    if (isBlockedIp(e.remoteIp)) {
      reasons.add(const RiskReason('Destination IP is blocklisted', 100));
    }
    if (e.domain.isEmpty && _isPublicIp(e.remoteIp)) {
      reasons.add(const RiskReason('Direct IP connection with no DNS name', 20));
    }
    if (_isPublicIp(e.remoteIp) && !_standardPorts.contains(e.remotePort)) {
      reasons.add(RiskReason('Non-standard destination port ${e.remotePort}', 10));
    }
    if (_looksDga(e.domain)) {
      reasons.add(const RiskReason('Domain looks algorithmically generated', 40));
    }
    if (_inTempPath(e.processPath)) {
      reasons.add(const RiskReason('Process runs from a temporary folder', 20));
    }
    if (e.direction == Direction.inbound && _isPublicIp(e.remoteIp)) {
      reasons.add(const RiskReason('Inbound connection from a public address', 15));
    }
  }

  static const Set<int> _standardPorts = {
    22, 25, 53, 80, 110, 123, 135, 139, 143, 443, 445, 587, 853, //
    993, 995, 3389, 8080, 8443,
  };

  static bool _inTempPath(String path) {
    if (path.isEmpty) return false;
    final p = path.toLowerCase();
    return p.contains('\\temp\\') ||
        p.contains('\\tmp\\') ||
        p.contains('\\appdata\\local\\temp');
  }

  static bool _looksLikeTunneling(String domain) {
    if (domain.isEmpty) return false;
    final labels = domain.split('.').where((l) => l.isNotEmpty).toList();
    if (labels.length < 4) return false;
    return labels.take(labels.length - 2).any((l) => l.length >= 30);
  }

  static bool _looksDga(String domain) {
    if (domain.isEmpty) return false;
    final labels = domain.split('.');
    if (labels.isEmpty) return false;
    final base = labels.length >= 2 ? labels[labels.length - 2] : labels.first;
    if (base.length < 10) return false;
    final letters = base.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    if (letters.isEmpty) return false;
    final vowels = letters.replaceAll(RegExp(r'[^aeiouAEIOU]'), '').length;
    final vowelRatio = vowels / letters.length;
    final digitRatio =
        base.replaceAll(RegExp(r'[^0-9]'), '').length / base.length;
    return vowelRatio < 0.18 || digitRatio > 0.35;
  }

  static bool _isPublicIp(String ip) {
    if (ip.isEmpty || !_looksLikeIpv4(ip)) return false;
    final parts = ip.split('.').map(int.parse).toList();
    final a = parts[0];
    final b = parts[1];
    if (a == 0 || a == 10 || a == 127) return false;
    if (a == 169 && b == 254) return false;
    if (a == 172 && b >= 16 && b <= 31) return false;
    if (a == 192 && b == 168) return false;
    if (a >= 224) return false;
    return true;
  }

  static bool _looksLikeIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
    }
    return true;
  }
}
