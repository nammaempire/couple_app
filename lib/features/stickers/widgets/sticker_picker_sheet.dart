import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/providers/avatar_providers.dart';
import 'package:couple_app/features/avatar/screens/avatar_builder_screen.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/chat/widgets/chat_chrome.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';
import 'package:couple_app/features/stickers/data/sticker_catalog.dart';
import 'package:couple_app/features/stickers/data/sticker_quotes.dart';
import 'package:couple_app/features/stickers/models/sticker_category.dart';
import 'package:couple_app/features/stickers/models/sticker_quote.dart';
import 'package:couple_app/features/stickers/models/sticker_scene.dart';
import 'package:couple_app/features/stickers/widgets/couple_sticker_view.dart';

/// Tall bottom sheet for sending a couple sticker.
///
/// First pick a category and a scene (previews use both partners' real
/// avatars), then pick, shuffle or write the quote and send. Sends with
/// [replyTo] and pops `true` once sent, so the chat can clear its reply.
class StickerPickerSheet extends ConsumerStatefulWidget {
  const StickerPickerSheet({super.key, this.replyTo});

  final ReplyPreview? replyTo;

  @override
  ConsumerState<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends ConsumerState<StickerPickerSheet> {
  late final ChatService _chat;
  late final String _coupleId;
  late final String _myUid;

  final _random = math.Random();
  final _ownLine = TextEditingController();
  final _ownLineFocus = FocusNode();

  StickerCategory _category = StickerCategory.values.first;

  /// Null while browsing the grid; set once a scene is chosen.
  StickerScene? _scene;
  late StickerQuote _quote;

  /// Whether the typed line, rather than [_quote], goes on the sticker.
  bool _useOwnLine = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _chat = ref.read(chatServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    _ownLineFocus.addListener(_onOwnLineFocus);
  }

  @override
  void dispose() {
    _ownLineFocus
      ..removeListener(_onOwnLineFocus)
      ..dispose();
    _ownLine.dispose();
    super.dispose();
  }

  /// Rebuilds to switch the compose layout while writing a line.
  void _onOwnLineFocus() {
    if (mounted) setState(() {});
  }

  List<StickerQuote> get _quotes => StickerQuotes.forCategory(_category);

  String get _text => _useOwnLine && _ownLine.text.trim().isNotEmpty
      ? _ownLine.text.trim()
      : _quote.text;

  void _pickCategory(StickerCategory category) {
    if (category == _category) return;
    HapticFeedback.selectionClick();
    setState(() => _category = category);
  }

  void _pickScene(StickerScene scene) {
    HapticFeedback.selectionClick();
    setState(() {
      _scene = scene;
      _quote = StickerCatalog.defaultQuote(scene);
      _useOwnLine = false;
      _ownLine.clear();
    });
  }

  void _pickQuote(StickerQuote quote) {
    FocusScope.of(context).unfocus();
    setState(() {
      _quote = quote;
      _useOwnLine = false;
    });
  }

  /// Moves through the category's quotes, wrapping at either end.
  void _stepQuote(int by) {
    final quotes = _quotes;
    final index = quotes.indexWhere((q) => q.id == _quote.id);
    _pickQuote(quotes[(index + by) % quotes.length]);
  }

  void _shuffleQuote() {
    final others = _quotes.where((q) => q.id != _quote.id).toList();
    if (others.isEmpty) return;
    HapticFeedback.selectionClick();
    _pickQuote(others[_random.nextInt(others.length)]);
  }

  Future<void> _openAvatarBuilder() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AvatarBuilderScreen()),
    );
  }

  Future<void> _send() async {
    final scene = _scene;
    if (scene == null || _sending) return;
    final quote = _text.trim();
    if (quote.isEmpty) return;

    setState(() => _sending = true);
    try {
      await _chat.sendSticker(
        coupleId: _coupleId,
        senderId: _myUid,
        stickerId: scene.id,
        category: scene.category.id,
        quote: quote,
        replyTo: widget.replyTo,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      context.showSnackMessage('Sticker not sent. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final mine = ref.watch(myAvatarProvider);
    final theirs = ref.watch(partnerAvatarProvider);
    final keyboard = media.viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Tall, but never taller than the room left above the keyboard
          // (and below the sheet's drag handle).
          final room = math.max(0.0, constraints.maxHeight);
          final height = math.min(media.size.height * .9, room);
          // The gradient handle is dropped when there's very little room.
          final handle = height > 260;
          final body = height - (handle ? 31 : 0);
          return SizedBox(
            height: height,
            child: Column(
              children: [
                if (handle) const ChatSheetHeader(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _scene == null
                        ? _buildBrowse(mine, theirs)
                        : _buildCompose(_scene!, mine, theirs, height: body),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---- Browse: categories and scenes ------------------------------------

  Widget _buildBrowse(AvatarConfig? mine, AvatarConfig? theirs) {
    final theme = Theme.of(context);
    final scenes = StickerCatalog.forCategory(_category);

    return Column(
      key: const ValueKey('browse'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
          child: Row(
            children: [
              const GradientBadge(icon: Icons.favorite, size: 34, iconSize: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Couple stickers',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        if (mine == null)
          _AvatarBanner(onTap: _openAvatarBuilder)
        else
          const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final category in StickerCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('sticker-category-${category.id}'),
                      avatar: Text(category.emoji),
                      label: Text(category.label),
                      showCheckmark: false,
                      shape: const StadiumBorder(),
                      selectedColor: theme.colorScheme.primaryContainer,
                      backgroundColor: theme.colorScheme.surface.withValues(
                        alpha: .7,
                      ),
                      side: BorderSide(
                        color: category == _category
                            ? theme.colorScheme.primary.withValues(alpha: .5)
                            : theme.colorScheme.outlineVariant,
                      ),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: category == _category
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                      selected: category == _category,
                      onSelected: (_) => _pickCategory(category),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              const side = 16.0;
              final tile = (constraints.maxWidth - side * 2 - gap) / 2;
              // One row height for the whole grid: the tallest card.
              var extent = 0.0;
              for (final scene in scenes) {
                extent = math.max(
                  extent,
                  CoupleStickerView.heightFor(
                    context,
                    quote: StickerCatalog.defaultQuote(scene).text,
                    width: tile,
                  ),
                );
              }
              return GridView.builder(
                key: ValueKey('scenes-${_category.id}'),
                padding: const EdgeInsets.fromLTRB(side, 8, side, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  mainAxisExtent: extent.ceilToDouble() + 1,
                ),
                itemCount: scenes.length,
                itemBuilder: (context, index) {
                  final scene = scenes[index];
                  return Align(
                    alignment: Alignment.topCenter,
                    // Never overflows a cell, even if a font measures
                    // differently than the estimate.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: _SceneTile(
                        key: ValueKey('sticker-scene-${scene.id}'),
                        scene: scene,
                        mine: mine,
                        theirs: theirs,
                        width: tile,
                        onTap: () => _pickScene(scene),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ---- Compose: preview, quote, send ------------------------------------

  Widget _buildCompose(
    StickerScene scene,
    AvatarConfig? mine,
    AvatarConfig? theirs, {
    required double height,
  }) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    // While writing a line, the quote list makes way so the field, the
    // preview and Send all fit above the keyboard.
    final writing = _ownLineFocus.hasFocus || media.viewInsets.bottom > 0;
    // Very little room (e.g. landscape with the keyboard up): drop the
    // header. In landscape, Send sits beside the field.
    final cramped = writing && height < 220;
    final sideBySide = media.size.width > media.size.height;

    final sendButton = FilledButton.icon(
      key: const ValueKey('sticker-send'),
      style: sideBySide
          ? FilledButton.styleFrom(minimumSize: const Size(0, 48))
          : null,
      onPressed: _sending ? null : _send,
      icon: _sending
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.send_rounded),
      label: const Text('Send sticker'),
    );

    final ownLineField = TextField(
      key: const ValueKey('sticker-own-line'),
      controller: _ownLine,
      focusNode: _ownLineFocus,
      // Tapping away brings the quote lines back.
      onTapOutside: (_) => _ownLineFocus.unfocus(),
      maxLength: ChatService.maxStickerQuoteLength,
      // The counter only shows when there's room, or near the limit.
      buildCounter:
          (
            context, {
            required currentLength,
            required isFocused,
            required maxLength,
          }) {
            final near = maxLength != null && currentLength >= maxLength - 15;
            if (cramped && !near) return null;
            return Text('$currentLength/$maxLength');
          },
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        hintText: 'Write my own',
        prefixIcon: Icon(Icons.edit_outlined),
      ),
      onChanged: (value) =>
          setState(() => _useOwnLine = value.trim().isNotEmpty),
    );

    return Column(
      key: const ValueKey('compose'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!cramped)
          Padding(
            key: const ValueKey('compose-header'),
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to stickers',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _scene = null),
                ),
                Expanded(
                  child: Text(
                    '${scene.category.emoji}  ${scene.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          key: const ValueKey('compose-body'),
          child: writing
              ? _buildWritingPreview(scene, mine, theirs)
              : _buildQuotePicker(scene, mine, theirs),
        ),
        // Keyed so the field keeps its element (and focus) when the layout
        // around it changes.
        SafeArea(
          key: const ValueKey('compose-footer'),
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, cramped ? 6 : 12),
            child: Flex(
              direction: sideBySide ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: sideBySide
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(flex: sideBySide ? 1 : 0, child: ownLineField),
                const SizedBox(width: 8, height: 4),
                sendButton,
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Just the preview, as large as the room left while writing allows.
  Widget _buildWritingPreview(
    StickerScene scene,
    AvatarConfig? mine,
    AvatarConfig? theirs,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Too small to read: leave the room to the field.
        if (constraints.maxHeight < 48) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: CoupleStickerView(
                scene: scene,
                sender: mine,
                partner: theirs,
                quote: _text,
                width: math.min(250.0, constraints.maxWidth - 32),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The preview pinned above the quote lines, which scroll beneath it.
  Widget _buildQuotePicker(
    StickerScene scene,
    AvatarConfig? mine,
    AvatarConfig? theirs,
  ) {
    final theme = Theme.of(context);
    final quotes = _quotes;

    final navRow = Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('sticker-prev-quote'),
            tooltip: 'Previous quote',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _stepQuote(-1),
          ),
          Flexible(
            child: FilledButton.tonalIcon(
              key: const ValueKey('sticker-shuffle'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: _shuffleQuote,
              icon: const Icon(Icons.shuffle, size: 18),
              label: const Text(
                'Shuffle quote',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('sticker-next-quote'),
            tooltip: 'Next quote',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _stepQuote(1),
          ),
        ],
      ),
    );
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
          child: Text(
            'Pick a line, or write your own below',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final quote in quotes)
          _QuoteOption(
            key: ValueKey('sticker-quote-${quote.id}'),
            quote: quote,
            selected: !_useOwnLine && quote.id == _quote.id,
            onTap: () => _pickQuote(quote),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Short and wide (landscape): the preview sits beside the lines.
        if (constraints.maxWidth > constraints.maxHeight * 2.2) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 0, 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: CoupleStickerView(
                    scene: scene,
                    sender: mine,
                    partner: theirs,
                    quote: _text,
                    width: math.min(250.0, constraints.maxWidth * .38),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    navRow,
                    Expanded(child: list),
                  ],
                ),
              ),
            ],
          );
        }

        // It shrinks when there's little room.
        final previewWidth = math.max(
          120.0,
          math.min(
            math.min(250.0, constraints.maxWidth - 80),
            constraints.maxHeight * .48,
          ),
        );
        return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .6,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: CoupleStickerView(
                  scene: scene,
                  sender: mine,
                  partner: theirs,
                  quote: _text,
                  width: previewWidth,
                ),
              ),
            ),
            navRow,
            Expanded(child: list),
          ],
        );
      },
    );
  }
}

/// Invites me to make my avatar, so stickers look like me.
class _AvatarBanner extends StatelessWidget {
  const _AvatarBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = ChatPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: ChatPalette.diagonal(palette.headerGradient),
            border: Border.all(color: scheme.primary.withValues(alpha: .25)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: InkWell(
            key: const ValueKey('sticker-make-avatar'),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  const GradientBadge(
                    icon: Icons.face_retouching_natural,
                    size: 34,
                    iconSize: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Make your avatar so stickers look like you',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurface),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A scene preview in the grid, with its default quote.
class _SceneTile extends StatelessWidget {
  const _SceneTile({
    super.key,
    required this.scene,
    required this.mine,
    required this.theirs,
    required this.width,
    required this.onTap,
  });

  final StickerScene scene;
  final AvatarConfig? mine;
  final AvatarConfig? theirs;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: scene.label,
      child: GestureDetector(
        onTap: onTap,
        child: CoupleStickerView(
          scene: scene,
          sender: mine,
          partner: theirs,
          quote: StickerCatalog.defaultQuote(scene).text,
          width: width,
        ),
      ),
    );
  }
}

/// One choosable quote line.
class _QuoteOption extends StatelessWidget {
  const _QuoteOption({
    super.key,
    required this.quote,
    required this.selected,
    required this.onTap,
  });

  final StickerQuote quote;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? scheme.primaryContainer
            : scheme.surface.withValues(alpha: .7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected
                ? scheme.primary.withValues(alpha: .55)
                : scheme.outlineVariant.withValues(alpha: .6),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    quote.text,
                    style: TextStyle(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  size: 20,
                  color: selected ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
