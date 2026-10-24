// An in-memory DbBackend for tests (replaces fake_cloud_firestore).
// Same write semantics as the server (sentinels, merge, dotted updates,
// versions, transactions); no security rules.
//
// Pure Dart.

import 'dart:async';

import 'package:couple_app/core/backend/db.dart';

class MemoryBackend implements DbBackend {
  final _docs = <String, _Stored>{};
  final _changes = StreamController<Set<String>>.broadcast(sync: true);
  int _version = 0;

  /// Fixed "server time" for tests; null = the real clock.
  DateTime? clock;

  /// Every commit, for assertions in tests.
  final commits = <List<WriteOp>>[];

  /// A snapshot of the stored data (path → fields), for assertions.
  Map<String, Map<String, dynamic>> dump() => {
    for (final e in _docs.entries) e.key: _clone(e.value.data),
  };

  /// Seeds a document directly (no sentinels).
  void seed(String path, Map<String, Object?> data) {
    _docs[path] = _Stored(decodeData(encodeValue(data)), ++_version);
    _changes.add({path});
  }

  RawDoc _raw(String path) {
    final s = _docs[path];
    return RawDoc(
      path: path,
      exists: s != null,
      data: s == null ? null : _clone(s.data),
      version: s?.version ?? 0,
    );
  }

  @override
  Future<List<RawDoc>> getDocs(List<String> paths) async =>
      [for (final p in paths) _raw(p)];

  bool _inCollection(String path, String collection) {
    if (!path.startsWith('$collection/')) return false;
    return !path.substring(collection.length + 1).contains('/');
  }

  List<RawDoc> _run(QuerySpec spec, {bool applyLimit = true}) {
    var rows = [
      for (final p in _docs.keys)
        if (_inCollection(p, spec.collection)) _raw(p),
    ];
    for (final f in spec.filters) {
      rows = rows.where((d) => _matches(d, f)).toList();
    }
    for (final o in spec.orders) {
      rows = rows.where((d) => _field(d, o.field) != _missing).toList();
    }
    rows.sort((a, b) {
      for (final o in spec.orders) {
        final c = _compare(_field(a, o.field), _field(b, o.field));
        if (c != 0) return o.descending ? -c : c;
      }
      final c = a.id.compareTo(b.id);
      return spec.orders.isNotEmpty && spec.orders.last.descending ? -c : c;
    });
    if (applyLimit && spec.limit != null && rows.length > spec.limit!) {
      rows = rows.sublist(0, spec.limit!);
    }
    return rows;
  }

  @override
  Future<List<RawDoc>> query(QuerySpec spec) async => _run(spec);

  @override
  Future<int> count(QuerySpec spec) async => _run(spec).length;

  @override
  Future<void> commit(
    List<WriteOp> writes, {
    List<ReadVersion> reads = const [],
  }) async {
    for (final r in reads) {
      if ((_docs[r.path]?.version ?? 0) != r.version) {
        throw DbException('aborted', 'The document changed. Try again.');
      }
    }
    final now = Timestamp.fromDate(clock ?? DateTime.now());
    final staged = <String, Map<String, dynamic>?>{};
    Map<String, dynamic>? current(String p) =>
        staged.containsKey(p) ? staged[p] : _docs[p]?.data;
    for (final w in writes) {
      final data = w.data == null ? null : _decodeWrite(encodeValue(w.data));
      switch (w.op) {
        case 'delete':
          staged[w.path] = null;
        case 'create':
          if (current(w.path) != null) {
            throw DbException('already-exists', 'Document already exists: ${w.path}');
          }
          staged[w.path] = _applySet(data!, now);
        case 'set':
          staged[w.path] = w.merge
              ? _applyMerge(current(w.path), data!, now)
              : _applySet(data!, now);
        case 'update':
          final cur = current(w.path);
          if (cur == null) {
            throw DbException('not-found', 'No document to update: ${w.path}');
          }
          staged[w.path] = _applyUpdate(cur, data!, now);
      }
    }
    commits.add(List.of(writes));
    for (final e in staged.entries) {
      if (e.value == null) {
        _docs.remove(e.key);
      } else {
        _docs[e.key] = _Stored(e.value!, ++_version);
      }
    }
    if (staged.isNotEmpty) _changes.add(staged.keys.toSet());
  }

