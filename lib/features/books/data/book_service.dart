import 'dart:io';
import 'dart:typed_data';

import 'package:couple_app/core/backend/backend.dart';
import 'package:http/http.dart' as http;

import 'package:couple_app/features/books/models/book.dart';

/// Thrown when a book can't be made or saved, with words for the screen.
class BookException implements Exception {
  BookException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where book PDFs live. Behind an interface so tests can fake it.
abstract class BookFileStore {
  Future<void> upload(String path, Uint8List bytes);
  Future<Uint8List> read(String path);
  Future<void> delete(String path);
}

/// [BookFileStore] in the Us server's file store (`application/pdf`, < 50 MB).
class StorageBookFileStore implements BookFileStore {
  StorageBookFileStore([Files? files, http.Client? httpClient])
    : _given = files,
      _http = httpClient;

  final Files? _given;
  final http.Client? _http;
  Files get _storage => _given ?? Files.instance;

  static const maxBytes = 50 * 1024 * 1024;

  @override
  Future<void> upload(String path, Uint8List bytes) async {
    if (bytes.length >= maxBytes) {
      throw BookException('This book is too big to save. Try a shorter range.');
    }
    await _storage
        .ref(path)
        .putData(bytes, SettableMetadata(contentType: 'application/pdf'));
  }

  @override
  Future<Uint8List> read(String path) async {
    return _downloadBytes(_storage.ref(path), maxBytes, httpClient: _http);
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _storage.ref(path).delete();
    } on DbException catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }
}

/// Downloads [ref] into memory (was Firebase Storage's `getData`): asks the
/// server for its download link, which checks the storage rules, then reads
/// the bytes. Fails if the file is larger than [maxBytes].
Future<Uint8List> _downloadBytes(
  FileRef ref,
  int maxBytes, {
  http.Client? httpClient,
}) async {
  final url = await ref.getDownloadURL();
  final client = httpClient ?? http.Client();
  try {
    final http.StreamedResponse res;
    try {
      res = await client.send(http.Request('GET', Uri.parse(url)));
    } on SocketException catch (e) {
      throw DbException(
        'unavailable',
        'Download failed: no connection. ${e.message}',
      );
    } on http.ClientException catch (e) {
      throw DbException('unavailable', 'Download failed: ${e.message}');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      ApiClient.decodeResponse(
        res.statusCode,
        await res.stream.bytesToString(),
      );
    }
    final out = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
      out.add(chunk);
      if (out.length > maxBytes) {
        throw DbException(
          'out-of-range',
          'File is larger than $maxBytes bytes.',
        );
      }
    }
    return out.takeBytes();
  } finally {
    if (httpClient == null) client.close();
  }
}

/// The couple's memory books: `couples/{cid}/books`, their PDFs, and the
/// book credits that pay for them.
///
/// A credit is spent only by [saveBook]'s final batch, after the PDF is
/// uploaded: `bookCredits` goes down by exactly one in the same batch that
/// creates the book document, as the rules require.
class BookService {
  BookService({Db? db, BookFileStore? files})
    : _db = db ?? Db.instance,
      _files = files ?? StorageBookFileStore();

  final Db _db;
  final BookFileStore _files;

  DocumentReference<Map<String, dynamic>> _couple(String coupleId) =>
      _db.collection('couples').doc(coupleId);

  CollectionReference<Map<String, dynamic>> _books(String coupleId) =>
      _couple(coupleId).collection('books');

  /// Newest first.
  Stream<List<MemoryBook>> watchBooks(String coupleId) =>
      _books(coupleId).snapshots().map((snap) {
        final epoch = DateTime.fromMillisecondsSinceEpoch(0);
        return snap.docs.map(MemoryBook.fromDoc).toList()..sort(
          (a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch),
        );
      });

  /// A fresh id for a book about to be made.
  String newBookId(String coupleId) => _books(coupleId).doc().id;

  /// Uploads the finished PDF. Spends nothing; safe to retry.
  Future<void> uploadPdf({
    required String coupleId,
    required String bookId,
    required Uint8List bytes,
  }) => _files.upload(MemoryBook.pathFor(coupleId, bookId), bytes);

  /// Spends one credit and records the (already uploaded) book, in one
  /// batch.
  Future<void> saveBook({
    required String coupleId,
    required String bookId,
    required String uid,
    required String title,
    required DateTime fromDate,
    required DateTime toDate,
    required int pageCount,
    required int creditsBefore,
  }) async {
    if (creditsBefore < 1) {
      throw BookException('You need a Memory book to make this one.');
    }
    final batch = _db.batch();
    batch.update(_couple(coupleId), {'bookCredits': FieldValue.increment(-1)});
    batch.set(_books(coupleId).doc(bookId), {
      'createdBy': uid,
      'title': cleanTitle(title),
      'fromDate': Timestamp.fromDate(fromDate),
      'toDate': Timestamp.fromDate(toDate),
      'pageCount': pageCount,
      'storagePath': MemoryBook.pathFor(coupleId, bookId),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// The creator renames a book.
  Future<void> rename({
    required String coupleId,
    required String bookId,
    required String title,
  }) => _books(coupleId).doc(bookId).update({'title': cleanTitle(title)});

  /// Either partner deletes a book and its PDF.
  Future<void> delete({
    required String coupleId,
    required MemoryBook book,
  }) async {
    await _books(coupleId).doc(book.id).delete();
    try {
      await _files.delete(book.storagePath);
    } catch (_) {
      // The record is gone; a leftover file is harmless.
    }
  }

  /// The book's PDF.
  Future<Uint8List> readPdf(MemoryBook book) => _files.read(book.storagePath);

  static String cleanTitle(String title) {
    final t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return 'Our memory book';
    return t.length > MemoryBook.maxTitle
        ? t.substring(0, MemoryBook.maxTitle)
        : t;
  }
}
