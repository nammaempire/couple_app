// Files in the Us server's bucket, with an API shaped like Firebase Storage:
// Files.instance.ref(path).putFile(file) … getDownloadURL() … delete().
//
// Uploads stream through the server, which checks the storage rules.
// Download URLs are signed links served by the server.
//
// Pure Dart (dart:io + package:http), no Flutter.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:couple_app/core/backend/remote.dart';
import 'package:couple_app/core/backend/values.dart';

/// Content type and custom metadata for an upload (was SettableMetadata).
class FileMetadata {
  const FileMetadata({this.contentType, this.customMetadata});
  final String? contentType;
  final Map<String, String>? customMetadata;
}

/// Kept so existing call sites read the same.
typedef SettableMetadata = FileMetadata;

enum TaskState { running, success, error }

class TaskSnapshot {
  const TaskSnapshot(this.ref, this.bytesTransferred, this.totalBytes, this.state);
  final FileRef ref;
  final int bytesTransferred;
  final int totalBytes;
  final TaskState state;
}

/// An upload in progress: await it, or listen to [snapshotEvents] for progress.
class UploadTask implements Future<TaskSnapshot> {
  UploadTask._(this._future, this.snapshotEvents);

  final Future<TaskSnapshot> _future;

  /// Progress events while the bytes are sent (broadcast).
  final Stream<TaskSnapshot> snapshotEvents;

  @override
  Stream<TaskSnapshot> asStream() => _future.asStream();

  @override
  Future<TaskSnapshot> catchError(Function onError, {bool Function(Object error)? test}) =>
      _future.catchError(onError, test: test);

  @override
  Future<R> then<R>(FutureOr<R> Function(TaskSnapshot value) onValue, {Function? onError}) =>
      _future.then(onValue, onError: onError);

  @override
  Future<TaskSnapshot> timeout(Duration timeLimit, {FutureOr<TaskSnapshot> Function()? onTimeout}) =>
      _future.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<TaskSnapshot> whenComplete(FutureOr<void> Function() action) =>
      _future.whenComplete(action);
}

