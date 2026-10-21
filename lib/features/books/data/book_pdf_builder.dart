import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:couple_app/features/books/models/book.dart';

/// Thrown when a book is cancelled while it is being made.
class BookCancelled implements Exception {
  const BookCancelled();
}

/// Lets the screen stop a book half way.
class BookCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// The fonts embedded in every book (see `assets/fonts/book/README.txt`).
class BookFonts {
  const BookFonts({
    required this.serif,
    required this.serifItalic,
    required this.serifBoldItalic,
    required this.sans,
    required this.sansMedium,
  });

  final pw.Font serif;
  final pw.Font serifItalic;
  final pw.Font serifBoldItalic;
  final pw.Font sans;
  final pw.Font sansMedium;

  static Future<BookFonts> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    Future<pw.Font> font(String name) async =>
        pw.Font.ttf(await b.load('assets/fonts/book/$name.ttf'));
    return BookFonts(
      serif: await font('NotoSerif-Regular'),
      serifItalic: await font('NotoSerif-Italic'),
      serifBoldItalic: await font('NotoSerif-BoldItalic'),
      sans: await font('Roboto-Regular'),
      sansMedium: await font('Roboto-Medium'),
    );
  }
}

/// One planned page of a book.
sealed class BookPageSpec {
  const BookPageSpec();
}

class CoverPageSpec extends BookPageSpec {
  const CoverPageSpec();
}

class ContentsPageSpec extends BookPageSpec {
  const ContentsPageSpec();
}

/// A memory with its photos (one or two on this page).
class MemoryPageSpec extends BookPageSpec {
  const MemoryPageSpec({
    required this.month,
    required this.memory,
    required this.photos,
    required this.monthStart,
    required this.firstPart,
    this.milestones = const [],
  });

  final DateTime month;
  final BookMemory memory;
  final List<BookPhoto> photos;
  final bool monthStart;

  /// A month's few milestones, shown small above the memory rather than
  /// alone on a page.
  final List<BookMilestone> milestones;

  /// The first page of this memory (with its caption).
  final bool firstPart;
}

/// Notes, dates and milestones (and memories without photos).
class MomentsPageSpec extends BookPageSpec {
  const MomentsPageSpec({
    required this.month,
    required this.entries,
    required this.monthStart,
  });

  final DateTime month;
  final List<BookEntry> entries;
  final bool monthStart;
}

class NumbersPageSpec extends BookPageSpec {
  const NumbersPageSpec();
}

class ClosingPageSpec extends BookPageSpec {
  const ClosingPageSpec();
}

/// Turns [BookContent] into an A5 PDF in the app's romantic look: soft
/// blush and lavender pages, serif headings, rounded photos (one or two a
/// page), a contents page, a numbers page and a closing line.
///
/// Pages are laid out first ([plan]), so the contents page knows where
/// each month starts and the progress can say "12 of 34 pages".
class BookPdfBuilder {
  BookPdfBuilder(this.fonts);

  final BookFonts fonts;

  static final format = PdfPageFormat.a5;

  /// Pages a free preview shows.
  static const previewPages = 3;

  // The app's palette, for paper.
  static const _ink = PdfColor.fromInt(0xFF3B1424);
  static const _muted = PdfColor.fromInt(0xFF7A5866);
  static const _blush = PdfColor.fromInt(0xFFC2185B);
  static const _lavender = PdfColor.fromInt(0xFF6A3FC4);
  static const _blushTint = [
    PdfColor.fromInt(0xFFFFF5F8),
    PdfColor.fromInt(0xFFFDEFF6),
  ];
  static const _lavenderTint = [
    PdfColor.fromInt(0xFFF7F3FF),
    PdfColor.fromInt(0xFFFBF1FA),
  ];

