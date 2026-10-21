import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/books/data/book_maker.dart';
import 'package:couple_app/features/books/data/book_pdf_builder.dart';
import 'package:couple_app/features/books/data/book_service.dart';
import 'package:couple_app/features/books/models/book.dart';
import 'package:couple_app/features/books/providers/book_providers.dart';
import 'package:couple_app/features/books/screens/book_viewer_screen.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/busy_button_label.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/premium/models/products.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';
import 'package:couple_app/features/premium/widgets/purchase_status_banner.dart';

/// Make a memory book: pick the range and title, see what goes in, look at
/// a free preview (the first pages, marked "Preview"), then make it.
///
/// Making it uses one book credit, and only at the very end: the PDF is
/// made on the phone, uploaded, and then one batch spends the credit and
/// records the book. If the upload fails the PDF is kept so it can be
/// saved again without being made (or paid for) again. With no credit,
/// the button buys one (`book_single`).
class BookBuilderScreen extends ConsumerStatefulWidget {
  const BookBuilderScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute<void>(builder: (_) => const BookBuilderScreen());

  @override
  ConsumerState<BookBuilderScreen> createState() => _BookBuilderScreenState();
}

enum _Stage { choosing, making, saving, unsaved }

class _BookBuilderScreenState extends ConsumerState<BookBuilderScreen> {
  BookRange _range = BookRange.thisYear;
  ({DateTime from, DateTime to})? _custom;
  final _title = TextEditingController();
  bool _titleEdited = false;

  Future<BookContent>? _content;
  _Stage _stage = _Stage.choosing;
  BookProgress? _progress;
  BookCancelToken? _cancel;
  bool _previewing = false;

