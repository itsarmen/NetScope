/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'capture/capture_coordinator.dart';
import 'capture/detection.dart';
import 'log_database.dart';
import 'models.dart';
import 'settings.dart';

enum SortColumn { time, process, target, protocol, risk }

class AppState extends ChangeNotifier {
  AppState(this.db, this.settingsStore) {
    settings = settingsStore.load();
    _capture = CaptureCoordinator(
      onEvents: _onEvents,
      onModeChanged: _onCaptureMode,
      interval: Duration(milliseconds: settings.pollIntervalMs),
    );
    detector = DetectionEngine(allowlist: db.loadAllowlist());
    live = settings.live;
  }

  final NetworkDatabase db;
  final SettingsStore settingsStore;
  late CaptureCoordinator _capture;
  late final DetectionEngine detector;
  late AppSettings settings;

  final List<NetworkEvent> all = <NetworkEvent>[];
  final List<NetworkEvent> pending = <NetworkEvent>[];
  final Set<String> _keys = <String>{};

  final List<GroupItem> groups = <GroupItem>[
    GroupItem(name: '', kind: GroupKind.all),
  ];

  List<NetworkEvent> _displayAll = <NetworkEvent>[];
  List<NetworkEvent> get stored => _displayAll;

  GroupKind? viewKind;
  String? viewName;
  String groupSearch = '';
  String logSearch = '';
  String protocolTab = 'All';
  SortColumn sortColumn = SortColumn.time;
  bool sortAscending = false;
  int selectedIndex = -1;
  bool live = true;
  bool captureRunning = false;
  CaptureMode captureMode = CaptureMode.stopped;
  String status = 'Idle';
  bool _disposed = false;

  static const List<String> protocolTabs = [
    'All',
    'TCP',
    'UDP',
    'DNS',
    'Suspicious',
    'Listening',
  ];

  static const List<int> pageSizeOptions = [25, 50, 100, 200];
  int pageSize = 50;
  int pageIndex = 0;

  Timer? _flushTimer;

  GroupItem get allGroup => groups.first;

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  Future<void> init() async {
    try {
      for (final event in db.loadAll()) {
        _addCore(event);
      }
    } catch (e) {
      status = 'Could not load history: $e';
    }
    _rebuildDisplay();
    notifyListeners();
    if (settings.captureEnabled) await startCapture();
  }

  Future<void> startCapture() async {
    if (captureRunning) return;
    status = 'Starting capture...';
    notifyListeners();
    try {
      await _capture.start();
      captureRunning = _capture.isRunning;
    } catch (e) {
      captureRunning = false;
      status = 'Capture failed: $e';
    }
    notifyListeners();
  }

  Future<void> stopCapture() async {
    await _capture.stop();
    captureRunning = false;
    notifyListeners();
  }

  void _onCaptureMode(CaptureMode mode, String detail) {
    captureMode = mode;
    captureRunning = mode != CaptureMode.stopped;
    status = switch (mode) {
      CaptureMode.etw => 'Realtime ETW capture (elevated)',
      CaptureMode.polling => 'Polling capture (ETW unavailable)',
      CaptureMode.stopped => 'Capture stopped',
    };
    if (!_disposed) notifyListeners();
  }

  String get captureModeLabel => switch (captureMode) {
        CaptureMode.etw => 'ETW',
        CaptureMode.polling => 'POLL',
        CaptureMode.stopped => 'OFF',
      };

  // ------------------------------------------------------------------
  // Ingest
  // ------------------------------------------------------------------

