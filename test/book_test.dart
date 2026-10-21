import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/theme/app_theme.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/books/data/book_maker.dart';
import 'package:couple_app/features/books/data/book_pdf_builder.dart';
import 'package:couple_app/features/books/data/book_service.dart';
import 'package:couple_app/features/books/models/book.dart';
import 'package:couple_app/features/books/providers/book_providers.dart';
import 'package:couple_app/features/books/screens/book_builder_screen.dart';
import 'package:couple_app/features/books/screens/memory_books_screen.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/premium/models/products.dart';

import 'pairing_fakes.dart';
import 'premium_fakes.dart';

/// Pages in a PDF, counted from its page objects.
int pdfPages(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page(?![s\w])').allMatches(latin1.decode(bytes)).length;

void main() {
  late BookFonts fonts;
  late PairingRig pairing;
  late PremiumRig rig;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    fonts = await BookFonts.load();
  });

  /// A year of shared life, plus private things that must never show up.
  Future<void> seedLife() async {
    final c = pairing.couple;
    await c.update({'startDate': Timestamp.fromDate(DateTime(2023, 2, 14))});
    await pairing.db.collection('users').doc(pAsha).update({
      'birthday': Timestamp.fromDate(DateTime(1997, 11, 2)),
    });
    Future<void> memory(
      String id,
      DateTime date,
      String title, {
      int photos = 1,
      String album = 'Trips',
    }) => c.collection('memories').doc(id).set({
      'title': title,
      'caption': 'Caption for $title',
      'date': Timestamp.fromDate(date),
      'place': 'Goa',
      'album': album,
      'createdBy': pAsha,
      'media': [
        for (var i = 0; i < photos; i++)
          {'type': 'image', 'url': 'https://img/$id/$i.jpg'},
      ],
    });
    await memory('m1', DateTime(2026, 2, 14), 'Goa weekend', photos: 3);
    await memory('m2', DateTime(2026, 3, 8), 'Holi');
    await memory('m3', DateTime(2026, 6, 1), 'Rainy day', photos: 0);
    await memory('old', DateTime(2024, 5, 1), 'Long ago');

    Future<void> note(
      String id,
      DateTime deliverAt, {
      required bool opened,
      required String body,
    }) async {
      await c.collection('notes').doc(id).set({
        'senderId': pRavi,
        'recipientId': pAsha,
        'kind': 'letter',
        'title': 'Note $id',
        'deliverAt': Timestamp.fromDate(deliverAt),
        'openedAt': opened ? Timestamp.fromDate(deliverAt) : null,
        'hasVoice': false,
      });
      await c
          .collection('notes')
          .doc(id)
          .collection('sealed')
          .doc('content')
          .set({'body': body, 'deliverAt': Timestamp.fromDate(deliverAt)});
    }

    await note('n1', DateTime(2026, 2, 20), opened: true, body: 'OPENED-WORDS');
    await note(
      'n2',
      DateTime(2026, 4, 2),
      opened: false,
      body: 'UNOPENED-SECRET',
    );
    await note(
      'n3',
      DateTime(2026, 12, 25),
      opened: false,
      body: 'FUTURE-SECRET',
    );

    await c.collection('datePlans').doc('d1').set({
      'title': 'Dinner at Toit',
      'status': 'done',
      'scheduledAt': Timestamp.fromDate(DateTime(2026, 2, 25)),
      'completedAt': Timestamp.fromDate(DateTime(2026, 2, 25)),
      'location': 'Indiranagar',
      'reflection': 'Best pizza',
      'rating': 5,
    });
    await c.collection('datePlans').doc('d2').set({
      'title': 'Not done yet',
      'status': 'planned',
      'scheduledAt': Timestamp.fromDate(DateTime(2026, 5, 2)),
    });
    await c.collection('games').doc('g1').set({
      'type': 'ticTacToe',
      'status': 'finished',
      'createdBy': pAsha,
      'invitee': pRavi,
      'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
    });
    await c.collection('songs').doc('s1').set({'title': 'Tum Hi Ho'});

    // Private: the vault and the chat.
    await c.collection('vaultItems').doc('v1').set({'ct': 'VAULT-SECRET'});
    await c.collection('messages').doc('x1').set({
      'senderId': pRavi,
      'type': 'text',
      'text': 'CHAT-SECRET',
    });
  }

  setUp(() async {
    pairing = PairingRig();
    pairing.now = DateTime(2026, 10, 21, 10);
    rig = PremiumRig(pairing, fonts: fonts);
    await pairing.seedCouple();
    await seedLife();
  });

  Future<BookContent> load() async {
    final c = ProviderContainer(overrides: rig.overrides(pAsha));
    addTearDown(c.dispose);
    final couple = Couple.fromDoc(await pairing.couple.get());
    final me = AppUser.fromDoc(
      await pairing.db.collection('users').doc(pAsha).get(),
    );
    final ravi = AppUser.fromDoc(
      await pairing.db.collection('users').doc(pRavi).get(),
    );
    return c
        .read(bookContentLoaderProvider)
        .load(
          couple: couple,
          me: me,
          partner: ravi,
          partnerName: 'Ravi',
          from: DateTime(2026),
          to: DateTime(2026, 10, 21, 23, 59),
          title: 'Asha & Ravi · 2026',
          now: pairing.now,
        );
  }

  /// Every word in the content, to look for things that must not be there.
  String allText(BookContent c) => [
    for (final m in c.months)
      for (final e in m.entries)
        switch (e) {
          BookMemory() => '${e.title} ${e.caption}',
          BookNote() => '${e.title} ${e.body}',
          BookDatePlan() => '${e.title} ${e.reflection}',
          BookMilestone() => e.title,
        },
  ].join(' ');

  group('content', () {
    test(
      'memories, opened notes, done dates and milestones in range',
      () async {
        final c = await load();
        final text = allText(c);
        expect(text, contains('Goa weekend'));
        expect(text, contains('Holi'));
        expect(text, isNot(contains('Long ago')));
        expect(text, contains('OPENED-WORDS'));
        expect(text, contains('Dinner at Toit'));
        expect(text, isNot(contains('Not done yet')));
        expect(text, contains('Our anniversary · 3 years'));
        // Her birthday (2 Nov) is after the range.
        expect(text, isNot(contains('Asha\'s birthday')));
        expect(c.months.map((m) => m.month.month), [2, 3, 6]);
        expect(c.numbers.memories, 3);
        expect(c.numbers.notes, 1);
        expect(c.numbers.gamesPlayed, 1);
        expect(c.numbers.songsSaved, 1);
        expect(c.photos.length, 4);
      },
      skip: false,
    );

    test('never the vault, the chat, or unopened notes', () async {
      final text = allText(await load());
      expect(text, isNot(contains('VAULT-SECRET')));
      expect(text, isNot(contains('CHAT-SECRET')));
      expect(text, isNot(contains('UNOPENED-SECRET')));
      expect(text, isNot(contains('FUTURE-SECRET')));
    });
  });

  group('pdf', () {
    test('plans pages: cover, contents, chapters, numbers, closing', () async {
      final c = await load();
      final pages = BookPdfBuilder.plan(c);
      expect(pages.first, isA<CoverPageSpec>());
      expect(pages[1], isA<ContentsPageSpec>());
      expect(pages[pages.length - 2], isA<NumbersPageSpec>());
      expect(pages.last, isA<ClosingPageSpec>());
      // Goa's three photos take two pages (two, then one).
      final goa = pages.whereType<MemoryPageSpec>().where(
        (p) => p.memory.title == 'Goa weekend',
      );
      expect(goa.map((p) => p.photos.length), [2, 1]);
      final toc = BookPdfBuilder.chapters(pages);
      expect(toc.map((t) => t.month.month), [2, 3, 6]);
      expect(toc.first.page, 3);
    });

    test('a lone milestone rides on the month\'s first photo page', () {
      final content = BookContent(
        title: 't',
        names: 'Asha & Ravi',
        from: DateTime(2026),
        to: DateTime(2026, 12),
        months: [
          BookMonth(
            month: DateTime(2026, 2),
            entries: [
              BookMilestone(date: DateTime(2026, 2, 14), title: 'Anniversary'),
              BookMemory(
                date: DateTime(2026, 2, 14),
                title: 'Dinner',
                photos: [BookPhoto(url: 'a')],
              ),
            ],
          ),
        ],
        numbers: const BookNumbers(),
      );
      final pages = BookPdfBuilder.plan(content);
      expect(pages.whereType<MomentsPageSpec>(), isEmpty);
      final first = pages.whereType<MemoryPageSpec>().single;
      expect(first.monthStart, isTrue);
      expect(first.milestones.single.title, 'Anniversary');
      expect(pages, hasLength(5));
    });

    test('emoji are left out of printed text', () {
      expect(
        BookPdfBuilder.printable('Ravi lost three games in a row 🎳 ❤️ ok'),
        'Ravi lost three games in a row ok',
      );
      expect(
        BookPdfBuilder.printable('Asha & Ravi · 2026'),
        'Asha & Ravi · 2026',
      );
    });

    test('the preview is the first 3 pages, marked Preview', () async {
      final c = await load();
      final maker = BookMaker(images: rig.images, fonts: () async => fonts);
      final bytes = await maker.preview(c);
      expect(pdfPages(bytes), BookPdfBuilder.previewPages);
      expect(latin1.decode(bytes), contains('(Preview)'));
      // Only the photos on those pages were fetched.
      expect(rig.images.fetched, isEmpty);
    });

    test('the whole book: every planned page, a sane size', () async {
      final c = await load();
      final maker = BookMaker(images: rig.images, fonts: () async => fonts);
      final progress = <String>[];
      final made = await maker.make(
        c,
        onProgress: (p) => progress.add(p.label),
      );
      expect(made.pageCount, BookPdfBuilder.plan(c).length);
      expect(pdfPages(made.bytes), made.pageCount);
      expect(latin1.decode(made.bytes), isNot(contains('(Preview)')));
      expect(made.bytes.length, lessThan(5 * 1024 * 1024));
      expect(rig.images.fetched, hasLength(4));
      expect(
        progress.last,
        'Making your book… ${made.pageCount} of '
        '${made.pageCount} pages',
      );
    });

    test('cancel stops it', () async {
      final c = await load();
      final maker = BookMaker(images: rig.images, fonts: () async => fonts);
      final cancel = BookCancelToken()..cancel();
      expect(
        () => maker.make(c, cancel: cancel),
        throwsA(isA<BookCancelled>()),
      );
    });
  });

  group('saving', () {
    test('one batch spends exactly one credit and records the book', () async {
      await pairing.couple.update({'bookCredits': 2});
      await rig.books.saveBook(
        coupleId: pCouple,
        bookId: 'b1',
        uid: pAsha,
        title: 'Asha & Ravi · 2026',
        fromDate: DateTime(2026),
        toDate: DateTime(2026, 10, 21),
        pageCount: 12,
        creditsBefore: 2,
      );
      expect((await pairing.couple.get()).data()!['bookCredits'], 1);
      final book = await pairing.couple.collection('books').doc('b1').get();
      expect(book.data()!.keys.toSet(), {
        'createdBy',
        'title',
        'fromDate',
        'toDate',
        'pageCount',
        'storagePath',
        'createdAt',
      });
      expect(book.data()!['storagePath'], 'couples/c1/books/b1.pdf');
    });

    test('no credit, no book', () async {
      expect(
        () => rig.books.saveBook(
          coupleId: pCouple,
          bookId: 'b1',
          uid: pAsha,
          title: 't',
          fromDate: DateTime(2026),
          toDate: DateTime(2026),
          pageCount: 1,
          creditsBefore: 0,
        ),
        throwsA(isA<BookException>()),
      );
    });
  });

  group('screens', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(pAsha),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: PairingReady(
              uid: pAsha,
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        Navigator.of(context).push(BookBuilderScreen.route()),
                    child: const Text('build'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('build'));
      await tester.pumpAndSettle();
    }

    /// Lets the book be made: pdf saves in its own isolate, which needs
    /// real time, not the test's fake clock.
    Future<void> run(WidgetTester tester) async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
    }

    Future<void> tapMake(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        find.byKey(const Key('book-make')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('book-make')));
    }

    testWidgets('defaults, summary and a free preview', (tester) async {
      await pump(tester);
      final title = tester.widget<TextField>(
        find.byKey(const Key('book-title')),
      );
      expect(title.controller!.text, 'Asha & Ravi · 2026');
      expect(find.text('3 memories'), findsOneWidget);
      expect(find.text('4 photos'), findsOneWidget);
      expect(find.text('1 love note'), findsOneWidget);
      expect(
        find.text('Private, your chat and unopened notes are never included.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('book-preview')));
      await run(tester);
      expect(find.textContaining('PDF Preview'), findsOneWidget);
    });

    testWidgets('no credit: the button buys one', (tester) async {
      await pump(tester);
      expect(find.text('Get this book · ₹199.00'), findsOneWidget);
      await tapMake(tester);
      await tester.pump();
      expect(rig.billing.bought, [Products.bookSingle]);
      expect((await pairing.couple.collection('books').get()).docs, isEmpty);
    });

    testWidgets('with a credit: made, uploaded, then one credit spent', (
      tester,
    ) async {
      await pairing.couple.update({'bookCredits': 1});
      await pump(tester);
      expect(find.text('Make our book'), findsOneWidget);
      await tapMake(tester);
      await run(tester);

      final books = await pairing.couple.collection('books').get();
      expect(books.docs, hasLength(1));
      final path = books.docs.single.data()['storagePath'] as String;
      expect(rig.files.files[path], isNotNull);
      expect(
        pdfPages(rig.files.files[path]!),
        books.docs.single.data()['pageCount'],
      );
      expect((await pairing.couple.get()).data()!['bookCredits'], 0);
      expect(find.textContaining('PDF Asha & Ravi · 2026'), findsOneWidget);
    });

    testWidgets('upload fails: nothing spent, save again later', (
      tester,
    ) async {
      await pairing.couple.update({'bookCredits': 1});
      rig.files.failUploads = 1;
      await pump(tester);
      await tapMake(tester);
      await run(tester);

      expect(find.byKey(const Key('book-unsaved')), findsOneWidget);
      expect((await pairing.couple.get()).data()!['bookCredits'], 1);
      expect((await pairing.couple.collection('books').get()).docs, isEmpty);
      final fetched = rig.images.fetched.length;

      await tester.tap(find.byKey(const Key('book-save-again')));
      await run(tester);
      expect((await pairing.couple.get()).data()!['bookCredits'], 0);
      expect(
        (await pairing.couple.collection('books').get()).docs,
        hasLength(1),
      );
      // Saved as it was made: nothing fetched or made again.
      expect(rig.images.fetched.length, fetched);
    });

    testWidgets('books list: rename and delete', (tester) async {
      await pairing.couple.update({'bookCredits': 1});
      rig.files.files['couples/c1/books/b1.pdf'] = Uint8List(3);
      await rig.books.saveBook(
        coupleId: pCouple,
        bookId: 'b1',
        uid: pAsha,
        title: 'Our 2026',
        fromDate: DateTime(2026),
        toDate: DateTime(2026, 10, 21),
        pageCount: 14,
        creditsBefore: 1,
      );
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: rig.overrides(pAsha),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PairingReady(uid: pAsha, child: MemoryBooksScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Our 2026'), findsOneWidget);
      expect(find.text('Jan – Oct 2026 · 14 pages'), findsOneWidget);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Our best year');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Our best year'), findsOneWidget);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect((await pairing.couple.collection('books').get()).docs, isEmpty);
      expect(rig.files.files, isEmpty);
    });
  });
}
