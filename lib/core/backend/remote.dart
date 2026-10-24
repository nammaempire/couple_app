// Talks to the Us server: JSON over HTTPS, and one WebSocket for live updates.
//
// Pure Dart (dart:io + package:http), no Flutter.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'package:couple_app/core/backend/db.dart';

/// Gets the signed-in user's Firebase ID token (null when signed out).
typedef TokenProvider = Future<String?> Function({bool forceRefresh});

/// HTTP calls to the Us server with the Firebase ID token attached.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.token,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

  /// e.g. https://us-server-production.up.railway.app (no trailing slash).
  final String baseUrl;
  final TokenProvider token;
  final Duration timeout;
  final http.Client _http;

  Uri uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, String>> authHeaders({bool forceRefresh = false}) async {
    final t = await token(forceRefresh: forceRefresh);
    return {if (t != null) 'authorization': 'Bearer $t'};
  }

  /// POSTs JSON and returns the decoded JSON body. Retries once with a
  /// fresh token on 401.
  Future<Map<String, dynamic>> post(String path, Object? body) async {
    for (var attempt = 0; ; attempt++) {
      final http.Response res;
      try {
        res = await _http
            .post(
              uri(path),
              headers: {
                'content-type': 'application/json',
                ...await authHeaders(forceRefresh: attempt > 0),
              },
              body: jsonEncode(body),
            )
            .timeout(timeout);
      } on TimeoutException {
        throw DbException('unavailable', 'The server took too long to answer.');
      } on SocketException catch (e) {
        throw DbException('unavailable', 'No connection to the server. ${e.message}');
      } on http.ClientException catch (e) {
        throw DbException('unavailable', 'No connection to the server. ${e.message}');
      }
      if (res.statusCode == 401 && attempt == 0) continue;
      return decodeResponse(res.statusCode, res.body);
    }
  }

  /// Turns a server reply into JSON, or throws its error as a [DbException].
  static Map<String, dynamic> decodeResponse(int status, String body) {
    Object? json;
    try {
      json = body.isEmpty ? null : jsonDecode(body);
    } catch (_) {
      json = null;
    }
    if (status >= 200 && status < 300 && json is Map<String, dynamic>) {
      return json;
    }
    final err = json is Map ? json['error'] : null;
    if (err is Map) {
      throw DbException(
        '${err['code'] ?? 'internal'}',
        err['message'] as String?,
        err['details'],
      );
    }
    throw DbException(
      status >= 500 ? 'unavailable' : 'internal',
      'Unexpected server reply ($status).',
    );
  }

  void close() => _http.close();
}

RawDoc _rawDoc(Object? json) {
  final m = json! as Map<String, dynamic>;
  return RawDoc(
    path: m['path'] as String,
    exists: m['exists'] == true,
    data: m['exists'] == true ? decodeData(m['data']) : null,
    version: (m['version'] as num?)?.toInt() ?? 0,
  );
}

/// [DbBackend] on the Us server.
class RemoteBackend implements DbBackend {
  RemoteBackend(this.api, {Realtime? realtime})
    : realtime = realtime ?? Realtime(api);

  final ApiClient api;
  final Realtime realtime;

  @override
  Future<List<RawDoc>> getDocs(List<String> paths) async {
    final res = await api.post('/v1/db/get', {'paths': paths});
    return [for (final d in res['docs'] as List) _rawDoc(d)];
  }

  @override
  Future<List<RawDoc>> query(QuerySpec spec) async {
    final res = await api.post('/v1/db/query', spec.toJson());
    return [for (final d in res['docs'] as List) _rawDoc(d)];
  }

  @override
  Future<int> count(QuerySpec spec) async {
    final res = await api.post('/v1/db/count', spec.toJson());
    return (res['count'] as num).toInt();
  }

  @override
  Future<void> commit(
    List<WriteOp> writes, {
    List<ReadVersion> reads = const [],
  }) async {
    if (writes.isEmpty && reads.isEmpty) return;
    await api.post('/v1/db/commit', {
      'writes': [for (final w in writes) w.toJson()],
      if (reads.isNotEmpty) 'reads': [for (final r in reads) r.toJson()],
    });
  }

  @override
  Stream<RawDoc> watchDoc(String path) => realtime
      .subscribe({'doc': path})
      .map((m) => _rawDoc(m['doc']));

  @override
  Stream<List<RawDoc>> watchQuery(QuerySpec spec) => realtime
      .subscribe({'query': spec.toJson()})
      .map((m) => [for (final d in m['docs'] as List) _rawDoc(d)]);
}

