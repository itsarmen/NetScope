/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

String humanBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}

String formatDuration(int? ms) {
  if (ms == null || ms < 0) return '—';
  if (ms < 1000) return '$ms ms';
  return '${(ms / 1000).toStringAsFixed(2)} s';
}

String readableDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final l = d.toLocal();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${p2(l.month)}-${p2(l.day)} '
      '${p2(l.hour)}:${p2(l.minute)}:${p2(l.second)}';
}