  @override
  Stream<RawDoc> watchDoc(String path) {
    late StreamController<RawDoc> c;
    StreamSubscription<Set<String>>? sub;
    c = StreamController<RawDoc>(
      onListen: () {
        scheduleMicrotask(() {
          if (!c.isClosed) c.add(_raw(path));
        });
        sub = _changes.stream.listen((paths) {
          if (paths.contains(path) && !c.isClosed) c.add(_raw(path));
        });
      },
      // Not async: awaiting a cancel can stall under fake async in widget tests.
      onCancel: () {
        unawaited(sub?.cancel());
        unawaited(c.close());
      },
    );
    return c.stream;
  }

  @override
  Stream<List<RawDoc>> watchQuery(QuerySpec spec) {
    late StreamController<List<RawDoc>> c;
    StreamSubscription<Set<String>>? sub;
    c = StreamController<List<RawDoc>>(
      onListen: () {
        scheduleMicrotask(() {
          if (!c.isClosed) c.add(_run(spec));
        });
        sub = _changes.stream.listen((paths) {
          if (paths.any((p) => _inCollection(p, spec.collection)) &&
              !c.isClosed) {
            c.add(_run(spec));
          }
        });
      },
      // Not async: awaiting a cancel can stall under fake async in widget tests.
      onCancel: () {
        unawaited(sub?.cancel());
        unawaited(c.close());
      },
    );
    return c.stream;
  }
}

class _Stored {
  _Stored(this.data, this.version);
  final Map<String, dynamic> data;
  final int version;
}

const _missing = Object();

Object? _field(RawDoc d, String field) {
  if (field == '__name__' || field == 'id') return d.id;
  Object? node = d.data;
  for (final seg in field.split('.')) {
    if (node is Map && node.containsKey(seg)) {
      node = node[seg];
    } else {
      return _missing;
    }
  }
  return node;
}

bool _eq(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_eq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_eq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num) return a == b;
  return a == b;
}

int _typeRank(Object? v) => switch (v) {
  null => 0,
  bool _ => 1,
  num _ => 2,
  Timestamp _ => 3,
  String _ => 4,
  List<dynamic> _ => 5,
  _ => 6,
};

int _compare(Object? a, Object? b) {
  final ra = _typeRank(a), rb = _typeRank(b);
  if (ra != rb) return ra.compareTo(rb);
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  if (a is num && b is num) return a.compareTo(b);
  if (a is Timestamp && b is Timestamp) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  return 0;
}

bool _matches(RawDoc d, QueryFilter f) {
  final v = _field(d, f.field);
  final want = decodeValue(encodeValue(f.value));
  if (v == _missing) return false;
  switch (f.op) {
    case '==':
      return _eq(v, want);
    case '!=':
      return !_eq(v, want);
    case '<':
    case '<=':
    case '>':
    case '>=':
      if (_typeRank(v) != _typeRank(want)) return false;
      final c = _compare(v, want);
      return switch (f.op) {
        '<' => c < 0,
        '<=' => c <= 0,
        '>' => c > 0,
        _ => c >= 0,
      };
    case 'in':
      return (want! as List).any((x) => _eq(v, x));
    case 'not-in':
      return !(want! as List).any((x) => _eq(v, x));
    case 'array-contains':
      return v is List && v.any((x) => _eq(x, want));
    case 'array-contains-any':
      return v is List && (want! as List).any((w) => v.any((x) => _eq(x, w)));
  }
  return false;
}

// ---- Write semantics (mirror of the server's values.ts) -------------------

