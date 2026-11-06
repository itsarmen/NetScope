/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../hosts/hosts_file.dart';
import '../hosts/hosts_service.dart';
import 'widgets.dart';

typedef HostsDocumentLoader = Future<HostsDocument> Function();
typedef HostsDocumentApplier =
    Future<HostsApplyResult> Function(HostsDocument document);
typedef HostsToast = void Function(String message);

Future<void> showHostsDialog(
  BuildContext context, {
  String? initialHostname,
  String? initialIp,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        HostsDialog(initialHostname: initialHostname, initialIp: initialIp),
  );
}

class HostsDialog extends StatefulWidget {
  const HostsDialog({
    super.key,
    this.initialHostname,
    this.initialIp,
    this.loadDocument,
    this.applyDocument,
    this.showToast,
  });

  final String? initialHostname;
  final String? initialIp;
  final HostsDocumentLoader? loadDocument;
  final HostsDocumentApplier? applyDocument;
  final HostsToast? showToast;

  @override
  State<HostsDialog> createState() => _HostsDialogState();
}

class _HostsDialogState extends State<HostsDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _ipCtrl = TextEditingController(text: '0.0.0.0');

  HostsDocument? _document;
  String? _error;
  String _search = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialIp != null && widget.initialIp!.isNotEmpty) {
      _ipCtrl.text = widget.initialIp!;
    }
    if (widget.initialHostname != null) {
      _hostCtrl.text = HostsDocument.normalizeHost(widget.initialHostname!);
    }
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hostCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final document = await (widget.loadDocument ?? HostsService.load)();
      if (!mounted) return;
      setState(() {
        _document = document;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not read the hosts file: $error');
    }
  }

  Future<void> _reload({bool confirm = true}) async {
    if (confirm && (_document?.hasChanges ?? false)) {
      final discard = await _confirm(
        'Discard changes?',
        'Reload the hosts file and lose your unsaved edits?',
      );
      if (!discard) return;
    }
    await _load();
  }

  void _addEntry() {
    final document = _document;
    if (document == null) return;
    final ip = _ipCtrl.text.trim();
    final host = HostsDocument.normalizeHost(_hostCtrl.text);
    if (InternetAddress.tryParse(ip) == null) {
      setState(() => _error = 'Enter a valid IP address, for example 0.0.0.0.');
      return;
    }
    if (host.isEmpty) {
      setState(() => _error = 'Enter a hostname, for example example.com.');
      return;
    }
    final existed = document.findByHostname(host) != null;
    document.addOrUpdate(ip, host);
    _hostCtrl.clear();
    setState(() {
      _error = null;
      if (!existed) _search = '';
      _searchCtrl.clear();
    });
    _snack('$host ${existed ? 'updated' : 'added'} (not applied yet)');
  }

  Future<void> _apply() async {
    final document = _document;
    if (document == null || !document.hasChanges || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await (widget.applyDocument ?? HostsService.apply)(document);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      _snack(result.message);
      await _load();
    } else {
      setState(() => _error = result.message);
    }
  }

  Future<void> _remove(HostsEntry entry) async {
    final document = _document;
    if (document == null) return;
    final ok = await _confirm(
      'Remove entry',
      'Remove ${entry.hostnameDisplay} from the hosts file?',
    );
    if (!ok) return;
    document.removeEntry(document.entries.indexOf(entry));
    setState(() => _error = null);
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _snack(String message) {
    final toast = widget.showToast;
    if (toast != null) {
      toast(message);
      return;
    }
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM_RIGHT,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 64).clamp(520.0, 820.0).toDouble();
    final height = (screen.height - 64).clamp(420.0, 640.0).toDouble();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radiusPopup),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_error != null) _errorBanner(context),
              Expanded(child: _body(context)),
              _footer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const Icon(Icons.dns_outlined, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hosts file',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  HostsService.hostsPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppSizes.fontSecondary,
                    color: AppColors.secondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reload hosts file',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : () => _reload(),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppSizes.fontBody),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final document = _document;
    if (document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final query = _search.trim().toLowerCase();
    final entries = document.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.ip.toLowerCase().contains(query) ||
          entry.hostnames.any((h) => h.toLowerCase().contains(query)) ||
          entry.comment.toLowerCase().contains(query);
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _editorBar(context),
          const SizedBox(height: 8),
          _listHeader(context),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSizes.radius),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: entries.isEmpty
                  ? _empty(context)
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (context, index) =>
                          _entryRow(context, document, entries[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorBar(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: SizedBox(
            height: AppSizes.field,
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: AppSizes.fontBody),
              decoration: softDecoration(
                context,
                hint: 'Search entries',
                prefixIcon: const Icon(
                  Icons.search,
                  size: AppSizes.sideRowIcon,
                ),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 132,
          height: AppSizes.field,
          child: TextField(
            controller: _ipCtrl,
            style: const TextStyle(
              fontSize: AppSizes.fontMono,
              fontFamily: 'monospace',
            ),
            decoration: softDecoration(context, hint: '0.0.0.0'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: SizedBox(
            height: AppSizes.field,
            child: TextField(
              controller: _hostCtrl,
              style: const TextStyle(fontSize: AppSizes.fontBody),
              decoration: softDecoration(
                context,
                hint: 'Hostname, for example example.com',
              ),
              onSubmitted: (_) => _addEntry(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _document == null ? null : _addEntry,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
        ),
      ],
    );
  }

  Widget _listHeader(BuildContext context) {
    const style = TextStyle(
      fontSize: AppSizes.fontSecondary,
      color: AppColors.secondary,
      fontWeight: FontWeight.w600,
    );
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 42, child: Text('On', style: style)),
          const SizedBox(width: 140, child: Text('IP', style: style)),
          const Expanded(child: Text('Hostnames', style: style)),
          const SizedBox(width: 150, child: Text('Comment', style: style)),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _entryRow(
    BuildContext context,
    HostsDocument document,
    HostsEntry entry,
  ) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Checkbox(
              value: entry.enabled,
              onChanged: _busy
                  ? null
                  : (value) {
                      document.setEnabled(
                        document.entries.indexOf(entry),
                        value ?? false,
                      );
                      setState(() {});
                    },
            ),
          ),
          SizedBox(
            width: 140,
            child: Text(
              entry.ip,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AppSizes.fontMono,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              entry.hostnameDisplay,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppSizes.fontBody),
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              entry.comment,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AppSizes.fontSecondary,
                color: AppColors.secondary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove entry',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: _busy ? null : () => _remove(entry),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined, size: 36, color: AppColors.placeholder),
          SizedBox(height: 8),
          Text(
            'No hosts entries',
            style: TextStyle(
              fontSize: AppSizes.fontBody,
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final document = _document;
    final dirty = document?.hasChanges ?? false;
    final count = document?.entries.length ?? 0;
    final enabled = document?.enabledCount ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dirty
                  ? '$count entries, $enabled enabled - unsaved changes'
                  : '$count entries, $enabled enabled',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AppSizes.fontSecondary,
                color: AppColors.secondary,
              ),
            ),
          ),
          if (dirty)
            TextButton(
              onPressed: _busy ? null : () => _reload(),
              child: const Text('Discard'),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: dirty && !_busy ? _apply : null,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Apply changes'),
          ),
        ],
      ),
    );
  }
}
