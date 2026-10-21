import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

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

/// [BookFileStore] in Firebase Storage (`application/pdf`, < 50 MB).
class StorageBookFileStore implements BookFileStore {
  StorageBookFileStore([FirebaseStorage? storage]) : _given = storage;

  final FirebaseStorage? _given;
  FirebaseStorage get _storage => _given ?? FirebaseStorage.instance;

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
    final data = await _storage.ref(path).getData(maxBytes);
    if (data == null) throw BookException('This book couldn\'t be opened.');
    return data;
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}

/// The couple's memory books: `couples/{cid}/books`, their PDFs, and the
/// book credits that pay for them.
///
/// A credit is spent only by [saveBook]'s final batch, after the PDF is
/// uploaded: `bookCredits` goes down by exactly one in the same batch that
/// creates the book document, as the rules require.
class BookService {
  BookService({FirebaseFirestore? firestore, BookFileStore? files})
    : _db = firestore ?? FirebaseFirestore.instance,
      _files = files ?? StorageBookFileStore();

  final FirebaseFirestore _db;
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
