import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/books/data/book_content_loader.dart';
import 'package:couple_app/features/books/data/book_images.dart';
import 'package:couple_app/features/books/data/book_maker.dart';
import 'package:couple_app/features/books/data/book_pdf_builder.dart';
import 'package:couple_app/features/books/data/book_service.dart';
import 'package:couple_app/features/books/models/book.dart';
import 'package:couple_app/features/memories/providers/memory_providers.dart';
import 'package:couple_app/features/music/providers/music_providers.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';

final bookServiceProvider = Provider<BookService>((ref) => BookService());

/// Where a book's photos come from.
final bookImageSourceProvider = Provider<BookImageSource>(
  (ref) => CachedBookImageSource(),
);

/// The fonts embedded in books, loaded once.
final bookFontsProvider = FutureProvider<BookFonts>((ref) => BookFonts.load());

final bookContentLoaderProvider = Provider<BookContentLoader>(
  (ref) => BookContentLoader(
    memories: ref.watch(memoryServiceProvider),
    notes: ref.watch(loveNoteServiceProvider),
    datePlans: ref.watch(datePlanServiceProvider),
    games: ref.watch(gameServiceProvider),
    songs: ref.watch(musicServiceProvider),
  ),
);

final bookMakerProvider = Provider<BookMaker>(
  (ref) => BookMaker(
    images: ref.watch(bookImageSourceProvider),
    fonts: () => ref.read(bookFontsProvider.future),
  ),
);

/// Renders a cartoon avatar to PNG for the cover. Tests replace it.
final avatarPngRendererProvider =
    Provider<Future<Uint8List?> Function(AvatarConfig config)>(
      (ref) => renderAvatarPng,
    );

/// The time, for ranges and "delivered" notes. Tests replace it.
final bookClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Shows a book's PDF. The app uses `printing`'s `PdfPreview`; tests and
/// screenshots replace it, since that needs the platform's PDF renderer.
typedef BookPdfViewBuilder =
    Widget Function(BuildContext context, Uint8List bytes, String title);

/// The couple's books, newest first.
final booksProvider = StreamProvider.autoDispose<List<MemoryBook>>(
  (ref) => ref
      .watch(bookServiceProvider)
      .watchBooks(ref.watch(currentCoupleIdProvider)),
);