/// File storage on the Us server.
class Files {
  Files(this.api, {http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final ApiClient api;
  final http.Client _http;

  static Files? _instance;
  static Files get instance {
    final i = _instance;
    if (i == null) throw StateError('Files.instance used before initBackend() ran.');
    return i;
  }

  static set instance(Files f) => _instance = f;

  FileRef ref([String path = '']) => FileRef._(this, path.replaceAll(RegExp(r'^/+|/+$'), ''));

  /// The file behind a download URL this server handed out.
  FileRef refFromURL(String url) {
    final u = Uri.parse(url);
    final segs = u.pathSegments;
    if (segs.length < 2 || segs.first != 'f') {
      throw DbException('invalid-argument', 'Not a file link from this app: $url');
    }
    return ref(segs.skip(1).join('/'));
  }
}

class FileRef {
  FileRef._(this._files, this.fullPath);

  final Files _files;
  final String fullPath;

  String get name => fullPath.substring(fullPath.lastIndexOf('/') + 1);

  FileRef child(String path) =>
      _files.ref(fullPath.isEmpty ? path : '$fullPath/$path');

  FileRef? get parent {
    final i = fullPath.lastIndexOf('/');
    return i < 0 ? null : _files.ref(fullPath.substring(0, i));
  }

  String get _encodedPath => fullPath.split('/').map(Uri.encodeComponent).join('/');

  String? _downloadUrl;

  UploadTask putFile(File file, [FileMetadata? metadata]) =>
      _upload(() async => (await file.length(), file.openRead()), metadata);

  UploadTask putData(Uint8List data, [FileMetadata? metadata]) =>
      _upload(() async => (data.length, Stream.value(data as List<int>)), metadata);

  UploadTask _upload(
    Future<(int, Stream<List<int>>)> Function() open,
    FileMetadata? metadata,
  ) {
    final events = StreamController<TaskSnapshot>.broadcast();
    Future<TaskSnapshot> run() async {
      final (size, source) = await open();
      for (var attempt = 0; ; attempt++) {
        final req = http.StreamedRequest('PUT', _files.api.uri('/v1/files/$_encodedPath'));
        req.contentLength = size;
        req.headers.addAll(await _files.api.authHeaders(forceRefresh: attempt > 0));
        req.headers['content-type'] = metadata?.contentType ?? 'application/octet-stream';
        final custom = metadata?.customMetadata;
        if (custom != null && custom.isNotEmpty) {
          req.headers['x-file-metadata'] =
              base64Url.encode(utf8.encode(jsonEncode(custom))).replaceAll('=', '');
        }
        var sent = 0;
        // Each attempt needs its own copy of the bytes.
        final body = attempt == 0 ? source : (await open()).$2;
        unawaited(() async {
          try {
            await for (final chunk in body) {
              req.sink.add(chunk);
              sent += chunk.length;
              events.add(TaskSnapshot(this, sent, size, TaskState.running));
            }
          } finally {
            await req.sink.close();
          }
        }());
        final http.StreamedResponse res;
        try {
          res = await _files._http.send(req);
        } on SocketException catch (e) {
          throw DbException('unavailable', 'Upload failed: no connection. ${e.message}');
        } on http.ClientException catch (e) {
          throw DbException('unavailable', 'Upload failed: ${e.message}');
        }
        final text = await res.stream.bytesToString();
        if (res.statusCode == 401 && attempt == 0) continue;
        final json = ApiClient.decodeResponse(res.statusCode, text);
        _downloadUrl = json['downloadUrl'] as String?;
        final done = TaskSnapshot(this, size, size, TaskState.success);
        events.add(done);
        return done;
      }
    }

    final future = run().whenComplete(events.close);
    // Errors surface through the future; don't also throw on the stream.
    return UploadTask._(future, events.stream);
  }

  Future<String> getDownloadURL() async {
    final cached = _downloadUrl;
    if (cached != null) return cached;
    final res = await _files.api.post('/v1/files/url', {'path': fullPath});
    return _downloadUrl = res['downloadUrl'] as String;
  }

  /// Downloads the file into memory. Throws DbException('out-of-range')
  /// when it is larger than [maxSize] bytes, and 'not-found' when missing.
  Future<Uint8List> getData([int maxSize = 10 * 1024 * 1024]) async {
    final url = await getDownloadURL();
    final req = http.Request('GET', Uri.parse(url));
    final http.StreamedResponse res;
    try {
      res = await _files._http.send(req);
    } on SocketException catch (e) {
      throw DbException('unavailable', 'No connection to the server. ${e.message}');
    } on http.ClientException catch (e) {
      throw DbException('unavailable', 'Download failed: ${e.message}');
    }
    if (res.statusCode == 404) throw DbException('not-found', 'No such file.');
    if (res.statusCode != 200) {
      throw DbException('unavailable', 'Download failed (${res.statusCode}).');
    }
    final len = res.contentLength;
    if (len != null && len > maxSize) {
      throw DbException('out-of-range', 'File is larger than $maxSize bytes.');
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
      out.add(chunk);
      if (out.length > maxSize) {
        throw DbException('out-of-range', 'File is larger than $maxSize bytes.');
      }
    }
    return out.takeBytes();
  }

  Future<void> delete() async {
    final req = http.Request('DELETE', _files.api.uri('/v1/files/$_encodedPath'));
    req.headers.addAll(await _files.api.authHeaders());
    final http.StreamedResponse res;
    try {
      res = await _files._http.send(req);
    } on SocketException catch (e) {
      throw DbException('unavailable', 'No connection to the server. ${e.message}');
    }
    ApiClient.decodeResponse(res.statusCode, await res.stream.bytesToString());
    _downloadUrl = null;
  }

  @override
  String toString() => 'FileRef($fullPath)';
}