/// One shared WebSocket carrying every live listener.
///
/// Reconnects with backoff, re-sends the token when it refreshes or the
/// server asks, and re-subscribes everything after a reconnect.
class Realtime {
  Realtime(this.api);

  final ApiClient api;

  WebSocket? _socket;
  bool _connecting = false;
  bool _ready = false;
  int _failures = 0;
  Timer? _retry;
  int _nextId = 0;
  final _subs = <String, _Sub>{};

  Stream<Map<String, dynamic>> subscribe(Map<String, Object?> target) {
    late final _Sub sub;
    final controller = StreamController<Map<String, dynamic>>(
      onListen: () {
        _subs[sub.id] = sub;
        _ensureConnected();
        if (_ready) _send({'t': 'sub', 'id': sub.id, ...target});
      },
      onCancel: () {
        _subs.remove(sub.id);
        if (_ready) _send({'t': 'unsub', 'id': sub.id});
        if (_subs.isEmpty) _scheduleIdleClose();
        unawaited(sub.controller.close());
      },
    );
    sub = _Sub('${_nextId++}', target, controller);
    return controller.stream;
  }

  /// Sends a fresh token (call when the Firebase ID token changes).
  Future<void> reauthenticate() async {
    if (_socket == null) return;
    final t = await api.token(forceRefresh: false);
    if (t != null) _send({'t': 'auth', 'token': t});
  }

  Timer? _idle;
  void _scheduleIdleClose() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 30), () {
      if (_subs.isEmpty) {
        _socket?.close();
        _socket = null;
        _ready = false;
      }
    });
  }

  void _send(Map<String, Object?> msg) {
    final s = _socket;
    if (s != null && s.readyState == WebSocket.open) s.add(jsonEncode(msg));
  }

  Future<void> _ensureConnected() async {
    _idle?.cancel();
    if (_socket != null || _connecting) return;
    _connecting = true;
    try {
      final wsUrl = api.baseUrl.replaceFirst(RegExp('^http'), 'ws');
      final socket = await WebSocket.connect(
        '$wsUrl/v1/realtime',
      ).timeout(const Duration(seconds: 15));
      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      _failures = 0;
      socket.listen(
        _onMessage,
        onDone: () => _onClosed(socket),
        onError: (Object _) => _onClosed(socket),
        cancelOnError: true,
      );
      final t = await api.token(forceRefresh: false);
      if (t == null) {
        for (final s in _subs.values) {
          s.controller.addError(DbException('unauthenticated', 'Sign in first.'));
        }
        return;
      }
      _send({'t': 'auth', 'token': t});
    } catch (_) {
      _socket = null;
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _onClosed(WebSocket socket) {
    if (_socket != socket) return;
    _socket = null;
    _ready = false;
    if (_subs.isNotEmpty) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _retry?.cancel();
    _failures++;
    final ms = min(30000, 500 * pow(2, min(_failures, 6)).toInt()) +
        Random().nextInt(500);
    _retry = Timer(Duration(milliseconds: ms), () {
      if (_subs.isNotEmpty) _ensureConnected();
    });
  }

  Future<void> _onMessage(dynamic raw) async {
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['t']) {
      case 'ready':
        final first = !_ready;
        _ready = true;
        if (first) {
          for (final s in _subs.values) {
            _send({'t': 'sub', 'id': s.id, ...s.target});
          }
        }
      case 'snap':
        final s = _subs[msg['id']];
        if (s != null && !s.controller.isClosed) s.controller.add(msg);
      case 'error':
        final id = msg['id'];
        final e = DbException(
          '${msg['code'] ?? 'internal'}',
          msg['message'] as String?,
        );
        if (id == null) {
          if (e.code == 'unauthenticated') {
            final t = await api.token(forceRefresh: true);
            if (t != null) _send({'t': 'auth', 'token': t});
          }
          return;
        }
        final s = _subs[id];
        if (s != null && !s.controller.isClosed) s.controller.addError(e);
      case 'authExpired':
        final t = await api.token(forceRefresh: true);
        if (t != null) _send({'t': 'auth', 'token': t});
    }
  }

  Future<void> close() async {
    _retry?.cancel();
    _idle?.cancel();
    await _socket?.close();
    _socket = null;
    _ready = false;
  }
}

class _Sub {
  _Sub(this.id, this.target, this.controller);
  final String id;
  final Map<String, Object?> target;
  final StreamController<Map<String, dynamic>> controller;
}
