import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/books/models/book.dart';
import 'package:couple_app/features/books/providers/book_providers.dart';

/// How a book's PDF is drawn on screen: `printing`'s [PdfPreview] in the
/// app. Tests and screenshots replace it (it needs the platform's PDF
/// renderer).
final bookPdfViewProvider = Provider<BookPdfViewBuilder>(
  (ref) =>
      (context, bytes, title) => PdfPreview(
        build: (_) async => bytes,
        pdfFileName: '${_fileName(title)}.pdf',
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        maxPageWidth: 520,
      ),
);

String _fileName(String title) {
  final cleaned = title.replaceAll(RegExp(r'[^A-Za-z0-9 &_-]'), '').trim();
  return cleaned.isEmpty ? 'Memory book' : cleaned;
}

/// Opens the share sheet with [bytes] as a PDF; the app lock waits.
Future<void> shareBookPdf(WidgetRef ref, Uint8List bytes, String title) {
  return ref
      .read(appLockControllerProvider.notifier)
      .suspendWhile(
        SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: 'application/pdf',
                name: '${_fileName(title)}.pdf',
              ),
            ],
            fileNameOverrides: ['${_fileName(title)}.pdf'],
            subject: title,
          ),
        ),
      );
}

/// A book's pages, with sharing: a saved book (fetched from Storage) or
/// one made just now (a preview, or a book not yet saved).
class BookViewerScreen extends ConsumerStatefulWidget {
  const BookViewerScreen({
    super.key,
    required this.title,
    this.book,
    this.bytes,
  }) : assert(book != null || bytes != null);

  final String title;
  final MemoryBook? book;
  final Uint8List? bytes;

  static Route<void> route({
    required String title,
    MemoryBook? book,
    Uint8List? bytes,
  }) => MaterialPageRoute<void>(
    builder: (_) => BookViewerScreen(title: title, book: book, bytes: bytes),
  );

  @override
  ConsumerState<BookViewerScreen> createState() => _BookViewerScreenState();
}

class _BookViewerScreenState extends ConsumerState<BookViewerScreen> {
  late final Future<Uint8List> _bytes = widget.bytes != null
      ? Future.value(widget.bytes)
      : ref.read(bookServiceProvider).readPdf(widget.book!);

  Future<void> _share() async {
    try {
      await shareBookPdf(ref, await _bytes, widget.title);
    } catch (_) {
      if (mounted) context.showSnackMessage('Couldn\'t share this book.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(bookPdfViewProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Share or save',
            icon: const Icon(Icons.ios_share),
            onPressed: _share,
          ),
        ],
      ),
      body: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Text('This book couldn\'t be opened.'));
          }
          final bytes = snap.data;
          if (bytes == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return view(context, bytes, widget.title);
        },
      ),
    );
  }
}