/// Decodes a write's JSON, keeping sentinels as `{"$sv": …}` maps.
Map<String, dynamic> _decodeWrite(Object? json) {
  Object? walk(Object? v) {
    if (v is Map) {
      if (v.containsKey(r'$sv')) {
        return <String, dynamic>{
          for (final e in v.entries)
            e.key as String: e.key == 'values' ? decodeValue(e.value) : e.value,
        };
      }
      if (v.length == 1 && v[r'$ts'] is String) return decodeValue(v);
      return <String, dynamic>{
        for (final e in v.entries) e.key as String: walk(e.value),
      };
    }
    if (v is List) return [for (final x in v) decodeValue(x)];
    return v;
  }

  return walk(json)! as Map<String, dynamic>;
}

bool _isSentinel(Object? v) => v is Map && v.containsKey(r'$sv');

const _deleteMarker = Object();

Object? _resolve(Map<dynamic, dynamic> s, Object? old, Timestamp now) {
  switch (s[r'$sv']) {
    case 'serverTimestamp':
      return now;
    case 'delete':
      return _deleteMarker;
    case 'increment':
      return (old is num ? old : 0) + (s['by'] as num);
    case 'arrayUnion':
      final out = old is List ? List<dynamic>.of(old) : <dynamic>[];
      for (final x in s['values'] as List) {
        if (!out.any((y) => _eq(x, y))) out.add(x);
      }
      return out;
    case 'arrayRemove':
      final vals = s['values'] as List;
      return [
        for (final y in old is List ? old : const <dynamic>[])
          if (!vals.any((x) => _eq(x, y))) y,
      ];
  }
  throw ArgumentError('Unknown sentinel ${s[r'$sv']}');
}

Object? _resolveAll(Object? v, Timestamp now) {
  if (_isSentinel(v)) return _resolve(v! as Map, null, now);
  if (v is Map<String, dynamic>) {
    final out = <String, dynamic>{};
    for (final e in v.entries) {
      final r = _resolveAll(e.value, now);
      if (!identical(r, _deleteMarker)) out[e.key] = r;
    }
    return out;
  }
  return v;
}

Map<String, dynamic> _applySet(Map<String, dynamic> data, Timestamp now) =>
    _resolveAll(data, now)! as Map<String, dynamic>;

Map<String, dynamic> _applyMerge(
  Map<String, dynamic>? old,
  Map<String, dynamic> data,
  Timestamp now,
) {
  final out = old == null ? <String, dynamic>{} : _clone(old);
  void mergeInto(Map<String, dynamic> target, Map<String, dynamic> patch) {
    for (final e in patch.entries) {
      final v = e.value;
      if (_isSentinel(v)) {
        final r = _resolve(v as Map, target[e.key], now);
        if (identical(r, _deleteMarker)) {
          target.remove(e.key);
        } else {
          target[e.key] = r;
        }
      } else if (v is Map<String, dynamic>) {
        final cur = target[e.key];
        final next = cur is Map<String, dynamic> ? cur : <String, dynamic>{};
        mergeInto(next, v);
        target[e.key] = next;
      } else {
        target[e.key] = v;
      }
    }
  }

  mergeInto(out, data);
  return out;
}

Map<String, dynamic> _applyUpdate(
  Map<String, dynamic> old,
  Map<String, dynamic> fields,
  Timestamp now,
) {
  final out = _clone(old);
  for (final e in fields.entries) {
    final segs = e.key.split('.');
    var node = out;
    for (final s in segs.take(segs.length - 1)) {
      final cur = node[s];
      if (cur is! Map<String, dynamic>) node[s] = <String, dynamic>{};
      node = node[s] as Map<String, dynamic>;
    }
    final last = segs.last;
    final r = _isSentinel(e.value)
        ? _resolve(e.value as Map, node[last], now)
        : _resolveAll(e.value, now);
    if (identical(r, _deleteMarker)) {
      node.remove(last);
    } else {
      node[last] = r;
    }
  }
  return out;
}

Map<String, dynamic> _clone(Map<String, dynamic> m) =>
    decodeData(encodeValue(m));