  void _onEvents(List<NetworkEvent> events) {
    if (_disposed || events.isEmpty) return;
    if (settings.detectEnabled) {
      for (final event in events) {
        detector.analyze(event);
      }
    }
    try {
      db.insert(events);
    } catch (e) {
      status = 'Save failed: $e';
    }
    pending.addAll(events);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (!live) {
      notifyListeners();
      return;
    }
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 300), flushPending);
  }

  void flushPending() {
    _flushTimer?.cancel();
    if (pending.isEmpty) return;
    final added = <NetworkEvent>[];
    for (final event in pending) {
      if (_addCore(event)) added.add(event);
    }
    pending.clear();
    if (added.isNotEmpty) {
      _rebuildDisplay();
      if (live) pageIndex = 0;
    }
    notifyListeners();
  }

  bool _addCore(NetworkEvent event) {
    if (!_keys.add(event.id)) return false;
    all.add(event);
    return true;
  }

  // ------------------------------------------------------------------
  // Display set + groups
  // ------------------------------------------------------------------

  void _rebuildDisplay() {
    _displayAll = List<NetworkEvent>.of(all);
    _rebuildGroups();
  }

  void _rebuildGroups() {
    groups
      ..clear()
      ..add(GroupItem(name: '', kind: GroupKind.all))
      ..add(GroupItem(name: '', kind: GroupKind.suspicious))
      ..add(GroupItem(name: '', kind: GroupKind.inbound));

    final processCounts = <String, int>{};
    final domainCounts = <String, int>{};
    for (final event in _displayAll) {
      if (event.processName.isNotEmpty) {
        processCounts[event.processName] =
            (processCounts[event.processName] ?? 0) + 1;
      }
      if (event.domain.isNotEmpty) {
        domainCounts[event.domain] = (domainCounts[event.domain] ?? 0) + 1;
      }
    }

    final processes = processCounts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in processes) {
      groups.add(GroupItem(
        name: name,
        kind: GroupKind.process,
        count: processCounts[name]!,
      ));
    }

    final domains = domainCounts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final name in domains) {
      groups.add(GroupItem(
        name: name,
        kind: GroupKind.domain,
        count: domainCounts[name]!,
      ));
    }

    _recountGroups();
  }

  void _recountGroups() {
    allGroup.count = _displayAll.length;
    groups[1].count = _displayAll.where((e) => e.isSuspicious).length;
    groups[2].count =
        _displayAll.where((e) => e.direction == Direction.inbound).length;
    for (final group in groups) {
      if (group.kind == GroupKind.process) {
        group.count =
            _displayAll.where((e) => e.processName == group.name).length;
      } else if (group.kind == GroupKind.domain) {
        group.count = _displayAll.where((e) => e.domain == group.name).length;
      }
    }
  }

  // ------------------------------------------------------------------
  // Settings
  // ------------------------------------------------------------------

  void setDetectEnabled(bool value) {
    settings.detectEnabled = value;
    settingsStore.save(settings);
    _reanalyzeAll();
    notifyListeners();
  }

  void setPollInterval(int ms) {
    settings.pollIntervalMs = ms.clamp(500, 60000);
    settingsStore.save(settings);
    _restartCapture();
    notifyListeners();
  }

  Future<void> _restartCapture() async {
    if (!captureRunning) return;
    await _capture.restartPolling();
  }

  void _reanalyzeAll() {
    if (settings.detectEnabled) {
      for (final event in all) {
        detector.analyze(event);
      }
    }
    _rebuildDisplay();
  }

  void addAllowlist(NetworkEvent event) {
    for (final entry in [
      event.domain,
      event.remoteIp,
      event.processName,
    ]) {
      if (entry.isEmpty || entry == '(dns)') continue;
      db.addAllowlist(entry);
    }
    detector.setAllowlist(db.loadAllowlist());
    _reanalyzeAll();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Filters, sort, selection
  // ------------------------------------------------------------------

  void selectGroup(GroupItem? item) {
    if (item == null || item.kind == GroupKind.all) {
      viewKind = null;
      viewName = null;
    } else {
      viewKind = item.kind;
      viewName = item.name;
    }
    pageIndex = 0;
    _selectFirst();
    notifyListeners();
  }

  void setGroupSearch(String value) {
    groupSearch = value;
    notifyListeners();
  }

  void setLogSearch(String value) {
    logSearch = value;
    pageIndex = 0;
    _selectFirst();
    notifyListeners();
  }

  void setProtocolTab(String value) {
    protocolTab = value;
    pageIndex = 0;
    _selectFirst();
    notifyListeners();
  }

  void setSortColumn(SortColumn column) {
    if (sortColumn == column) {
      sortAscending = !sortAscending;
    } else {
      sortColumn = column;
      sortAscending = column == SortColumn.process ||
          column == SortColumn.target ||
          column == SortColumn.protocol;
    }
    notifyListeners();
  }

  void setLive(bool value) {
    live = value;
    settings.live = value;
    settingsStore.save(settings);
    if (value) flushPending();
    notifyListeners();
  }

  void selectIndex(int index) {
    selectedIndex = index;
    notifyListeners();
  }

  void moveSelection(int delta) {
    final list = visible;
    if (list.isEmpty) return;
    var index = selectedIndex + delta;
    if (index < 0) index = 0;
    if (index >= list.length) index = list.length - 1;
    selectedIndex = index;
    notifyListeners();
  }

  NetworkEvent? get selectedEvent {
    final list = visible;
    if (selectedIndex < 0 || selectedIndex >= list.length) return null;
    return list[selectedIndex];
  }

  void _selectFirst() {
    selectedIndex = visible.isEmpty ? -1 : 0;
  }

  List<GroupItem> get groupsView {
    final query = groupSearch.trim().toLowerCase();
    if (query.isEmpty) return groups;
    return groups
        .where((g) =>
            g.kind == GroupKind.all ||
            g.kind == GroupKind.suspicious ||
            g.kind == GroupKind.inbound ||
            g.name.toLowerCase().contains(query))
        .toList();
  }

  List<NetworkEvent> get visible {
    Iterable<NetworkEvent> query = _displayAll;
    switch (viewKind) {
      case GroupKind.suspicious:
        query = query.where((e) => e.isSuspicious);
      case GroupKind.inbound:
        query = query.where((e) => e.direction == Direction.inbound);
      case GroupKind.process:
        query = query.where((e) => e.processName == viewName);
      case GroupKind.domain:
        query = query.where((e) => e.domain == viewName);
      case GroupKind.all:
      case null:
        break;
    }
    query = query.where(_matchesProtocol);
    final text = logSearch.trim().toLowerCase();
    if (text.isNotEmpty) {
      query = query.where((e) => _searchText(e).contains(text));
    }
    final list = query.toList()..sort(_compare);
    return list;
  }

  bool _matchesProtocol(NetworkEvent event) {
    switch (protocolTab) {
      case 'TCP':
        return event.protocol == 'tcp';
      case 'UDP':
        return event.protocol == 'udp';
      case 'DNS':
        return event.protocol == 'dns';
      case 'Suspicious':
        return event.isSuspicious;
      case 'Listening':
        return event.direction == Direction.listening;
      default:
        return true;
    }
  }

  static String _searchText(NetworkEvent e) => [
        e.processName,
        e.processPath,
        e.protocol,
        e.state,
        e.localIp,
        e.remoteIp,
        e.domain,
        e.severity.name,
      ].join(' ').toLowerCase();

  int _compare(NetworkEvent a, NetworkEvent b) {
    int c;
    switch (sortColumn) {
      case SortColumn.process:
        c = a.processDisplay.toLowerCase().compareTo(
              b.processDisplay.toLowerCase(),
            );
      case SortColumn.target:
        c = a.targetDisplay.toLowerCase().compareTo(
              b.targetDisplay.toLowerCase(),
            );
      case SortColumn.protocol:
        c = a.protocol.compareTo(b.protocol);
      case SortColumn.risk:
        c = a.riskScore.compareTo(b.riskScore);
      case SortColumn.time:
        c = a.timestamp.compareTo(b.timestamp);
    }
    if (!sortAscending) c = -c;
    return c != 0 ? c : b.timestamp.compareTo(a.timestamp);
  }

  // ------------------------------------------------------------------
  // Pagination
  // ------------------------------------------------------------------

  int get pageCount {
    final total = visible.length;
    if (total == 0) return 1;
    return ((total - 1) ~/ pageSize) + 1;
  }

  int get _clampedPage {
    final total = visible.length;
    if (total == 0) return 0;
    return pageIndex.clamp(0, ((total - 1) ~/ pageSize));
  }

  int get pageStart => _clampedPage * pageSize;

  List<NetworkEvent> get pageItems {
    final list = visible;
    if (list.isEmpty) return list;
    final start = _clampedPage * pageSize;
    final end = (start + pageSize).clamp(0, list.length);
    return list.sublist(start, end);
  }

  String get pageLabel {
    final total = visible.length;
    if (total == 0) return 'Page 1 of 1';
    return 'Page ${_clampedPage + 1} of $pageCount';
  }

  String get pageRangeLabel {
    final total = visible.length;
    if (total == 0) return '0 of 0';
    final start = pageStart + 1;
    final end = (pageStart + pageSize).clamp(0, total);
    return '$start–$end of $total';
  }

  void setPage(int index) {
    pageIndex = index.clamp(0, pageCount - 1);
    notifyListeners();
  }

  void setPageSize(int size) {
    pageSize = size;
    pageIndex = 0;
    _selectFirst();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Clear
  // ------------------------------------------------------------------

  void clearAll() {
    db.clear();
    all.clear();
    pending.clear();
    _keys.clear();
    viewKind = null;
    viewName = null;
    selectedIndex = -1;
    pageIndex = 0;
    _rebuildDisplay();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _capture.stop();
    db.dispose();
    super.dispose();
  }
}
