/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../hosts/hosts_action.dart';
import '../models.dart';
import 'widgets.dart';

/// Toolbar + sortable column header + compact flow rows + footer, in one
/// bordered card (same visual language as the old network table).
class NetworkTableCard extends StatelessWidget {
  const NetworkTableCard({
    super.key,
    required this.state,
    required this.onOpen,
    required this.onHostsAction,
    required this.onClear,
    required this.onExport,
    required this.filterController,
    required this.filterFocusNode,
  });

  final AppState state;
  final ValueChanged<NetworkEvent> onOpen;
  final void Function(NetworkEvent event, HostsAction action) onHostsAction;
  final VoidCallback onClear;
  final VoidCallback onExport;
  final TextEditingController filterController;
  final FocusNode filterFocusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            state: state,
            onClear: onClear,
            onExport: onExport,
            filterController: filterController,
            filterFocusNode: filterFocusNode,
          ),
          Divider(height: 1, color: AppColors.divider),
          _ColumnHeader(state: state),
          Divider(height: 1, color: AppColors.border),
          Expanded(
            child: _Body(
              state: state,
              onOpen: onOpen,
              onHostsAction: onHostsAction,
            ),
          ),
          Divider(height: 1, color: AppColors.divider),
          _Footer(state: state),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.onClear,
    required this.onExport,
    required this.filterController,
    required this.filterFocusNode,
  });

  final AppState state;
  final VoidCallback onClear;
  final VoidCallback onExport;
  final TextEditingController filterController;
  final FocusNode filterFocusNode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.toolbar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Clear captured events',
              icon: const Icon(Icons.delete_outline),
              onPressed: onClear,
            ),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: AppColors.divider,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: SizedBox(
                height: AppSizes.field,
                child: TextField(
                  controller: filterController,
                  focusNode: filterFocusNode,
                  style: const TextStyle(fontSize: AppSizes.fontBody),
                  decoration: softDecoration(
                    context,
                    hint: 'Filter process, domain, IP, state...',
                    prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: filterController,
                      builder: (context, value, child) => value.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: 'Clear filter',
                              onPressed: () => state.setLogSearch(''),
                            ),
                    ),
                  ),
                  onChanged: state.setLogSearch,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _ProtocolTabs(state: state)),
            Tooltip(
              message: state.live
                  ? 'Live on: new events appear automatically'
                  : 'Live off: list is frozen, arrivals buffer',
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSizes.radius),
                onTap: () => state.setLive(!state.live),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: state.live,
                        onChanged: (v) => state.setLive(v ?? false),
                      ),
                      const Text(
                        'Live',
                        style: TextStyle(fontSize: AppSizes.fontBody),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Export current view as JSON',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: onExport,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProtocolTabs extends StatelessWidget {
  const _ProtocolTabs({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in AppState.protocolTabs)
            InkWell(
              onTap: () => state.setProtocolTab(tab),
              child: Container(
                height: AppSizes.toolbar,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: state.protocolTab == tab
                          ? AppColors.accent
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tab,
                  style: TextStyle(
                    fontSize: AppSizes.fontMono,
                    color: state.protocolTab == tab
                        ? AppColors.text
                        : AppColors.secondary,
                    fontWeight: state.protocolTab == tab
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Columns
// ---------------------------------------------------------------------------

class _Col {
  const _Col(this.label, this.flex, this.sort, {this.right = false});

  final String label;
  final int flex;
  final SortColumn? sort;
  final bool right;
}

const List<_Col> _cols = [
  _Col('Time', 9, SortColumn.time),
  _Col('Dir', 7, null),
  _Col('Process', 16, SortColumn.process),
  _Col('Target', 22, SortColumn.target),
  _Col('Proto', 8, SortColumn.protocol),
  _Col('State', 10, null),
  _Col('Risk', 8, SortColumn.risk, right: true),
];

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.columnHeader,
      child: Row(
        children: [
          for (final col in _cols)
            Expanded(
              flex: col.flex,
              child: _HeaderCell(
                label: col.label,
                right: col.right,
                active: col.sort != null && state.sortColumn == col.sort,
                ascending: state.sortAscending,
                onTap: col.sort == null
                    ? null
                    : () => state.setSortColumn(col.sort!),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.right,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  final String label;
  final bool right;
  final bool active;
  final bool ascending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: right ? Alignment.centerRight : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            mainAxisAlignment:
                right ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppSizes.fontMono,
                    fontWeight: FontWeight.w500,
                    color: active ? AppColors.text : AppColors.secondary,
                  ),
                ),
              ),
              if (active)
                Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 13,
                  color: AppColors.text,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.onOpen,
    required this.onHostsAction,
  });

  final AppState state;
  final ValueChanged<NetworkEvent> onOpen;
  final void Function(NetworkEvent event, HostsAction action) onHostsAction;

  @override
  Widget build(BuildContext context) {
    final events = state.pageItems;
    if (events.isEmpty) return _Empty(state: state);
    final offset = state.pageStart;
    return ListView.builder(
      primary: false,
      padding: const EdgeInsets.symmetric(vertical: 2),
      itemCount: events.length,
      itemBuilder: (context, index) => _Row(
        state: state,
        event: events[index],
        index: offset + index,
        onOpen: onOpen,
        onHostsAction: onHostsAction,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final captured = state.stored.isEmpty;
    final filtered = !captured &&
        (state.logSearch.trim().isNotEmpty ||
            state.protocolTab != 'All' ||
            state.viewKind != null);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 44,
              color: AppColors.placeholder,
            ),
            const SizedBox(height: 12),
            Text(
              captured
                  ? 'No traffic captured yet'
                  : filtered
                      ? 'No events match the filter'
                      : 'No traffic captured yet',
              style: const TextStyle(
                fontSize: AppSizes.fontBody,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 4),
            if (captured)
              const Text(
                'Start monitoring to see connections from every app.',
                style: TextStyle(
                  fontSize: AppSizes.fontSecondary,
                  color: AppColors.placeholder,
                ),
              )
            else if (filtered)
              TextButton(
                onPressed: () {
                  state.setLogSearch('');
                  state.setProtocolTab('All');
                  state.selectGroup(null);
                },
                child: const Text('Clear filter'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.state,
    required this.event,
    required this.index,
    required this.onOpen,
    required this.onHostsAction,
  });

  final AppState state;
  final NetworkEvent event;
  final int index;
  final ValueChanged<NetworkEvent> onOpen;
  final void Function(NetworkEvent event, HostsAction action) onHostsAction;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final selected = widget.state.selectedIndex == widget.index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.state.selectIndex(widget.index);
          widget.onOpen(event);
        },
        onSecondaryTapDown: _showContextMenu,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
          height: AppSizes.tableRow,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: (selected || _hovered)
                ? Border.all(
                    color: selected
                        ? AppColors.borderSelected
                        : AppColors.borderHover,
                  )
                : null,
          ),
          child: Row(
            children: [
              for (var i = 0; i < _cols.length; i++)
                Expanded(
                  flex: _cols[i].flex,
                  child: _cell(i, event, selected),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(TapDownDetails details) async {
    widget.state.selectIndex(widget.index);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );
    final hasDomain = widget.event.domain.trim().isNotEmpty;
    final action = await showMenu<HostsAction>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem<HostsAction>(
          enabled: false,
          child: Text('Hosts file'),
        ),
        if (!hasDomain)
          const PopupMenuItem<HostsAction>(
            enabled: false,
            child: Text('No domain name on this event'),
          )
        else ...[
          const PopupMenuItem<HostsAction>(
            value: HostsAction.block,
            child: _HostsMenuItem(
              icon: Icons.block,
              label: 'Block domain (0.0.0.0)',
            ),
          ),
          const PopupMenuItem<HostsAction>(
            value: HostsAction.redirect,
            child: _HostsMenuItem(
              icon: Icons.alt_route,
              label: 'Redirect to localhost',
            ),
          ),
        ],
        const PopupMenuItem<HostsAction>(
          value: HostsAction.edit,
          child: _HostsMenuItem(
            icon: Icons.edit_outlined,
            label: 'Open hosts editor',
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<HostsAction>(
          value: HostsAction.remove,
          enabled: hasDomain,
          child: const _HostsMenuItem(
            icon: Icons.delete_outline,
            label: 'Remove from hosts',
          ),
        ),
      ],
    );
    if (action != null) widget.onHostsAction(widget.event, action);
  }

  Widget _cell(int index, NetworkEvent event, bool selected) {
    final secondary = AppColors.secondary;
    final mono = TextStyle(
      fontSize: AppSizes.fontMono,
      color: secondary,
    );
    Widget content;
    switch (index) {
      case 0:
        content = Text(event.timeDisplay, style: mono);
      case 1:
        content = DirectionBadge(event.direction);
      case 2:
        content = Tooltip(
          message: event.processPath.isEmpty
              ? event.processDisplay
              : '${event.processDisplay}\n${event.processPath}',
          waitDuration: const Duration(milliseconds: 600),
          child: Text(
            event.processDisplay,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppSizes.fontMono,
              color: AppColors.text,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        );
      case 3:
        content = Tooltip(
          message: event.remoteDisplay,
          waitDuration: const Duration(milliseconds: 600),
          child: Text(
            event.targetDisplay,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppSizes.fontMono,
              color: event.isSuspicious ? AppColors.error : AppColors.text,
            ),
          ),
        );
      case 4:
        content = ProtocolBadge(event.protocol);
      case 5:
        content = Text(event.state, style: mono, overflow: TextOverflow.ellipsis);
      case 6:
        content = Align(
          alignment: Alignment.centerRight,
          child: RiskBadge(severity: event.severity, score: event.riskScore),
        );
      default:
        content = const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: index == 6 ? Alignment.centerRight : Alignment.centerLeft,
      child: content,
    );
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final events = state.visible;
    final suspicious = events.where((e) => e.isSuspicious).length;
    final inbound = events.where((e) => e.direction == Direction.inbound).length;
    final filtered = state.logSearch.trim().isNotEmpty ||
        state.protocolTab != 'All' ||
        state.viewKind != null;

    Widget item(String text, {Color? color}) => Text(
          text,
          style: TextStyle(
            fontSize: AppSizes.fontSecondary,
            color: color ?? AppColors.secondary,
          ),
        );

    return SizedBox(
      height: AppSizes.cardFooter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    item(filtered
                        ? '${events.length} of ${state.stored.length} events (filtered)'
                        : '${events.length} events'),
                    const SizedBox(width: 16),
                    item('$inbound inbound'),
                    if (suspicious > 0) ...[
                      const SizedBox(width: 16),
                      item('$suspicious suspicious',
                          color: AppColors.error),
                    ],
                  ],
                ),
              ),
            ),
            _pager(context),
          ],
        ),
      ),
    );
  }

  Widget _pager(BuildContext context) {
    final last = state.pageCount - 1;
    final atFirst = state.pageIndex <= 0;
    final atLast = state.pageIndex >= last;
    IconButton btn(IconData icon, String tip, VoidCallback? onTap) =>
        IconButton(tooltip: tip, icon: Icon(icon, size: 18), onPressed: onTap);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 1, height: 14, color: AppColors.divider),
        const SizedBox(width: 4),
        btn(Icons.skip_previous, 'First page',
            atFirst ? null : () => state.setPage(0)),
        btn(Icons.chevron_left, 'Previous page',
            atFirst ? null : () => state.setPage(state.pageIndex - 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${state.pageRangeLabel} • ${state.pageLabel}',
            maxLines: 1,
            style: const TextStyle(
              fontSize: AppSizes.fontSecondary,
              color: AppColors.secondary,
            ),
          ),
        ),
        btn(Icons.chevron_right, 'Next page',
            atLast ? null : () => state.setPage(state.pageIndex + 1)),
        btn(Icons.skip_next, 'Last page',
            atLast ? null : () => state.setPage(last)),
        const SizedBox(width: 4),
        DropdownButton<int>(
          value: state.pageSize,
          isDense: true,
          underline: const SizedBox.shrink(),
          iconEnabledColor: AppColors.secondary,
          dropdownColor: AppColors.surface,
          style: const TextStyle(
            fontSize: AppSizes.fontSecondary,
            color: AppColors.text,
          ),
          items: [
            for (final size in AppState.pageSizeOptions)
              DropdownMenuItem(
                value: size,
                child: Text(
                  '$size',
                  style: const TextStyle(
                    fontSize: AppSizes.fontSecondary,
                    color: AppColors.text,
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) state.setPageSize(v);
          },
        ),
      ],
    );
  }
}

class _HostsMenuItem extends StatelessWidget {
  const _HostsMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