  /// Lays out every page.
  static List<BookPageSpec> plan(BookContent content) {
    final pages = <BookPageSpec>[
      const CoverPageSpec(),
      const ContentsPageSpec(),
    ];
    for (final month in content.months) {
      var monthStart = true;
      final pendingText = <BookEntry>[];
      void flushText() {
        // The month's heading takes about one entry's room.
        for (final group in _groupText(pendingText, first: monthStart)) {
          pages.add(
            MomentsPageSpec(
              month: month.month,
              entries: group,
              monthStart: monthStart,
            ),
          );
          monthStart = false;
        }
        pendingText.clear();
      }

      // The month's notes, dates and milestones open the chapter together;
      // then each memory with photos gets its own page or two.
      final text = month.entries
          .where((e) => e is! BookMemory || e.photos.isEmpty)
          .toList();
      final photoMemories = month.memories
          .where((m) => m.photos.isNotEmpty)
          .toList();
      // Just a milestone or two, and photos to come: they ride along on
      // the first photo page instead of taking a page of their own.
      final carried =
          photoMemories.isNotEmpty &&
              text.isNotEmpty &&
              text.length <= 2 &&
              text.every((e) => e is BookMilestone)
          ? text.cast<BookMilestone>()
          : const <BookMilestone>[];
      if (carried.isEmpty) {
        pendingText.addAll(text);
        flushText();
      }
      for (final memory in photoMemories) {
        for (var i = 0; i < memory.photos.length; i += 2) {
          pages.add(
            MemoryPageSpec(
              month: month.month,
              memory: memory,
              photos: memory.photos.skip(i).take(2).toList(),
              monthStart: monthStart,
              firstPart: i == 0,
              milestones: monthStart ? carried : const [],
            ),
          );
          monthStart = false;
        }
      }
    }
    pages
      ..add(const NumbersPageSpec())
      ..add(const ClosingPageSpec());
    return pages;
  }

  /// How much of a page a text entry takes (a page holds about 5.5).
  static double _weight(BookEntry e) => switch (e) {
    BookNote(:final body) => 1 + body.length / 330,
    BookDatePlan(:final reflection) => .9 + reflection.length / 330,
    BookMemory(:final caption) => .9 + caption.length / 330,
    BookMilestone() => .55,
  };

  static List<List<BookEntry>> _groupText(
    List<BookEntry> entries, {
    bool first = false,
  }) {
    const capacity = 5.5;
    final groups = <List<BookEntry>>[];
    var current = <BookEntry>[];
    var used = first ? 1.0 : 0.0;
    for (final e in entries) {
      final w = _weight(e).clamp(.5, capacity);
      if (current.isNotEmpty && used + w > capacity) {
        groups.add(current);
        current = [];
        used = 0;
      }
      current.add(e);
      used += w;
    }
    if (current.isNotEmpty) groups.add(current);
    return groups;
  }

