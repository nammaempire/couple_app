// The app's document database, backed by the Us server (Postgres).
//
// The API mirrors the Firestore SDK the app used before — collection(),
// doc(), where(), orderBy(), limit(), get(), snapshots(), set(), update(),
// delete(), runTransaction(), batch() — so feature code changes little.
//
// Pure Dart (no Flutter).

import 'dart:async';
import 'dart:math';

import 'package:couple_app/core/backend/values.dart';

export 'package:couple_app/core/backend/values.dart';

/// A document as the backend returns it (data already decoded).
class RawDoc {
  const RawDoc({
    required this.path,
    required this.exists,
    this.data,
    this.version = 0,
  });

  final String path;
  final bool exists;
  final Map<String, dynamic>? data;

  /// Changes on every write; 0 when the document doesn't exist.
  final int version;

  String get id => path.substring(path.lastIndexOf('/') + 1);
}

/// One where-clause.
class QueryFilter {
  const QueryFilter(this.field, this.op, this.value);
  final String field;
  final String op;
  final Object? value;
}

class QueryOrder {
  const QueryOrder(this.field, this.descending);
  final String field;
  final bool descending;
}

/// What a query asks for.
class QuerySpec {
  const QuerySpec({
    required this.collection,
    this.filters = const [],
    this.orders = const [],
    this.limit,
  });

  final String collection;
  final List<QueryFilter> filters;
  final List<QueryOrder> orders;
  final int? limit;

  QuerySpec copyWith({
    List<QueryFilter>? filters,
    List<QueryOrder>? orders,
    int? limit,
  }) => QuerySpec(
    collection: collection,
    filters: filters ?? this.filters,
    orders: orders ?? this.orders,
    limit: limit ?? this.limit,
  );

  Map<String, Object?> toJson() => {
    'collection': collection,
    if (filters.isNotEmpty)
      'where': [
        for (final f in filters) [f.field, f.op, encodeValue(f.value)],
      ],
    if (orders.isNotEmpty)
      'orderBy': [
        for (final o in orders) [o.field, o.descending ? 'desc' : 'asc'],
      ],
    if (limit != null) 'limit': limit,
  };
}

/// One write in a commit.
class WriteOp {
  const WriteOp.set(this.path, this.data, {this.merge = false}) : op = 'set';
  const WriteOp.create(this.path, this.data) : op = 'create', merge = false;
  const WriteOp.update(this.path, this.data) : op = 'update', merge = false;
  const WriteOp.delete(this.path) : op = 'delete', data = null, merge = false;

  final String op;
  final String path;
  final Map<String, Object?>? data;
  final bool merge;

  Map<String, Object?> toJson() => {
    'op': op,
    'path': path,
    if (data != null) 'data': encodeValue(data),
    if (merge) 'merge': true,
  };
}

/// A version observed by a transaction read (0 = missing).
class ReadVersion {
  const ReadVersion(this.path, this.version);
  final String path;
  final int version;
  Map<String, Object?> toJson() => {'path': path, 'version': version};
}

/// Where documents actually live: the Us server, or memory in tests.
abstract class DbBackend {
  Future<List<RawDoc>> getDocs(List<String> paths);
  Future<List<RawDoc>> query(QuerySpec spec);
  Future<int> count(QuerySpec spec);

  /// Applies [writes] atomically. Throws DbException('aborted') when a
  /// document in [reads] changed since it was read.
  Future<void> commit(List<WriteOp> writes, {List<ReadVersion> reads});

  Stream<RawDoc> watchDoc(String path);
  Stream<List<RawDoc>> watchQuery(QuerySpec spec);
}

// ---- Public API ---------------------------------------------------------------

/// Entry point, like FirebaseFirestore.
class Db {
  Db(this.backend);

  final DbBackend backend;

  static Db? _instance;

  /// The app-wide database. Set up by `initBackend()` at startup.
  static Db get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('Db.instance used before initBackend() ran.');
    }
    return i;
  }

  static set instance(Db db) => _instance = db;

  /// Whether [instance] has been set (tests and startup).
  static bool get isInitialized => _instance != null;

  CollectionReference<Map<String, dynamic>> collection(String path) =>
      CollectionReference._(this, _clean(path));

  DocumentReference<Map<String, dynamic>> doc(String path) =>
      DocumentReference._(this, _clean(path));

  WriteBatch batch() => WriteBatch._(this);

  /// Optimistic transaction: reads are versioned, and the commit fails with
  /// 'aborted' if any of them changed; then [handler] runs again.
  Future<T> runTransaction<T>(
    Future<T> Function(Transaction transaction) handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    for (var attempt = 1; ; attempt++) {
      final t = Transaction._(this);
      final result = await handler(t);
      try {
        await backend.commit(t._writes, reads: t._reads.values.toList());
        return result;
      } on DbException catch (e) {
        if (e.code != 'aborted' || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 40 * attempt + Random().nextInt(60)),
        );
      }
    }
  }

  static String _clean(String path) =>
      path.replaceAll(RegExp(r'^/+|/+$'), '');
}

