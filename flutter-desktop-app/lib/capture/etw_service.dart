/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models.dart';
import 'helper_locator.dart';

/// Phase 2 capture source: talks to `netscope-capture.exe` over loopback TCP.
///
/// The helper raises UAC itself and streams NDJSON. Each line is normalized to
/// a [NetworkEvent]. If the helper cannot start, [start] returns false and the
/// coordinator falls back to polling.
class EtwCaptureService {
  EtwCaptureService({
    required this.onEvents,
    this.onDisconnected,
    this.helperPath,
  });

  final void Function(List<NetworkEvent> events) onEvents;
  final void Function()? onDisconnected;
  final String? helperPath;

  ServerSocket? _server;
  Socket? _socket;
  Process? _process;
  StreamSubscription<String>? _subscription;
  Timer? _flushTimer;
  final List<NetworkEvent> _buffer = <NetworkEvent>[];
  bool _running = false;

  bool get isRunning => _running;

  Future<bool> start({Duration timeout = const Duration(seconds: 10)}) async {
    if (_running) return true;

    final helper = helperPath ?? findCaptureHelper();
    if (helper == null || !File(helper).existsSync()) return false;

    final token = _randomToken();
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    } catch (_) {
      return false;
    }

    try {
      _process = await Process.start(helper, <String>[
        '--port',
        '${_server!.port}',
        '--token',
        token,
      ]);
    } catch (_) {
      await _server?.close();
      _server = null;
      return false;
    }

    final connection = Completer<Socket?>();
    _server!.first.then((value) {
      if (!connection.isCompleted) connection.complete(value);
    });
    _process!.exitCode.then((code) {
      // A non-zero exit means elevation was declined or startup failed.
      // Exit code 0 is expected when the launcher spawned the elevated copy.
      if (code != 0 && !connection.isCompleted) connection.complete(null);
    });

    Socket? socket;
    try {
      socket = await connection.future.timeout(timeout);
    } on TimeoutException {
      await _cleanup();
      return false;
    } catch (_) {
      await _cleanup();
      return false;
    }
    if (socket == null) {
      await _cleanup();
      return false;
    }

    await _server?.close();
    _server = null;
    _socket = socket;
    socket.setOption(SocketOption.tcpNoDelay, true);

    final lines = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final ready = Completer<bool>();
    var helloSeen = false;

    _subscription = lines.listen(
      (line) {
        if (!helloSeen) {
          helloSeen = true;
          try {
            final decoded = jsonDecode(line);
            if (decoded is Map &&
                decoded['kind'] == 'hello' &&
                decoded['token'] == token) {
              _running = true;
              ready.complete(true);
              return;
            }
          } catch (_) {}
          ready.complete(false);
          _cleanup();
          return;
        }
        _handleLine(line);
      },
      onError: (_) {
        if (!ready.isCompleted) ready.complete(false);
        _handleDisconnect();
      },
      onDone: () {
        if (!ready.isCompleted) ready.complete(false);
        _handleDisconnect();
      },
      cancelOnError: true,
    );

    return ready.future.timeout(
      timeout,
      onTimeout: () {
        _cleanup();
        return false;
      },
    );
  }

  Future<void> stop() async {
    await _cleanup();
  }

  void _handleLine(String line) {
    final text = line.trim();
    if (text.isEmpty) return;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final event = eventFromJson(Map<String, dynamic>.from(decoded));
      if (event == null) return;
      _buffer.add(event);
      _scheduleFlush();
    } catch (_) {
      // Ignore malformed lines; the helper is the only writer.
    }
  }

  /// Maps one helper NDJSON object to a [NetworkEvent]. Public for tests.
  NetworkEvent? eventFromJson(Map<String, dynamic> json) {
    final kind = '${json['kind'] ?? ''}';
    final timestamp = '${json['ts'] ?? ''}';
    final pid = (json['pid'] as num?)?.toInt() ?? 0;
    final process = '${json['process'] ?? json['processName'] ?? ''}';
    final processPath = '${json['processPath'] ?? ''}';

    if (kind == 'dns') {
      final query = '${json['query'] ?? json['domain'] ?? ''}';
      final answers = json['answers'];
      var answer = '${json['remoteIp'] ?? ''}';
      if (answer.isEmpty && answers is List && answers.isNotEmpty) {
        answer = '${answers.first}';
      }
      if (query.isEmpty) return null;
      return NetworkEvent(
        id: '${json['id'] ?? 'dns-$pid-$query-$answer'}',
        timestamp: timestamp,
        direction: Direction.outbound,
        pid: pid,
        processName: process,
        processPath: processPath,
        protocol: 'dns',
        state: '${json['status'] ?? 'resolved'}',
        remoteIp: answer,
        remotePort: 53,
        domain: query,
      );
    }

    if (kind != 'flow') return null;

    final remoteIp = '${json['remoteIp'] ?? ''}';
    final remotePort = (json['remotePort'] as num?)?.toInt() ?? 0;
    final direction = Direction.values.firstWhere(
      (value) => value.name == json['direction'],
      orElse: () => Direction.outbound,
    );

    return NetworkEvent(
      id: '${json['id'] ?? 'etw-$pid-$timestamp-$remoteIp:$remotePort'}',
      timestamp: timestamp,
      direction: direction,
      pid: pid,
      processName: process,
      processPath: processPath,
      protocol: '${json['protocol'] ?? 'tcp'}',
      state: '${json['state'] ?? ''}',
      localIp: '${json['localIp'] ?? ''}',
      localPort: (json['localPort'] as num?)?.toInt() ?? 0,
      remoteIp: remoteIp,
      remotePort: remotePort,
      domain: '${json['domain'] ?? ''}',
      bytesSent: (json['bytesSent'] as num?)?.toInt() ?? 0,
      bytesReceived: (json['bytesReceived'] as num?)?.toInt() ?? 0,
    );
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: 100), _flush);
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;
    final events = List<NetworkEvent>.of(_buffer);
    _buffer.clear();
    onEvents(events);
  }

  void _handleDisconnect() {
    if (!_running) return;
    _running = false;
    _flush();
    onDisconnected?.call();
  }

  Future<void> _cleanup() async {
    _running = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _buffer.clear();
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _process?.kill();
    _process = null;
    await _server?.close();
    _server = null;
  }

  static String _randomToken() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
