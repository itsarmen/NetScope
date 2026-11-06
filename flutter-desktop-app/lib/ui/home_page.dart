/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:yaru/yaru.dart';

import '../app_state.dart';
import '../capture/capture_coordinator.dart';
import '../hosts/hosts_action.dart';
import '../hosts/hosts_file.dart';
import '../hosts/hosts_service.dart';
import '../models.dart';
import 'event_details_dialog.dart';
import 'hosts_dialog.dart';
import 'network_table.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _dismissedError;

  final TextEditingController _groupSearchCtrl = TextEditingController();
  final TextEditingController _filterCtrl = TextEditingController();
  final FocusNode _groupSearchFocus = FocusNode();
  final FocusNode _filterFocus = FocusNode();
  final FocusNode _tableFocus = FocusNode();

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _groupSearchCtrl.addListener(
      () => state.setGroupSearch(_groupSearchCtrl.text),
    );
  }

  @override
  void dispose() {
    _groupSearchCtrl.dispose();
    _filterCtrl.dispose();
    _groupSearchFocus.dispose();
    _filterFocus.dispose();
    _tableFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final sideWidth = (constraints.maxWidth * 0.3).clamp(
            AppSizes.sidebarMin,
            AppSizes.sidebarMax,
          );
          if (wide) {
            return Scaffold(
              backgroundColor: AppColors.surface,
              body: SelectionArea(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: sideWidth, child: _sidebar(context)),
                    Expanded(child: _rightPane(context)),
                  ],
                ),
              ),
            );
          }
          return Scaffold(
            drawer: Drawer(
              width: sideWidth,
              child: SelectionArea(child: _sidebar(context)),
            ),
            body: SelectionArea(child: _rightPane(context, drawerButton: true)),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------------
  // Sidebar
  // ------------------------------------------------------------------

  Widget _sidebar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sideHeader(context),
          _groupSearchField(context),
          Expanded(
            child: state.groupsView.isEmpty
                ? _sidebarEmpty(context)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    itemCount: state.groupsView.length,
                    itemBuilder: (context, index) =>
                        _groupRow(context, state.groupsView[index]),
                  ),
          ),
          _sideBottom(context),
        ],
      ),
    );
  }

  Widget _sideHeader(BuildContext context) {
    return Container(
      height: AppSizes.header,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: const Text(
        'NetScope',
        style: TextStyle(
          fontSize: AppSizes.fontTitle,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _groupSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: SizedBox(
        height: AppSizes.field,
        child: TextField(
          controller: _groupSearchCtrl,
          focusNode: _groupSearchFocus,
          style: const TextStyle(fontSize: AppSizes.fontBody),
          decoration: softDecoration(
            context,
            hint: 'Search processes, domains',
            prefixIcon: const Icon(Icons.search, size: AppSizes.sideRowIcon),
          ),
        ),
      ),
    );
  }

  Widget _groupRow(BuildContext context, GroupItem item) {
    final selected = item.kind == GroupKind.all
        ? state.viewKind == null
        : state.viewKind == item.kind && state.viewName == item.name;
    return _SideRow(
      key: ValueKey('group-${item.key}'),
      item: item,
      selected: selected,
      onTap: () => state.selectGroup(item),
    );
  }

  Widget _sidebarEmpty(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar, size: 40, color: AppColors.placeholder),
            SizedBox(height: 12),
            Text(
              'No traffic yet',
              style: TextStyle(
                fontSize: AppSizes.fontBody,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Start monitoring to see processes, domains and connections.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppSizes.fontSecondary,
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideBottom(BuildContext context) {
    final running = state.captureRunning;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: AppColors.divider),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: running ? state.stopCapture : state.startCapture,
                icon: Icon(
                  running ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                  size: 18,
                ),
                label: Text(running ? 'Stop monitoring' : 'Start monitoring'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => showHostsDialog(context),
                icon: const Icon(Icons.dns_outlined, size: 18),
                label: const Text('Hosts file'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: state.settings.detectEnabled,
                    onChanged: (v) => state.setDetectEnabled(v ?? true),
                  ),
                  const Expanded(
                    child: Text(
                      'Detect malicious requests',
                      style: TextStyle(fontSize: AppSizes.fontBody),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppBadge(
                    label: state.captureModeLabel,
                    color: switch (state.captureMode) {
                      CaptureMode.etw => AppColors.success,
                      CaptureMode.polling => AppColors.warning,
                      CaptureMode.stopped => AppColors.secondary,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppSizes.fontSecondary,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // Right pane
  // ------------------------------------------------------------------

  Widget _rightPane(BuildContext context, {bool drawerButton = false}) {
    final titleBar = YaruWindowTitleBar(
      leading: drawerButton
          ? Builder(
              builder: (context) => IconButton(
                tooltip: 'Groups',
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            )
          : null,
      title: Text(_title),
      actions: _actions(context),
    );

    return Focus(
      focusNode: _tableFocus,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _focusFilter,
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              state.moveSelection(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              state.moveSelection(-1),
          const SingleActivator(LogicalKeyboardKey.enter): _openSelected,
          const SingleActivator(LogicalKeyboardKey.escape): _escape,
        },
        child: Builder(
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBar,
              if (_errorMessage != null && _errorMessage != _dismissedError)
                _errorBanner(context),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: NetworkTableCard(
                    state: state,
                    onOpen: (event) => showEventDialog(context, state, event),
                    onHostsAction: _onHostsAction,
                    onClear: _clear,
                    onExport: _export,
                    filterController: _filterCtrl,
                    filterFocusNode: _filterFocus,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _focusFilter() {
    _filterFocus.requestFocus();
  }

  void _openSelected() {
    final event = state.selectedEvent;
    if (event != null) showEventDialog(context, state, event);
  }

  void _escape() {
    if (_filterCtrl.text.isNotEmpty) {
      _filterCtrl.clear();
      state.setLogSearch('');
      return;
    }
    if (state.selectedIndex >= 0) state.selectIndex(-1);
  }

  String? get _errorMessage {
    final s = state.status;
    if (s.startsWith('Capture failed') || s.startsWith('Could not')) {
      return s;
    }
    return null;
  }

  String get _title {
    final label = switch (state.viewKind) {
      null => 'All activity',
      GroupKind.suspicious => 'Suspicious',
      GroupKind.inbound => 'Inbound',
      _ => state.viewName ?? 'All activity',
    };
    return '$label · ${state.visible.length}';
  }

  List<Widget> _actions(BuildContext context) {
    return [
      IconButton(
        tooltip: state.captureRunning ? 'Stop monitoring' : 'Start monitoring',
        icon: Icon(
          state.captureRunning
              ? Icons.stop_circle_outlined
              : Icons.play_circle_outline,
        ),
        onPressed:
            state.captureRunning ? state.stopCapture : state.startCapture,
      ),
      IconButton(
        tooltip: state.live ? 'Pause live updates' : 'Resume live updates',
        isSelected: !state.live,
        selectedIcon: const Icon(Icons.play_arrow_outlined),
        icon: const Icon(Icons.pause_outlined),
        onPressed: () => state.setLive(!state.live),
      ),
      IconButton(
        tooltip: 'Hosts file',
        icon: const Icon(Icons.dns_outlined),
        onPressed: () => showHostsDialog(context),
      ),
      PopupMenuButton<String>(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          if (value == 'clear') {
            _clear();
          } else if (value == 'export') {
            _export();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'clear', child: Text('Clear all events')),
          PopupMenuItem(
              value: 'export', child: Text('Export current view → JSON')),
        ],
      ),
      const SizedBox(width: 6),
    ];
  }

  Widget _errorBanner(BuildContext context) {
    final message = _errorMessage!;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppSizes.fontBody),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _dismissedError = message),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  Future<void> _clear() async {
    final ok = await _confirm(
      'Clear all events',
      'Delete every captured network event?',
    );
    if (!ok) return;
    state.clearAll();
  }

  Future<void> _export() async {
    final events = state.visible;
    if (events.isEmpty) {
      _snack('Nothing to export');
      return;
    }
    final suggested =
        'NetScope-${DateTime.now().millisecondsSinceEpoch}.json';
    final location = await getSaveLocation(suggestedName: suggested);
    if (location == null) return;
    final text = const JsonEncoder.withIndent('  ')
        .convert(events.map((e) => e.toJson()).toList());
    await File(location.path).writeAsString(text);
    _snack('Exported ${events.length} events');
  }

  Future<void> _onHostsAction(NetworkEvent event, HostsAction action) async {
    final host = HostsDocument.normalizeHost(event.domain);
    if (action == HostsAction.edit) {
      await showHostsDialog(
        context,
        initialHostname: host.isEmpty ? null : host,
      );
      return;
    }
    if (host.isEmpty) {
      _snack('This event has no domain name to add to the hosts file.');
      return;
    }

    if (action == HostsAction.remove) {
      final ok = await _confirmHosts(
        'Remove $host',
        'Remove every hosts-file entry for "$host"?\n\n'
            'Windows will ask for administrator approval before the file '
            'is changed.',
        confirmLabel: 'Remove',
      );
      if (!ok) return;
      final result = await HostsService.removeHost(host);
      _snack(result.message);
      return;
    }

    final ip = action == HostsAction.block ? '0.0.0.0' : '127.0.0.1';
    final label = action == HostsAction.block ? 'Block' : 'Redirect';
    final ok = await _confirmHosts(
      '$label $host',
      'Add "$ip $host" to the Windows hosts file?\n\n'
          'Windows will ask for administrator approval. The DNS cache is '
          'flushed after the file is updated.',
      confirmLabel: 'Add to hosts',
    );
    if (!ok) return;
    final result = await HostsService.addHost(host, ip);
    _snack(result.message);
  }

  Future<bool> _confirmHosts(
    String title,
    String message, {
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _snack(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.BOTTOM_RIGHT,
      timeInSecForIosWeb: 2,
      backgroundColor: Colors.black87,
      textColor: Colors.white,
    );
  }
}

// ----------------------------------------------------------------------
// Sidebar row
// ----------------------------------------------------------------------

class _SideRow extends StatefulWidget {
  const _SideRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GroupItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SideRow> createState() => _SideRowState();
}

class _SideRowState extends State<_SideRow> {
  bool _hovered = false;

  IconData get _icon => switch (widget.item.kind) {
        GroupKind.all => Icons.public,
        GroupKind.suspicious => Icons.gpp_maybe_outlined,
        GroupKind.inbound => Icons.call_received,
        GroupKind.process => Icons.memory,
        GroupKind.domain => Icons.language,
      };

  @override
  Widget build(BuildContext context) {
    final border = widget.selected
        ? Border.all(color: AppColors.borderSelected)
        : _hovered
            ? Border.all(color: AppColors.borderHover)
            : null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(vertical: 2),
          height: AppSizes.sideRow,
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sideRowPad),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: border,
          ),
          child: Row(
            children: [
              Icon(
                _icon,
                size: AppSizes.sideRowIcon,
                color: AppColors.text,
              ),
              const SizedBox(width: AppSizes.sideRowGap),
              Expanded(
                child: Text(
                  widget.item.display,
                  style: TextStyle(
                    fontSize: AppSizes.fontRowLabel,
                    fontWeight: widget.selected
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              CountPill(widget.item.count),
            ],
          ),
        ),
      ),
    );
  }
}
