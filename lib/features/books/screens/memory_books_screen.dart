import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/core/widgets/name_edit_dialog.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/books/models/book.dart';
import 'package:couple_app/features/books/providers/book_providers.dart';
import 'package:couple_app/features/books/screens/book_builder_screen.dart';
import 'package:couple_app/features/books/screens/book_viewer_screen.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';

/// "Jan – Oct 2026", or "Oct 2026" for one month.
String bookRangeText(DateTime from, DateTime to) {
  final f = DateFormat('MMM y');
  final a = f.format(from), b = f.format(to);
  if (a == b) return a;
  if (from.year == to.year) return '${DateFormat('MMM').format(from)} – $b';
  return '$a – $b';
}

/// Us → Memory books: the books you've made, to open, share, rename or
/// delete, and the way to make a new one.
class MemoryBooksScreen extends ConsumerWidget {
  const MemoryBooksScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const MemoryBooksScreen());

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    MemoryBook b,
  ) async {
    final service = ref.read(bookServiceProvider);
    final coupleId = ref.read(currentCoupleIdProvider);
    final title = await showNameEditDialog(
      context: context,
      title: 'Rename book',
      label: 'Title',
      initialValue: b.title,
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      await service.rename(coupleId: coupleId, bookId: b.id, title: title);
    } catch (_) {
      if (context.mounted) context.showSnackMessage('Couldn\'t rename it.');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MemoryBook b,
  ) async {
    final service = ref.read(bookServiceProvider);
    final coupleId = ref.read(currentCoupleIdProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this book?'),
        content: const Text(
          'It\'s removed for both of you. Your memories stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: pillButtonStyle(
              dialogContext,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await service.delete(coupleId: coupleId, book: b);
    } catch (_) {
      if (context.mounted) context.showSnackMessage('Couldn\'t delete it.');
    }
  }

  Future<void> _share(BuildContext context, WidgetRef ref, MemoryBook b) async {
    try {
      final bytes = await ref.read(bookServiceProvider).readPdf(b);
      await shareBookPdf(ref, bytes, b.title);
    } catch (_) {
      if (context.mounted) context.showSnackMessage('Couldn\'t share it.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final books = ref.watch(booksProvider);
    final credits = ref.watch(bookCreditsProvider);
    final uid = ref.watch(currentUidProvider);
    final list = books.value ?? const <MemoryBook>[];

    return RomanceBackdrop(
      preset: GradientPreset.lavender,
      strength: .45,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: romanceAppBar(
          automaticallyImplyLeading: true,
          title: const Text('Memory books'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            AnimatedGradientCard(
              preset: GradientPreset.festive,
              radius: 26,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const IconTile(
                        icon: Icons.auto_stories_rounded,
                        preset: GradientPreset.festive,
                        size: 48,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your story, as a book',
                              style: romanceSerif(
                                theme.textTheme.titleLarge,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              credits > 0
                                  ? (credits == 1
                                        ? '1 book ready to make'
                                        : '$credits books ready to make')
                                  : 'Photos, notes and dates, month by month. '
                                        'Preview it free.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const Key('books-make'),
                    onPressed: () =>
                        Navigator.of(context).push(BookBuilderScreen.route()),
                    style: pillButtonStyle(
                      context,
                      preset: GradientPreset.festive,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Make a memory book'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (books.isLoading && !books.hasValue)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyState(
                  icon: Icons.menu_book_outlined,
                  text: 'Books you make are kept here, for both of you.',
                ),
              ),
            for (final (i, b) in list.indexed) ...[
              _BookTile(
                book: b,
                preset: i.isEven
                    ? GradientPreset.blush
                    : GradientPreset.lavender,
                canRename: b.createdBy == uid,
                onOpen: () => Navigator.of(
                  context,
                ).push(BookViewerScreen.route(title: b.title, book: b)),
                onShare: () => _share(context, ref, b),
                onRename: () => _rename(context, ref, b),
                onDelete: () => _delete(context, ref, b),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.preset,
    required this.canRename,
    required this.onOpen,
    required this.onShare,
    required this.onRename,
    required this.onDelete,
  });

  final MemoryBook book;
  final GradientPreset preset;
  final bool canRename;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return AnimatedGradientCard(
      key: Key('book-${book.id}'),
      preset: preset,
      radius: 22,
      onTap: onOpen,
      sheen: false,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  preset.isDarkIn(b) ? preset.accent(b) : preset.ink,
                  GradientPreset.lavender.ink,
                ],
              ),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: romanceSerif(theme.textTheme.titleMedium).copyWith(
                    fontWeight: FontWeight.w700,
                    color: preset.foreground(b),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${bookRangeText(book.fromDate, book.toDate)} · '
                  '${book.pageCount} pages',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: preset.foregroundMuted(b),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            iconColor: preset.foregroundMuted(b),
            onSelected: (v) => switch (v) {
              'share' => onShare(),
              'rename' => onRename(),
              'delete' => onDelete(),
              _ => onOpen(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'open', child: Text('Open')),
              const PopupMenuItem(value: 'share', child: Text('Share or save')),
              if (canRename)
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}
