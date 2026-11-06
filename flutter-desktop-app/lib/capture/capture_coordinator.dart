/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:async';
import 'dart:io';

import '../models.dart';
import 'capture_service.dart';
import 'etw_service.dart';

enum CaptureMode { etw, polling, stopped }

/// Prefers realtime ETW capture and silently falls back to polling when the
/// helper is missing, elevation is declined, or the helper disconnects.
class CaptureCoordinator {
  CaptureCoordinator({
    required this.onEvents,
    required this.onModeChanged,
    required this.interval,
  });

  final void Function(List<NetworkEvent> events) onEvents;
  final void Function(CaptureMode mode, String detail) onModeChanged;
  final Duration interval;

  EtwCaptureService? _etw;
  CaptureService? _polling;
  CaptureMode _mode = CaptureMode.stopped;
  bool _running = false;
  bool _fallingBack = false;

  CaptureMode get mode => _mode;
  bool get isRunning => _running && _mode != CaptureMode.stopped;

  Future<void> start() async {
    if (_running) return;
    _running = true;

    final disabled = Platform.environment['NETSCOPE_DISABLE_ETW'] == '1';
    if (!disabled) {
      final etw = EtwCaptureService(
        onEvents: onEvents,
        onDisconnected: _onEtwDisconnected,
      );
      var started = false;
      try {
        started = await etw.start();
      } catch (_) {
        started = false;
      }
      if (started && _running) {
        _etw = etw;
        _setMode(CaptureMode.etw, 'etw');
        return;
      }
      await etw.stop();
    }

    await _startPolling();
  }

  Future<void> stop() async {
    _running = false;
    await _etw?.stop();
    _etw = null;
    await _polling?.stop();
    _polling = null;
    _setMode(CaptureMode.stopped, 'stopped');
  }

  Future<void> restartPolling() async {
    if (!_running || _mode != CaptureMode.polling) return;
    await _polling?.stop();
    _polling = null;
    await _startPolling();
  }

  Future<void> _startPolling() async {
    if (!_running) return;
    final polling = CaptureService(onEvents: onEvents, interval: interval);
    await polling.start();
    _polling = polling;
    _setMode(CaptureMode.polling, 'polling');
  }

  void _onEtwDisconnected() {
    if (!_running || _mode != CaptureMode.etw || _fallingBack) return;
    _fallingBack = true;
    unawaited(() async {
      await _etw?.stop();
      _etw = null;
      if (_running) await _startPolling();
      _fallingBack = false;
    }());
  }

  void _setMode(CaptureMode mode, String detail) {
    _mode = mode;
    onModeChanged(mode, detail);
  }
}