  /// The month each chapter starts on, with its page number.
  static List<({DateTime month, int page})> chapters(List<BookPageSpec> pages) {
    final list = <({DateTime month, int page})>[];
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      final start = switch (p) {
        MemoryPageSpec(:final monthStart, :final month) when monthStart =>
          month,
        MomentsPageSpec(:final monthStart, :final month) when monthStart =>
          month,
        _ => null,
      };
      if (start != null) list.add((month: start, page: i + 1));
    }
    return list;
  }

  /// Makes the PDF. With [preview], only the first [previewPages] pages,
  /// each marked "Preview". [onPage] reports pages done of the total.
  Future<Uint8List> build(
    BookContent content, {
    bool preview = false,
    void Function(int done, int total)? onPage,
    BookCancelToken? cancel,
  }) async {
    final all = plan(content);
    final pages = preview ? all.take(previewPages).toList() : all;
    final toc = chapters(all);
    final doc = pw.Document(
      title: content.title,
      author: content.names,
      creator: 'Us',
      subject: preview ? 'Preview' : 'Memory book',
    );

    for (var i = 0; i < pages.length; i++) {
      if (cancel?.isCancelled ?? false) throw const BookCancelled();
      final spec = pages[i];
      final number = i + 1;
      doc.addPage(
        pw.Page(
          pageFormat: format,
          margin: pw.EdgeInsets.zero,
          build: (_) => _page(
            content,
            spec,
            number: number,
            toc: toc,
            preview: preview,
            tint: i.isEven ? _blushTint : _lavenderTint,
          ),
        ),
      );
      onPage?.call(i + 1, pages.length);
      // Let the screen draw the progress between pages.
      await Future<void>.delayed(Duration.zero);
    }
    if (cancel?.isCancelled ?? false) throw const BookCancelled();
    return doc.save();
  }

  // ---- Pages -------------------------------------------------------------

  pw.Widget _page(
    BookContent content,
    BookPageSpec spec, {
    required int number,
    required List<({DateTime month, int page})> toc,
    required bool preview,
    required List<PdfColor> tint,
  }) {
    final body = switch (spec) {
      CoverPageSpec() => _cover(content),
      ContentsPageSpec() => _contents(toc),
      MemoryPageSpec() => _memoryPage(spec),
      MomentsPageSpec() => _momentsPage(spec),
      NumbersPageSpec() => _numbers(content.numbers),
      ClosingPageSpec() => _closing(content),
    };
    final isCover = spec is CoverPageSpec;
    return pw.Stack(
      children: [
        pw.Positioned.fill(
          child: pw.Container(
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                begin: pw.Alignment.topLeft,
                end: pw.Alignment.bottomRight,
                colors: isCover
                    ? const [
                        PdfColor.fromInt(0xFFFFE4EC),
                        PdfColor.fromInt(0xFFEFE4FF),
                        PdfColor.fromInt(0xFFFBD5EA),
                      ]
                    : tint,
              ),
            ),
          ),
        ),
        pw.Positioned.fill(
          child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(34, 36, 34, 40),
            child: body,
          ),
        ),
        if (!isCover)
          pw.Positioned(
            left: 0,
            right: 0,
            bottom: 18,
            child: pw.Center(
              child: pw.Text(
                '$number',
                style: pw.TextStyle(
                  font: fonts.sans,
                  fontSize: 8,
                  color: _muted,
                ),
              ),
            ),
          ),
        if (preview)
          pw.Positioned.fill(
            child: pw.Center(
              child: pw.Transform.rotate(
                angle: .62,
                child: pw.Opacity(
                  opacity: .16,
                  child: pw.Text(
                    'Preview',
                    style: pw.TextStyle(
                      font: fonts.serifBoldItalic,
                      fontSize: 92,
                      color: _blush,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  pw.TextStyle _serif(double size, {pw.Font? font, PdfColor color = _ink}) =>
      pw.TextStyle(font: font ?? fonts.serif, fontSize: size, color: color);

  pw.TextStyle _sans(
    double size, {
    bool medium = false,
    PdfColor color = _muted,
  }) => pw.TextStyle(
    font: medium ? fonts.sansMedium : fonts.sans,
    fontSize: size,
    color: color,
    letterSpacing: medium ? .6 : 0,
  );

  static String _monthName(DateTime d) => DateFormat('MMMM y').format(d);
  static String _day(DateTime d) => DateFormat('d MMMM y').format(d);

  pw.Widget _cover(BookContent c) {
    final photo = c.coverImage;
    final pw.Widget art;
    if (photo != null) {
      art = _circle(photo, 170);
    } else if (c.avatarImages.isNotEmpty) {
      art = pw.SizedBox(
        width: 230,
        height: 130,
        child: pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            for (final (i, a) in c.avatarImages.take(2).indexed)
              pw.Positioned(
                left: c.avatarImages.length == 1 ? 50 : i * 100.0,
                child: _circle(a, 130),
              ),
          ],
        ),
      );
    } else {
      art = _heart(90, _blush);
    }

    final start = c.startDate;
    final days = c.numbers.daysTogether;
    final since = start == null
        ? null
        : 'Together since ${_day(start)}'
              '${days == null ? '' : ' · ${NumberFormat.decimalPattern().format(days)} days'}';

    return pw.Column(
      children: [
        pw.SizedBox(height: 26),
        pw.Text(
          'OUR MEMORY BOOK',
          style: _sans(9, medium: true, color: _blush),
        ),
        pw.Spacer(),
        art,
        pw.SizedBox(height: 30),
        pw.Text(
          printable(c.title),
          textAlign: pw.TextAlign.center,
          style: _serif(30, font: fonts.serifBoldItalic),
        ),
        pw.SizedBox(height: 10),
        if (!c.title.contains(c.names))
          pw.Text(
            printable(c.names),
            style: _serif(14, font: fonts.serifItalic, color: _muted),
          ),
        if (since != null) ...[
          pw.SizedBox(height: 16),
          pw.Text(since, style: _sans(9.5)),
        ],
        pw.Spacer(),
        pw.Text(
          '${DateFormat('MMMM y').format(c.from)} – '
          '${DateFormat('MMMM y').format(c.to)}',
          style: _sans(8.5, medium: true, color: _lavender),
        ),
        pw.SizedBox(height: 8),
      ],
    );
  }

  pw.Widget _circle(Uint8List bytes, double size) => pw.Container(
    width: size,
    height: size,
    padding: const pw.EdgeInsets.all(4),
    decoration: const pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      color: PdfColors.white,
    ),
    child: pw.ClipOval(
      child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
    ),
  );

  pw.Widget _heading(String text, {double size = 26}) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(text, style: _serif(size, font: fonts.serifBoldItalic)),
      pw.SizedBox(height: 6),
      pw.Container(
        width: 60,
        height: 2,
        decoration: const pw.BoxDecoration(
          gradient: pw.LinearGradient(colors: [_blush, _lavender]),
        ),
      ),
      pw.SizedBox(height: 18),
    ],
  );

  pw.Widget _contents(List<({DateTime month, int page})> toc) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _heading('Contents'),
        if (toc.isEmpty)
          pw.Text(
            'Your first chapter is still being written.',
            style: _serif(12),
          ),
        for (final t in toc.take(24))
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Row(
              children: [
                pw.Text(_monthName(t.month), style: _serif(12.5)),
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.symmetric(horizontal: 8),
                    height: 1,
                    color: const PdfColor.fromInt(0x337A5866),
                  ),
                ),
                pw.Text(
                  '${t.page}',
                  style: _sans(10, medium: true, color: _blush),
                ),
              ],
            ),
          ),
      ],
    );
  }

  pw.Widget _monthHeader(DateTime month) => _heading(_monthName(month));

  pw.Widget _memoryPage(MemoryPageSpec spec) {
    final m = spec.memory;
    final meta = [_day(m.date), ?m.place].map(printable).join('  ·  ');
    final photos = [
      for (final p in spec.photos)
        if (p.bytes != null) p.bytes!,
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (spec.monthStart) _monthHeader(spec.month),
        for (final milestone in spec.milestones)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 8),
            padding: const pw.EdgeInsets.fromLTRB(12, 7, 12, 7),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'MILESTONE',
                  style: _sans(6.5, medium: true, color: _blush),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Text(
                    printable(milestone.title),
                    style: _serif(10.5, font: fonts.serifBoldItalic),
                  ),
                ),
                pw.Text(
                  DateFormat('d MMM').format(milestone.date),
                  style: _sans(8),
                ),
              ],
            ),
          ),
        if (spec.milestones.isNotEmpty) pw.SizedBox(height: 6),
        pw.Text(
          printable(spec.firstPart ? m.title : '${m.title} (continued)'),
          style: _serif(17, font: fonts.serifBoldItalic),
        ),
        pw.SizedBox(height: 3),
        pw.Text(meta, style: _sans(8.5)),
        pw.SizedBox(height: 12),
        pw.Expanded(
          child: photos.isEmpty
              ? pw.Center(child: _heart(40, _lavender))
              : pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, bytes) in photos.indexed) ...[
                      if (i > 0) pw.SizedBox(height: 10),
                      pw.Expanded(
                        child: pw.ClipRRect(
                          horizontalRadius: 14,
                          verticalRadius: 14,
                          child: pw.Image(
                            pw.MemoryImage(bytes),
                            fit: pw.BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        if (spec.firstPart && m.caption.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            _clip(m.caption, 320),
            style: _serif(10.5, font: fonts.serifItalic, color: _ink),
          ),
        ],
      ],
    );
  }

  pw.Widget _momentsPage(MomentsPageSpec spec) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (spec.monthStart) _monthHeader(spec.month),
        for (final e in spec.entries)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: _moment(e),
          ),
      ],
    );
  }

  pw.Widget _moment(BookEntry e) {
    final (label, color, title, body, meta) = switch (e) {
      BookNote() => (
        'LOVE NOTE FROM ${e.fromName.toUpperCase()}',
        _blush,
        e.title,
        _clip(e.body, 900),
        _day(e.date),
      ),
      BookDatePlan() => (
        'DATE',
        _lavender,
        e.title,
        e.reflection,
        [
          _day(e.date),
          ?e.place,
          if (e.rating != null) '${e.rating}/5',
        ].join('  ·  '),
      ),
      BookMilestone() => ('MILESTONE', _blush, e.title, '', _day(e.date)),
      BookMemory() => (
        'MEMORY',
        _lavender,
        e.title,
        e.caption,
        [_day(e.date), ?e.place].join('  ·  '),
      ),
    };
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(14, 11, 14, 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14),
        border: pw.Border.all(color: const PdfColor.fromInt(0x22C2185B)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            printable(label),
            style: _sans(7, medium: true, color: color),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            printable(title),
            style: _serif(13, font: fonts.serifBoldItalic),
          ),
          pw.SizedBox(height: 2),
          pw.Text(printable(meta), style: _sans(8)),
          if (printable(body).isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              printable(body),
              style: pw.TextStyle(
                font: e is BookNote ? fonts.serifItalic : fonts.serif,
                fontSize: 10,
                color: _ink,
                lineSpacing: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  pw.Widget _numbers(BookNumbers n) {
    final format = NumberFormat.decimalPattern();
    final stats = [
      if (n.daysTogether != null)
        (format.format(n.daysTogether), 'days together'),
      (format.format(n.memories), n.memories == 1 ? 'memory' : 'memories'),
      (format.format(n.notes), n.notes == 1 ? 'love note' : 'love notes'),
      (format.format(n.gamesPlayed), 'games played'),
      (format.format(n.songsSaved), 'songs saved'),
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _heading('Our numbers'),
        pw.Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (i, (value, label)) in stats.indexed)
              pw.Container(
                width: (_contentWidth - 12) / 2,
                padding: const pw.EdgeInsets.fromLTRB(14, 16, 14, 16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(16),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      value,
                      style: _serif(
                        26,
                        font: fonts.serifBoldItalic,
                        color: i.isEven ? _blush : _lavender,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(label, style: _sans(9)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The content width of a page.
  static final _contentWidth = format.width - 68;

  pw.Widget _closing(BookContent c) {
    return pw.Column(
      children: [
        pw.Spacer(),
        _heart(56, _blush),
        pw.SizedBox(height: 26),
        pw.Text(
          c.closingLine,
          textAlign: pw.TextAlign.center,
          style: _serif(19, font: fonts.serifBoldItalic),
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          printable(c.names),
          style: _serif(12, font: fonts.serifItalic, color: _muted),
        ),
        pw.Spacer(),
        pw.Text('Made with love in Us', style: _sans(7.5)),
      ],
    );
  }

  /// A heart drawn as a path (no font has one we can rely on).
  pw.Widget _heart(double size, PdfColor color) => pw.SizedBox(
    width: size,
    height: size * .9,
    child: pw.CustomPaint(
      painter: (canvas, s) {
        final w = s.x, h = s.y;
        canvas
          ..setFillColor(color)
          ..moveTo(w * .5, 0)
          ..curveTo(w * .42, h * .12, 0, h * .36, 0, h * .66)
          ..curveTo(0, h * .92, w * .3, h * 1.04, w * .5, h * .8)
          ..curveTo(w * .7, h * 1.04, w, h * .92, w, h * .66)
          ..curveTo(w, h * .36, w * .58, h * .12, w * .5, 0)
          ..closePath()
          ..fillPath();
      },
    ),
  );

  static String _clip(String text, int max) {
    final t = printable(text);
    return t.length <= max ? t : '${t.substring(0, max).trimRight()}…';
  }

  /// [text] without what the book's fonts can't draw (emoji and other
  /// symbols), so nothing prints as an empty box.
  static String printable(String text) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      final emoji =
          rune >= 0x1F000 ||
          (rune >= 0x2600 && rune <= 0x27BF) ||
          (rune >= 0x2B00 && rune <= 0x2BFF) ||
          rune == 0xFE0F ||
          rune == 0x200D ||
          (rune >= 0xE000 && rune <= 0xF8FF);
      if (!emoji) out.writeCharCode(rune);
    }
    return out.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }
}