const _autoIdChars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
final _rand = Random.secure();

/// A 20-character random id, like Firestore's auto ids.
String autoId() =>
    String.fromCharCodes(Iterable.generate(
      20,
      (_) => _autoIdChars.codeUnitAt(_rand.nextInt(_autoIdChars.length)),
    ));

class SnapshotMetadata {
  const SnapshotMetadata({
    this.isFromCache = false,
    this.hasPendingWrites = false,
  });
  final bool isFromCache;
  final bool hasPendingWrites;
}

class DocumentSnapshot<T extends Object?> {
  DocumentSnapshot._(this.reference, this._data, this.exists, this.version);

  final DocumentReference<T> reference;
  final Map<String, dynamic>? _data;
  final bool exists;

  /// Server version of this document (0 when missing).
  final int version;

  String get id => reference.id;

  SnapshotMetadata get metadata => const SnapshotMetadata();

  /// The fields, or null when the document doesn't exist.
  T? data() => _data as T?;

  /// One field, using a dotted path for nested maps. Throws if missing,
  /// like Firestore.
  dynamic get(Object field) {
    Object? node = _data;
    for (final seg in field.toString().split('.')) {
      if (node is Map && node.containsKey(seg)) {
        node = node[seg];
      } else {
        throw StateError('Field "$field" does not exist in ${reference.path}');
      }
    }
    return node;
  }

  dynamic operator [](Object field) => get(field);
}

class QueryDocumentSnapshot<T extends Object?> extends DocumentSnapshot<T> {
  QueryDocumentSnapshot._(
    DocumentReference<T> reference,
    Map<String, dynamic> data,
    int version,
  ) : super._(reference, data, true, version);

  @override
  T data() => super.data() as T;
}

class QuerySnapshot<T extends Object?> {
  QuerySnapshot._(this.docs);

  final List<QueryDocumentSnapshot<T>> docs;

  int get size => docs.length;
  bool get isEmpty => docs.isEmpty;
  SnapshotMetadata get metadata => const SnapshotMetadata();
}

class AggregateQuerySnapshot {
  const AggregateQuerySnapshot._(this.count);
  final int? count;
}

class AggregateQuery {
  AggregateQuery._(this._query);
  final Query<Object?> _query;

  Future<AggregateQuerySnapshot> get() async =>
      AggregateQuerySnapshot._(await _query.db.backend.count(_query._spec));
}

/// A query on one collection.
class Query<T extends Object?> {
  Query._(this.db, this._spec);

  final Db db;
  final QuerySpec _spec;

  /// The query as sent to the server (tests and debugging).
  QuerySpec get spec => _spec;

  Query<T> where(
    Object field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    Iterable<Object?>? arrayContainsAny,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
    bool? isNull,
  }) {
    final f = field.toString();
    final added = <QueryFilter>[
      if (isEqualTo != null) QueryFilter(f, '==', isEqualTo),
      if (isNotEqualTo != null) QueryFilter(f, '!=', isNotEqualTo),
      if (isLessThan != null) QueryFilter(f, '<', isLessThan),
      if (isLessThanOrEqualTo != null)
        QueryFilter(f, '<=', isLessThanOrEqualTo),
      if (isGreaterThan != null) QueryFilter(f, '>', isGreaterThan),
      if (isGreaterThanOrEqualTo != null)
        QueryFilter(f, '>=', isGreaterThanOrEqualTo),
      if (arrayContains != null)
        QueryFilter(f, 'array-contains', arrayContains),
      if (arrayContainsAny != null)
        QueryFilter(f, 'array-contains-any', arrayContainsAny.toList()),
      if (whereIn != null) QueryFilter(f, 'in', whereIn.toList()),
      if (whereNotIn != null) QueryFilter(f, 'not-in', whereNotIn.toList()),
      if (isNull == true) QueryFilter(f, '==', null),
      if (isNull == false) QueryFilter(f, '!=', null),
    ];
    if (added.isEmpty) {
      throw ArgumentError('where() needs a condition for "$f".');
    }
    return Query._(db, _spec.copyWith(filters: [..._spec.filters, ...added]));
  }

  Query<T> orderBy(Object field, {bool descending = false}) => Query._(
    db,
    _spec.copyWith(
      orders: [..._spec.orders, QueryOrder(field.toString(), descending)],
    ),
  );

  Query<T> limit(int limit) => Query._(db, _spec.copyWith(limit: limit));

  AggregateQuery count() => AggregateQuery._(this);

  QuerySnapshot<T> _snapshot(List<RawDoc> docs) => QuerySnapshot._([
    for (final d in docs)
      QueryDocumentSnapshot<T>._(
        DocumentReference<T>._(db, d.path),
        d.data ?? <String, dynamic>{},
        d.version,
      ),
  ]);

  Future<QuerySnapshot<T>> get([GetOptions? options]) async =>
      _snapshot(await db.backend.query(_spec));

  /// Live results: the current result first, then again after every change.
  Stream<QuerySnapshot<T>> snapshots({bool includeMetadataChanges = false}) =>
      db.backend.watchQuery(_spec).map(_snapshot);
}

