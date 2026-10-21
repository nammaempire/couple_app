import 'dart:typed_data';

import 'package:couple_app/features/books/data/book_images.dart';
import 'package:couple_app/features/books/data/book_pdf_builder.dart';
import 'package:couple_app/features/books/models/book.dart';

/// How far along a book is, for "Making your book… 12 of 34 pages".
class BookProgress {
  const BookProgress(this.stage, this.done, this.total);

  /// `photos` while fetching photos, `pages` while laying out pages.
  final String stage;
  final int done;
  final int total;

  String get label => stage == 'photos'
      ? 'Gathering your photos… $done of $total'
      : 'Making your book… $done of $total pages';

  double get fraction => total == 0 ? 0 : done / total;
}

/// A finished PDF, ready to upload.
class MadeBook {
  const MadeBook({required this.bytes, required this.pageCount});

  final Uint8List bytes;
  final int pageCount;
}

/// Fetches the photos a book needs and lays it out, for the preview (the
/// first pages, watermarked) or the whole book.
class BookMaker {
  BookMaker({required this.images, required this.fonts});

  final BookImageSource images;
  final Future<BookFonts> Function() fonts;

  /// Photos on the first [pages] pages, or every photo.
  static Iterable<BookPhoto> photosFor(BookContent content, {int? pages}) {
    final specs = BookPdfBuilder.plan(content);
    final used = pages == null ? specs : specs.take(pages);
    return [
      for (final spec in used)
        if (spec is MemoryPageSpec) ...spec.photos,
    ];
  }

  Future<void> _fetch(
    Iterable<BookPhoto> photos, {
    void Function(BookProgress)? onProgress,
    BookCancelToken? cancel,
  }) async {
    final todo = photos.where((p) => p.bytes == null).toList();
    for (var i = 0; i < todo.length; i++) {
      if (cancel?.isCancelled ?? false) throw const BookCancelled();
      onProgress?.call(BookProgress('photos', i, todo.length));
      todo[i].bytes = await images.fetch(todo[i].url);
    }
  }

  /// The first [BookPdfBuilder.previewPages] pages, marked "Preview".
  Future<Uint8List> preview(BookContent content) async {
    await _fetch(photosFor(content, pages: BookPdfBuilder.previewPages));
    return BookPdfBuilder(await fonts()).build(content, preview: true);
  }

  /// The whole book.
  Future<MadeBook> make(
    BookContent content, {
    void Function(BookProgress)? onProgress,
    BookCancelToken? cancel,
  }) async {
    await _fetch(photosFor(content), onProgress: onProgress, cancel: cancel);
    final builder = BookPdfBuilder(await fonts());
    var pages = 0;
    final bytes = await builder.build(
      content,
      cancel: cancel,
      onPage: (done, total) {
        pages = total;
        onProgress?.call(BookProgress('pages', done, total));
      },
    );
    return MadeBook(bytes: bytes, pageCount: pages);
  }
}
