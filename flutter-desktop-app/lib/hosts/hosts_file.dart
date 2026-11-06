/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:io';

/// One parsed hosts file entry.
///
/// A line that starts with `#` is kept as a disabled entry when the rest of
/// the line is a valid IP + hostname pair. Ordinary comment lines are ignored
/// but preserved verbatim in [HostsDocument.serialize].
class HostsEntry {
  HostsEntry({
    required this.index,
    required this.ip,
    required this.hostnames,
    required this.comment,
    required this.enabled,
    required this.raw,
  });

  final int index;
  String ip;
  List<String> hostnames;
  String comment;
  bool enabled;
  final String raw;

  String get hostnameDisplay => hostnames.join(' ');
}

/// Parses, edits and serializes a Windows hosts file without disturbing
/// comments or blank lines.
class HostsDocument {
  HostsDocument._({
    required this.path,
    required List<String> initialLines,
    required this.lineEnding,
    required this.trailingNewline,
  }) : _lines = initialLines {
    _reparse();
  }

  factory HostsDocument.parse(String text, {String path = ''}) {
    final lineEnding = text.contains('\r\n')
        ? '\r\n'
        : text.contains('\n')
            ? '\n'
            : '\r\n';
    var trailing = text.endsWith('\n');
    final raw = text.split('\n');
    final lines = <String>[];
    for (var i = 0; i < raw.length; i++) {
      var line = raw[i];
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (i == raw.length - 1 && line.isEmpty) continue;
      lines.add(line);
    }
    if (lines.isEmpty && text.isNotEmpty) trailing = text.endsWith('\n');
    return HostsDocument._(
      path: path,
      initialLines: lines,
      lineEnding: lineEnding,
      trailingNewline: trailing,
    );
  }

  final String path;
  final String lineEnding;
  final bool trailingNewline;

  List<String> _lines;
  final List<HostsEntry> entries = <HostsEntry>[];
  bool _dirty = false;

  bool get hasChanges => _dirty;
  int get enabledCount => entries.where((e) => e.enabled).length;

  void _reparse() {
    entries.clear();
    for (var i = 0; i < _lines.length; i++) {
      final entry = _parseLine(_lines[i], i);
      if (entry != null) entries.add(entry);
    }
  }

  static HostsEntry? _parseLine(String line, int index) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    var body = trimmed;
    var enabled = true;
    if (body.startsWith('#')) {
      enabled = false;
      body = body.substring(1).trimLeft();
    }
    if (body.isEmpty) return null;

    String comment = '';
    final hash = body.indexOf('#');
    if (hash >= 0) {
      comment = body.substring(hash + 1).trim();
      body = body.substring(0, hash).trim();
    }

    final parts = body.split(RegExp(r'\s+'));
    if (parts.length < 2 || !_isIp(parts.first)) return null;
    final names = parts
        .skip(1)
        .where((part) => part.isNotEmpty && !part.startsWith('#'))
        .toList();
    if (names.isEmpty) return null;

    return HostsEntry(
      index: index,
      ip: parts.first,
      hostnames: names,
      comment: comment,
      enabled: enabled,
      raw: line,
    );
  }

  static bool _isIp(String value) => InternetAddress.tryParse(value) != null;

  static String normalizeHost(String host) =>
      host.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '');

  HostsEntry? findByHostname(String hostname) {
    final name = normalizeHost(hostname);
    for (final entry in entries) {
      if (entry.hostnames.any((h) => normalizeHost(h) == name)) {
        return entry;
      }
    }
    return null;
  }

  String _render(HostsEntry entry, {required bool enabled, String? ip}) {
    final target = ip ?? entry.ip;
    final names = entry.hostnames.join(' ');
    final comment = entry.comment.isEmpty ? '' : ' # ${entry.comment}';
    return '${enabled ? '' : '# '}$target\t$names$comment';
  }

  void setEnabled(int index, bool enabled) {
    final entry = _entryAt(index);
    if (entry == null || entry.enabled == enabled) return;
    _lines[entry.index] = _render(entry, enabled: enabled);
    _dirty = true;
    _reparse();
  }

  /// Adds a mapping or updates an existing mapping for [hostname].
  ///
  /// Returns true when an existing entry was changed.
  bool addOrUpdate(String ip, String hostname) {
    final targetIp = ip.trim();
    final name = normalizeHost(hostname);
    if (targetIp.isEmpty || name.isEmpty || !_isIp(targetIp)) return false;

    final existing = findByHostname(name);
    if (existing != null) {
      _lines[existing.index] = _render(existing, enabled: true, ip: targetIp);
      _dirty = true;
      _reparse();
      return true;
    }

    _lines.add('$targetIp\t$name');
    _dirty = true;
    _reparse();
    return false;
  }

  void removeEntry(int index) {
    final entry = _entryAt(index);
    if (entry == null) return;
    _lines.removeAt(entry.index);
    _dirty = true;
    _reparse();
  }

  void removeHostname(String hostname) {
    final name = normalizeHost(hostname);
    if (name.isEmpty) return;
    var changed = false;
    for (var i = _lines.length - 1; i >= 0; i--) {
      final entry = _parseLine(_lines[i], i);
      if (entry == null) continue;
      final remaining =
          entry.hostnames.where((h) => normalizeHost(h) != name).toList();
      if (remaining.length == entry.hostnames.length) continue;
      changed = true;
      if (remaining.isEmpty) {
        _lines.removeAt(i);
      } else {
        entry.hostnames = remaining;
        _lines[i] = _render(entry, enabled: entry.enabled);
      }
    }
    if (changed) {
      _dirty = true;
      _reparse();
    }
  }

  void markClean() {
    _dirty = false;
  }

  HostsEntry? _entryAt(int index) {
    if (index < 0 || index >= entries.length) return null;
    return entries[index];
  }

  String serialize() {
    final body = _lines.join(lineEnding);
    return trailingNewline && _lines.isNotEmpty ? '$body$lineEnding' : body;
  }
}