class CollectionReference<T extends Object?> extends Query<T> {
  CollectionReference._(Db db, String path)
    : super._(db, QuerySpec(collection: path));

  String get path => _spec.collection;
  String get id => path.substring(path.lastIndexOf('/') + 1);

  /// The document containing this collection, or null at the top level.
  DocumentReference<Map<String, dynamic>>? get parent {
    final i = path.lastIndexOf('/');
    return i < 0 ? null : DocumentReference._(db, path.substring(0, i));
  }

  /// A document in this collection; a new random id when [id] is omitted.
  DocumentReference<T> doc([String? id]) =>
      DocumentReference<T>._(db, '$path/${id ?? autoId()}');

  /// Creates a document with a random id.
  Future<DocumentReference<T>> add(T data) async {
    final ref = doc();
    await db.backend.commit([
      WriteOp.create(ref.path, data as Map<String, Object?>),
    ]);
    return ref;
  }
}

class DocumentReference<T extends Object?> {
  DocumentReference._(this.db, this.path);

  final Db db;
  final String path;

  String get id => path.substring(path.lastIndexOf('/') + 1);

  CollectionReference<T> get parent =>
      CollectionReference<T>._(db, path.substring(0, path.lastIndexOf('/')));

  CollectionReference<Map<String, dynamic>> collection(String sub) =>
      CollectionReference._(db, '$path/$sub');

  DocumentSnapshot<T> _snapshot(RawDoc d) =>
      DocumentSnapshot<T>._(this, d.exists ? d.data : null, d.exists, d.version);

  Future<DocumentSnapshot<T>> get([GetOptions? options]) async =>
      _snapshot((await db.backend.getDocs([path])).single);

  Stream<DocumentSnapshot<T>> snapshots({
    bool includeMetadataChanges = false,
  }) => db.backend.watchDoc(path).map(_snapshot);

  Future<void> set(T data, [SetOptions? options]) => db.backend.commit([
    WriteOp.set(
      path,
      data as Map<String, Object?>,
      merge: options?.merge ?? false,
    ),
  ]);

  /// Updates fields (dotted paths reach into maps). Fails with not-found
  /// when the document doesn't exist.
  Future<void> update(Map<Object, Object?> data) => db.backend.commit([
    WriteOp.update(path, {for (final e in data.entries) '${e.key}': e.value}),
  ]);

  Future<void> delete() => db.backend.commit([WriteOp.delete(path)]);

  @override
  bool operator ==(Object other) =>
      other is DocumentReference && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'DocumentReference($path)';
}

class WriteBatch {
  WriteBatch._(this._db);

  final Db _db;
  final _writes = <WriteOp>[];

  void set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) =>
      _writes.add(
        WriteOp.set(
          ref.path,
          data as Map<String, Object?>,
          merge: options?.merge ?? false,
        ),
      );

  void update(DocumentReference<Object?> ref, Map<Object, Object?> data) =>
      _writes.add(
        WriteOp.update(ref.path, {
          for (final e in data.entries) '${e.key}': e.value,
        }),
      );

  void delete(DocumentReference<Object?> ref) =>
      _writes.add(WriteOp.delete(ref.path));

  Future<void> commit() async {
    if (_writes.isEmpty) return;
    await _db.backend.commit(List.of(_writes));
  }
}

class Transaction {
  Transaction._(this._db);

  final Db _db;
  final _writes = <WriteOp>[];
  final _reads = <String, ReadVersion>{};

  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> ref,
  ) async {
    if (_writes.isNotEmpty) {
      throw StateError('Transactions must read before they write.');
    }
    final d = (await _db.backend.getDocs([ref.path])).single;
    _reads[ref.path] = ReadVersion(ref.path, d.version);
    return ref._snapshot(d);
  }

  Transaction set<T>(
    DocumentReference<T> ref,
    T data, [
    SetOptions? options,
  ]) {
    _writes.add(
      WriteOp.set(
        ref.path,
        data as Map<String, Object?>,
        merge: options?.merge ?? false,
      ),
    );
    return this;
  }

  Transaction update(
    DocumentReference<Object?> ref,
    Map<Object, Object?> data,
  ) {
    _writes.add(
      WriteOp.update(ref.path, {
        for (final e in data.entries) '${e.key}': e.value,
      }),
    );
    return this;
  }

  Transaction delete(DocumentReference<Object?> ref) {
    _writes.add(WriteOp.delete(ref.path));
    return this;
  }
}