  /// A made book waiting to be saved, with the id it will have.
  ({String bookId, MadeBook made, BookContent content})? _unsaved;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _title.dispose();
    super.dispose();
  }

  ({DateTime from, DateTime to}) _dates() {
    final couple = ref.read(coupleProvider).value;
    return _range.dates(
      ref.read(bookClockProvider)(),
      start: couple?.startDate,
      custom: _custom,
    );
  }

  String _defaultTitle(AppUser me, String partner) {
    final d = _dates();
    final years = d.from.year == d.to.year
        ? '${d.to.year}'
        : '${d.from.year}–${d.to.year}';
    return '${me.displayName} & $partner · $years';
  }

  void _reload() {
    final me = ref.read(currentUserProvider);
    final partner = ref.read(partnerNameProvider);
    if (!_titleEdited) _title.text = _defaultTitle(me, partner);
    final content = _load();
    setState(() {
      _content = content;
    });
  }

  Future<BookContent> _load() async {
    final couple = ref.read(coupleProvider).value!;
    final me = ref.read(currentUserProvider);
    final partnerUser = ref.read(partnerProvider).value;
    final partner = ref.read(partnerNameProvider);
    final d = _dates();
    final content = await ref
        .read(bookContentLoaderProvider)
        .load(
          couple: couple,
          me: me,
          partner: partnerUser,
          partnerName: partner,
          from: d.from,
          to: d.to,
          title: _title.text,
          now: ref.read(bookClockProvider)(),
        );
    return _withCover(content, couple, me, partnerUser);
  }

  /// The couple photo, or both avatars, for the cover.
  Future<BookContent> _withCover(
    BookContent c,
    Couple couple,
    AppUser me,
    AppUser? partner,
  ) async {
    Uint8List? cover;
    final photo = couple.photoUrl;
    if (photo != null) {
      cover = await ref
          .read(bookImageSourceProvider)
          .fetch(photo, maxEdge: 1200);
    }
    final avatars = <Uint8List>[];
    if (cover == null) {
      final render = ref.read(avatarPngRendererProvider);
      for (final config in [me.avatar, partner?.avatar]) {
        if (config == null) continue;
        final png = await render(config);
        if (png != null) avatars.add(png);
      }
    }
    return BookContent(
      title: c.title,
      names: c.names,
      from: c.from,
      to: c.to,
      startDate: c.startDate,
      coverImage: cover,
      avatarImages: avatars,
      months: c.months,
      numbers: c.numbers,
    );
  }

  BookContent _titled(BookContent c) => BookContent(
    title: BookService.cleanTitle(_title.text),
    names: c.names,
    from: c.from,
    to: c.to,
    startDate: c.startDate,
    coverImage: c.coverImage,
    avatarImages: c.avatarImages,
    months: c.months,
    numbers: c.numbers,
  );

  Future<void> _pickCustom() async {
    final now = ref.read(bookClockProvider)();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _custom == null
          ? DateTimeRange(start: DateTime(now.year), end: now)
          : DateTimeRange(start: _custom!.from, end: _custom!.to),
      helpText: 'Which dates go in the book?',
    );
    if (picked == null) return;
    setState(() {
      _custom = (from: picked.start, to: picked.end);
      _range = BookRange.custom;
    });
    _reload();
  }

  Future<void> _preview() async {
    final content = await _content;
    if (content == null || content.isEmpty) return;
    setState(() => _previewing = true);
    try {
      final bytes = await ref.read(bookMakerProvider).preview(_titled(content));
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(BookViewerScreen.route(title: 'Preview', bytes: bytes));
    } catch (e) {
      if (mounted) context.showSnackMessage('Couldn\'t make the preview.');
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  void _buy() {
    ref
        .read(purchaseControllerProvider.notifier)
        .buy(Products.bookSingle, coupleId: ref.read(currentCoupleIdProvider));
  }

  Future<void> _make() async {
    final content = await _content;
    if (content == null || content.isEmpty) return;
    if (ref.read(bookCreditsProvider) < 1) return _buy();
    final cancel = BookCancelToken();
    final bookId = ref
        .read(bookServiceProvider)
        .newBookId(ref.read(currentCoupleIdProvider));
    setState(() {
      _stage = _Stage.making;
      _cancel = cancel;
      _progress = null;
    });
    try {
      final titled = _titled(content);
      final made = await ref
          .read(bookMakerProvider)
          .make(
            titled,
            cancel: cancel,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      _unsaved = (bookId: bookId, made: made, content: titled);
      await _keepLocally(bookId, made.bytes);
      await _save();
    } on BookCancelled {
      if (mounted) setState(() => _stage = _Stage.choosing);
    } catch (e, st) {
      debugPrint('Making the book failed: $e\n$st');
      if (!mounted) return;
      setState(() => _stage = _Stage.choosing);
      context.showSnackMessage('Couldn\'t make the book. Try again.');
    }
  }

  /// Best effort: a copy on the phone while it isn't saved.
  Future<void> _keepLocally(String bookId, Uint8List bytes) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await File('${dir.path}/book_$bookId.pdf').writeAsBytes(bytes);
    } catch (_) {}
  }

  /// Uploads the made book, then spends one credit and records it.
  Future<void> _save() async {
    final unsaved = _unsaved;
    if (unsaved == null) return;
    final service = ref.read(bookServiceProvider);
    final coupleId = ref.read(currentCoupleIdProvider);
    final uid = ref.read(currentUidProvider);
    setState(() => _stage = _Stage.saving);
    try {
      await service.uploadPdf(
        coupleId: coupleId,
        bookId: unsaved.bookId,
        bytes: unsaved.made.bytes,
      );
      await service.saveBook(
        coupleId: coupleId,
        bookId: unsaved.bookId,
        uid: uid,
        title: unsaved.content.title,
        fromDate: unsaved.content.from,
        toDate: unsaved.content.to,
        pageCount: unsaved.made.pageCount,
        creditsBefore: ref.read(bookCreditsProvider),
      );
      _unsaved = null;
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        BookViewerScreen.route(
          title: unsaved.content.title,
          bytes: unsaved.made.bytes,
        ),
      );
    } on BookException catch (e) {
      if (!mounted) return;
      setState(() => _stage = _Stage.unsaved);
      context.showSnackMessage(e.message);
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.unsaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The partner's name arrives a moment after the screen opens; the
    // default title follows it until edited.
    ref.listen(partnerNameProvider, (_, name) {
      if (_titleEdited) return;
      _title.text = _defaultTitle(ref.read(currentUserProvider), name);
    });
    final theme = Theme.of(context);
    final credits = ref.watch(bookCreditsProvider);
    final purchase = ref.watch(purchaseControllerProvider);
    final price = ref
        .watch(storeProductsProvider(Products.bookSingle))
        .value?[Products.bookSingle]
        ?.price;
    final busy = _stage != _Stage.choosing && _stage != _Stage.unsaved;

    return PopScope(
      canPop: !busy,
      child: RomanceBackdrop(
        preset: GradientPreset.lavender,
        strength: .5,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: romanceAppBar(
            automaticallyImplyLeading: !busy,
            title: const Text('Make a memory book'),
          ),
          body: SafeArea(
            child: busy
                ? BookMakingView(
                    progress: _progress,
                    saving: _stage == _Stage.saving,
                    onCancel: _stage == _Stage.making
                        ? () => _cancel?.cancel()
                        : null,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    children: [
                      if (_stage == _Stage.unsaved) ...[
                        _UnsavedCard(onRetry: _save),
                        const SizedBox(height: 14),
                      ],
                      const PurchaseStatusBanner(
                        successText:
                            'Your book is paid for. Tap “Make our book”.',
                      ),
                      FrostedForm(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              key: const Key('book-title'),
                              controller: _title,
                              maxLength: MemoryBook.maxTitle,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Title',
                                prefixIcon: Icon(Icons.edit_outlined),
                                counterText: '',
                              ),
                              onChanged: (_) => _titleEdited = true,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Which moments?',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final r in BookRange.values)
                                  ChoiceChip(
                                    key: Key('range-${r.name}'),
                                    label: Text(
                                      r == BookRange.custom && _custom != null
                                          ? _customLabel()
                                          : r.label,
                                    ),
                                    selected: _range == r,
                                    onSelected: (_) {
                                      if (r == BookRange.custom) {
                                        _pickCustom();
                                        return;
                                      }
                                      setState(() => _range = r);
                                      _reload();
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      FutureBuilder<BookContent>(
                        future: _content,
                        builder: (context, snap) => _Summary(
                          content: snap.data,
                          loading: snap.connectionState != ConnectionState.done,
                          failed: snap.hasError,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FutureBuilder<BookContent>(
                        future: _content,
                        builder: (context, snap) {
                          final ready =
                              snap.hasData && !(snap.data?.isEmpty ?? true);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              OutlinedButton.icon(
                                key: const Key('book-preview'),
                                onPressed: ready && !_previewing
                                    ? _preview
                                    : null,
                                style: pillOutlineStyle(
                                  context,
                                  preset: GradientPreset.lavender,
                                ),
                                icon: const Icon(Icons.visibility_outlined),
                                label: BusyButtonLabel(
                                  busy: _previewing,
                                  label: 'See a free preview',
                                ),
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                key: const Key('book-make'),
                                onPressed: ready && !purchase.busy
                                    ? _make
                                    : null,
                                style: pillButtonStyle(
                                  context,
                                  preset: GradientPreset.festive,
                                ),
                                icon: Icon(
                                  credits > 0
                                      ? Icons.auto_stories_rounded
                                      : Icons.shopping_bag_outlined,
                                ),
                                label: Text(
                                  credits > 0
                                      ? 'Make our book'
                                      : price == null
                                      ? 'Get this book'
                                      : 'Get this book · $price',
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                credits > 0
                                    ? (credits == 1
                                          ? 'Uses your paid book, only once '
                                                'it\'s saved.'
                                          : 'Uses 1 of your $credits paid '
                                                'books, only once it\'s saved.')
                                    : 'One payment makes one book. The '
                                          'preview is free.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  String _customLabel() {
    final c = _custom!;
    final f = DateFormat('d MMM y');
    return '${f.format(c.from)} – ${f.format(c.to)}';
  }
}

/// What's going in: counts, and that private things never do.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.content,
    required this.loading,
    required this.failed,
  });

  final BookContent? content;
  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.blush;
    final c = content;

    Widget body;
    if (failed) {
      body = const Text(
        'Couldn\'t gather your moments. Check your connection.',
      );
    } else if (loading || c == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(),
        ),
      );
    } else if (c.isEmpty) {
      body = Text(
        'Nothing in these dates yet. Try a longer range.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: preset.foreground(b),
        ),
      );
    } else {
      final pages = BookPdfBuilder.plan(c).length;
      final memories = c.months.expand((m) => m.memories).length;
      final photos = c.photos.length;
      final notes = c.months
          .expand((m) => m.entries)
          .whereType<BookNote>()
          .length;
      final dates = c.months
          .expand((m) => m.entries)
          .whereType<BookDatePlan>()
          .length;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About $pages pages',
            key: const Key('book-pages'),
            style: romanceSerif(theme.textTheme.titleLarge).copyWith(
              fontWeight: FontWeight.w700,
              color: preset.foreground(b),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(_count(memories, 'memory', 'memories')),
              _Chip(_count(photos, 'photo', 'photos')),
              _Chip(_count(notes, 'love note', 'love notes')),
              _Chip(_count(dates, 'date', 'dates')),
              _Chip(_count(c.months.length, 'month', 'months')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Private, your chat and unopened notes are never included.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: preset.foregroundMuted(b),
            ),
          ),
        ],
      );
    }
    return AnimatedGradientCard(
      preset: preset,
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: SizedBox(width: double.infinity, child: body),
    );
  }
}

String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: dark ? .12 : .7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// "Making your book… 12 of 34 pages", with Cancel.
class BookMakingView extends StatelessWidget {
  const BookMakingView({
    super.key,
    required this.progress,
    required this.saving,
    required this.onCancel,
  });

  final BookProgress? progress;
  final bool saving;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: GlassPanel(
          dark: theme.brightness == Brightness.dark,
          radius: 28,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GlowBadge(
                preset: GradientPreset.lavender,
                icon: Icons.auto_stories_rounded,
                size: 72,
              ),
              const SizedBox(height: 18),
              Text(
                saving
                    ? 'Saving your book…'
                    : p?.label ?? 'Getting your moments ready…',
                key: const Key('book-progress'),
                textAlign: TextAlign.center,
                style: romanceSerif(theme.textTheme.titleLarge).copyWith(
                  fontWeight: FontWeight.w700,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: saving ? null : p?.fraction,
                  color: GradientPreset.lavender.ink,
                  backgroundColor: Colors.white.withValues(alpha: .6),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onCancel,
                child: Text(onCancel == null ? 'Almost done' : 'Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnsavedCard extends StatelessWidget {
  const _UnsavedCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    const preset = GradientPreset.sunny;
    return AnimatedGradientCard(
      key: const Key('book-unsaved'),
      preset: preset,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your book is made, but it couldn\'t be saved yet.',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: preset.foreground(b),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'It\'s kept on this phone. Nothing has been used up.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: preset.foregroundMuted(b),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('book-save-again'),
            onPressed: onRetry,
            style: pillButtonStyle(
              context,
              preset: GradientPreset.festive,
              minimumSize: const Size.fromHeight(46),
            ),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Save again'),
          ),
        ],
      ),
    );
  }
}
