import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'package:couple_app/core/services/voice_playback.dart';
import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/calls/call_launcher.dart';
import 'package:couple_app/features/calls/models/call_session.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/chat_look.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_look_providers.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/chat/screens/chat_appearance_screen.dart';
import 'package:couple_app/features/chat/screens/chat_search_screen.dart';
import 'package:couple_app/features/chat/screens/media_gallery_screen.dart';
import 'package:couple_app/features/chat/widgets/call_log_tile.dart';
import 'package:couple_app/features/chat/widgets/chat_background_layer.dart';
import 'package:couple_app/features/chat/widgets/chat_date_divider.dart';
import 'package:couple_app/features/chat/widgets/chat_input.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';
import 'package:couple_app/features/chat/widgets/message_actions_sheet.dart';
import 'package:couple_app/features/chat/widgets/message_bubble.dart';
import 'package:couple_app/features/chat/widgets/pinned_message_bar.dart';
import 'package:couple_app/features/chat/widgets/pinned_messages_sheet.dart';
import 'package:couple_app/features/chat/widgets/upload_progress_bar.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/stickers/widgets/sticker_picker_sheet.dart';

enum _MenuAction { search, media, pinned, theme }

/// The conversation between the two partners.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.isActive = true});

  /// Whether the Chat tab is the one on screen. The shell keeps every tab
  /// alive, so without this, messages would be marked seen from Home.
  final bool isActive;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  static const _pageSize = 60;

  /// Jumping to a message pages back at most this far.
  static const _maxJumpPages = ChatService.searchWindow ~/ _pageSize + 1;

  late final ChatService _chat;
  late final String _coupleId;
  late final String _myUid;
  final _picker = ImagePicker();
  final _scroll = ScrollController();

  late final Stream<List<Message>> _pinnedStream = _chat.watchPinned(_coupleId);

  /// How many of the newest messages are loaded. Grows as the user scrolls
  /// back; Firestore keeps the whole window live.
  int _limit = _pageSize;
  late Stream<({List<Message> messages, bool fromCache})> _messagesStream =
      _chat.watchMessagePage(_coupleId, limit: _limit);

  List<Message> _loaded = const [];
  bool get _hasMore => _loaded.length >= _limit;
  bool _loadingMore = false;
  Completer<void>? _pageLoaded;

  /// False while the last requested page has only been answered from the
  /// device cache (or not at all), e.g. when offline.
  bool _pageConfirmed = true;

  /// Keys for message rows, so a message can be scrolled into view.
  final _rowKeys = <String, GlobalKey>{};

  double? _uploadProgress;
  String? _uploadLabel;

  Message? _replyingTo;
  String? _highlightId;
  Timer? _highlightTimer;

  /// Id of the newest message we have already run a seen-sweep for, so
  /// rebuilds don't trigger repeated Firestore reads.
  String? _lastSeenSweepId;

  /// The chat theme for the current look, rebuilt only when the app theme
  /// or the look changes.
  ({ThemeData base, ChatLook look, ThemeData theme})? _chatTheme;

  ThemeData _themeFor(ThemeData base, ChatLook look) {
    final cached = _chatTheme;
    if (cached != null && identical(cached.base, base) && cached.look == look) {
      return cached.theme;
    }
    final theme = ChatPalette.applyTo(base, look);
    _chatTheme = (base: base, look: look, theme: theme);
    return theme;
  }

  @override
  void initState() {
    super.initState();
    _chat = ref.read(chatServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    WidgetsBinding.instance.addObserver(this);
    _markSeen();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _markSeen();
    } else if (!widget.isActive && oldWidget.isActive) {
      // Leaving the Chat tab: don't keep a voice message playing.
      VoicePlayback.instance.stop();
      if (_replyingTo != null) setState(() => _replyingTo = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _markSeen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _highlightTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Marks the partner's messages read, but only while the chat is actually
  /// on screen and the app is in the foreground.
  void _markSeen() {
    // Null until the couple is complete.
    final partnerId = ref.read(coupleProvider).value?.partnerIdFor(_myUid);
    if (partnerId == null || !widget.isActive) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _chat
        .markSeen(coupleId: _coupleId, partnerId: partnerId)
        .catchError((_) {});
  }

  String _nameFor(String uid) =>
      uid == _myUid ? 'You' : ref.read(partnerNameProvider);

  // ---- Paging -------------------------------------------------------------

  void _loadMore() {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    _pageConfirmed = false;
    _pageLoaded = Completer<void>();
    setState(() {
      _limit += _pageSize;
      _messagesStream = _chat.watchMessagePage(_coupleId, limit: _limit);
    });
  }

  Future<void> _loadMoreAndWait() async {
    if (!_hasMore) return;
    _loadMore();
    await (_pageLoaded?.future ?? Future<void>.value()).timeout(
      const Duration(seconds: 8),
      // Offline or slow: give up on this page but let paging try again.
      onTimeout: _finishPage,
    );
  }

  void _finishPage() {
    _loadingMore = false;
    final pending = _pageLoaded;
    _pageLoaded = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Called from the list's builder with each result of the current query.
  void _onMessages(
    List<Message> messages, {
    required bool fromCache,
    required bool isCurrentQuery,
  }) {
    // Right after the limit grows, StreamBuilder replays the previous
    // query's result; ignore that for paging purposes.
    if (!isCurrentQuery) return;
    _loaded = messages;

    if (!_loadingMore) return;
    // A cache-only answer may be missing older messages the server has, so
    // only a short server answer means "no more".
    final pageFilled = messages.length >= _limit;
    if (pageFilled || !fromCache) {
      _pageConfirmed = true;
      _finishPage();
    }
  }

  // ---- Jumping to a message ----------------------------------------------

  /// Scrolls [messageId] into view and flashes it, loading older pages if
  /// needed. Used by search results, pins and reply quotes.
  Future<void> _jumpTo(String messageId) async {
    bool isLoaded() => _loaded.any((m) => m.id == messageId);

    for (
      var page = 0;
      page < _maxJumpPages && !isLoaded() && _hasMore;
      page++
    ) {
      await _loadMoreAndWait();
      if (!mounted) return;
    }
    if (!isLoaded()) {
      context.showSnackMessage(
        !_pageConfirmed
            ? 'Could not load older messages. Check your connection.'
            : _hasMore
            ? 'That message is too far back to jump to.'
            : 'That message is no longer in the conversation.',
      );
      return;
    }

    // Rows are built lazily, so walk up the list until the row exists.
    if (_scroll.hasClients && _rowKeys[messageId]?.currentContext == null) {
      _scroll.jumpTo(0);
      await WidgetsBinding.instance.endOfFrame;
    }
    for (var step = 0; step < 200; step++) {
      final rowContext = _rowKeys[messageId]?.currentContext;
      if (rowContext != null) {
        if (!rowContext.mounted) return;
        await Scrollable.ensureVisible(
          rowContext,
          alignment: .4,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        _flash(messageId);
        return;
      }
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels >= position.maxScrollExtent) return;
      _scroll.jumpTo(
        math.min(
          position.pixels + position.viewportDimension * .8,
          position.maxScrollExtent,
        ),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _flash(String messageId) {
    _highlightTimer?.cancel();
    setState(() => _highlightId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  // ---- Sending ------------------------------------------------------------

  ReplyPreview? _takeReply() {
    final reply = _replyingTo == null ? null : ReplyPreview.of(_replyingTo!);
    if (_replyingTo != null) setState(() => _replyingTo = null);
    return reply;
  }

  Future<void> _sendText(String text) async {
    final reply = _takeReply();
    try {
      await _chat.sendText(
        coupleId: _coupleId,
        senderId: _myUid,
        text: text,
        replyTo: reply,
      );
    } catch (e) {
      if (!mounted) return;
      context.showSnackMessage('Message not sent. Check your connection.');
    }
  }

  /// Runs an upload with the progress bar showing, mapping common failures
  /// to messages.
  Future<void> _upload(
    String label,
    Future<void> Function(void Function(double) onProgress) send,
  ) async {
    setState(() {
      _uploadProgress = 0;
      _uploadLabel = label;
    });
    try {
      await send((p) {
        if (mounted) setState(() => _uploadProgress = p);
      });
    } on ChatException catch (e) {
      if (!mounted) return;
      context.showSnackMessage(e.message);
    } on FirebaseException catch (e) {
      // Storage is optional: the app is usable for text before it is enabled.
      if (!mounted) return;
      context.showSnackMessage(
        e.plugin == 'firebase_storage'
            ? 'Sending media needs Firebase Storage enabled on this project.'
            : 'Could not send. Check your connection.',
      );
    } catch (e) {
      if (!mounted) return;
      context.showSnackMessage('Could not send. Check your connection.');
    } finally {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
          _uploadLabel = null;
        });
      }
    }
  }

  Future<void> _sendPhoto(ImageSource source) async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 2000,
      );
    } catch (e) {
      if (!mounted) return;
      context.showSnackMessage(
        'Could not open ${source == ImageSource.camera ? 'the camera' : 'your photos'}.',
      );
      return;
    }
    if (picked == null) return;

    final reply = _takeReply();
    await _upload('Sending photo…', (onProgress) {
      return _chat.sendImage(
        coupleId: _coupleId,
        senderId: _myUid,
        file: File(picked!.path),
        onProgress: onProgress,
        replyTo: reply,
      );
    });
  }

  Future<void> _sendVideo(ImageSource source) async {
    final XFile? picked;
    try {
      picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 3),
      );
    } catch (e) {
      if (!mounted) return;
      context.showSnackMessage(
        'Could not open ${source == ImageSource.camera ? 'the camera' : 'your videos'}.',
      );
      return;
    }
    if (picked == null) return;

    final file = File(picked.path);
    final duration = await _videoDuration(file);
    final reply = _takeReply();

    await _upload('Sending video…', (onProgress) {
      return _chat.sendVideo(
        coupleId: _coupleId,
        senderId: _myUid,
        file: file,
        duration: duration,
        onProgress: onProgress,
        replyTo: reply,
      );
    });
  }

  Future<Duration?> _videoDuration(File file) async {
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      return controller.value.duration;
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }

  Future<void> _sendVoice(File file, Duration duration) async {
    final reply = _takeReply();
    await _upload('Sending voice message…', (_) {
      return _chat.sendVoice(
        coupleId: _coupleId,
        senderId: _myUid,
        file: file,
        duration: duration,
        replyTo: reply,
      );
    });
  }

  Future<void> _openAttachSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        void pick(Future<void> Function() action) {
          Navigator.pop(sheetContext);
          action();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Photo from gallery'),
                onTap: () => pick(() => _sendPhoto(ImageSource.gallery)),
              ),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Video from gallery'),
                subtitle: const Text('Up to 3 minutes, 100 MB'),
                onTap: () => pick(() => _sendVideo(ImageSource.gallery)),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Record a video'),
                onTap: () => pick(() => _sendVideo(ImageSource.camera)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Opens the sticker picker, which sends the sticker itself (as a reply,
  /// if one is in progress) and reports whether it did.
  Future<void> _openStickers() async {
    final reply = _replyingTo == null ? null : ReplyPreview.of(_replyingTo!);
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => StickerPickerSheet(replyTo: reply),
    );
    if (sent == true && mounted && _replyingTo != null) {
      setState(() => _replyingTo = null);
    }
  }

  // ---- Message actions ----------------------------------------------------

  Future<void> _openMessageActions(Message message) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => MessageActionsSheet(
        message: message,
        myUid: _myUid,
        onReact: (emoji) => _react(message, emoji),
        onReply: () => setState(() => _replyingTo = message),
        onCopy: () {
          Clipboard.setData(ClipboardData(text: message.text));
          context.showSnackMessage('Copied');
        },
        onTogglePin: () => _setPinned(message, !message.pinned),
        onDelete: () => _confirmDelete(message),
      ),
    );
  }

  Future<void> _react(Message message, String emoji) async {
    await HapticFeedback.selectionClick();
    try {
      await _chat.toggleReaction(
        coupleId: _coupleId,
        message: message,
        uid: _myUid,
        emoji: emoji,
      );
    } catch (e) {
      if (!mounted) return;
      context.showSnackMessage('Could not add that reaction.');
    }
  }

  Future<void> _setPinned(Message message, bool pinned) async {
    try {
      await _chat.setPinned(
        coupleId: _coupleId,
        message: message,
        pinned: pinned,
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage(
        'Could not ${pinned ? 'pin' : 'unpin'} that message.',
      );
    }
  }

  Future<void> _confirmDelete(Message message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'It will be removed for both of you. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _chat.deleteMessage(coupleId: _coupleId, message: message);
    } catch (e) {
      if (!mounted) return;
      context.showSnackMessage('Could not delete that message.');
    }
  }

  // ---- Menus --------------------------------------------------------------

  Future<void> _onMenu(_MenuAction action) async {
    switch (action) {
      case _MenuAction.search:
        final id = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const ChatSearchScreen()),
        );
        if (id != null) await _jumpTo(id);
      case _MenuAction.media:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const MediaGalleryScreen()));
      case _MenuAction.pinned:
        await _openPinnedSheet();
      case _MenuAction.theme:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ChatAppearanceScreen()));
    }
  }

  Future<void> _openPinnedSheet() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      // A fresh stream: Firestore streams are broadcast, so a second listener
      // on the pinned bar's stream would get nothing until the next change.
      builder: (_) => PinnedMessagesSheet(
        pinnedStream: _chat.watchPinned(_coupleId),
        nameFor: _nameFor,
        onUnpin: (m) => _setPinned(m, false),
      ),
    );
    if (id != null) await _jumpTo(id);
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final partnerName = ref.watch(partnerNameProvider);
    final couple = ref.watch(coupleProvider).value;
    final look = ref.watch(effectiveChatLookProvider);

    return AnimatedTheme(
      data: _themeFor(Theme.of(context), look),
      child: _buildScaffold(partnerName, couple, look),
    );
  }

  Widget _buildScaffold(String partnerName, Couple? couple, ChatLook look) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(partnerName),
            if (couple != null && !couple.isComplete)
              Text(
                'Waiting for your partner · code ${couple.inviteCode}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(Icons.call_outlined),
            onPressed: () => _call(CallType.voice),
          ),
          IconButton(
            tooltip: 'Video call',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _call(CallType.video),
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: 'More',
            onSelected: _onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _MenuAction.search,
                child: ListTile(
                  leading: Icon(Icons.search),
                  title: Text('Search'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.media,
                child: ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('Photos & videos'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.pinned,
                child: ListTile(
                  leading: Icon(Icons.push_pin_outlined),
                  title: Text('Pinned messages'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _MenuAction.theme,
                child: ListTile(
                  leading: Icon(Icons.palette_outlined),
                  title: Text('Chat theme'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          StreamBuilder<List<Message>>(
            stream: _pinnedStream,
            builder: (context, snap) {
              final pinned = snap.data ?? const <Message>[];
              if (pinned.isEmpty) return const SizedBox.shrink();
              return PinnedMessageBar(
                latest: pinned.first,
                count: pinned.length,
                onTap: () => _jumpTo(pinned.first.id),
                onShowAll: _openPinnedSheet,
              );
            },
          ),
          if (_uploadProgress != null)
            UploadProgressBar(
              label: _uploadLabel ?? 'Sending…',
              progress: _uploadProgress == 0 ? null : _uploadProgress,
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ChatBackgroundLayer(background: look.background),
                ),
                _buildMessages(partnerName),
              ],
            ),
          ),
          ChatInput(
            enabled: _uploadProgress == null,
            onSendText: _sendText,
            onPickCamera: () => _sendPhoto(ImageSource.camera),
            onAttach: _openAttachSheet,
            onSendVoice: _sendVoice,
            onOpenStickers: _openStickers,
            replyingTo: _replyingTo == null
                ? null
                : ReplyPreview.of(_replyingTo!),
            replyingToLabel: _replyingTo == null
                ? null
                : _nameFor(_replyingTo!.senderId),
            onCancelReply: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
  }

  void _call(CallType type) {
    placeCall(context, ref, type: type);
  }

  Widget _buildMessages(String partnerName) {
    return StreamBuilder<({List<Message> messages, bool fromCache})>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // Let paging recover if a bigger page failed.
          if (_loadingMore) _finishPage();
          return Center(
            child: _OverBackground(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyState(
                    icon: Icons.cloud_off,
                    text: 'Could not load messages.',
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                    onPressed: () => setState(() {
                      _messagesStream = _chat.watchMessagePage(
                        _coupleId,
                        limit: _limit,
                      );
                    }),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final page = snapshot.data!;
        final messages = page.messages;
        _onMessages(
          messages,
          fromCache: page.fromCache,
          isCurrentQuery: snapshot.connectionState == ConnectionState.active,
        );

        if (messages.isEmpty) {
          return const Center(
            child: _OverBackground(
              child: EmptyState(
                icon: Icons.favorite_border,
                text: 'Say something sweet to start.',
              ),
            ),
          );
        }

        // Mark incoming messages read, but only once per new arrival.
        final newest = messages.first;
        if (newest.id != _lastSeenSweepId && widget.isActive) {
          _lastSeenSweepId = newest.id;
          _markSeen();
        }

        final hasMore = _hasMore;

        return ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: messages.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            // The top of the list: fetch the next page when it comes into view.
            if (index == messages.length) {
              // With a timeout, so paging can retry after an offline spell.
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _loadMoreAndWait(),
              );
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            final message = messages[index];
            final isMine = message.senderId == _myUid;

            // messages is newest-first, so "older" is the next index.
            final older = index + 1 < messages.length
                ? messages[index + 1]
                : null;
            final showDate = _needsDateDivider(message, older);

            final Widget row = message.type == MessageType.call
                ? CallLogTile(message: message, myUid: _myUid)
                : MessageBubble(
                    message: message,
                    isMine: isMine,
                    myUid: _myUid,
                    partnerName: partnerName,
                    highlighted: _highlightId == message.id,
                    onLongPress: () => _openMessageActions(message),
                    onDoubleTap: () =>
                        _react(message, CoupleReaction.love.emoji),
                    onSwipeReply: () => setState(() => _replyingTo = message),
                    onTapQuote: _jumpTo,
                  );

            return KeyedSubtree(
              key: _rowKeys.putIfAbsent(message.id, GlobalKey.new),
              child: Column(
                children: [
                  if (showDate) ChatDateDivider(date: message.sentAt),
                  row,
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _needsDateDivider(Message current, Message? older) {
    final currentDate = current.sentAt;
    if (currentDate == null) return false;
    if (older?.sentAt == null) return true;

    final previousDate = older!.sentAt!;
    return currentDate.year != previousDate.year ||
        currentDate.month != previousDate.month ||
        currentDate.day != previousDate.day;
  }
}

/// Puts a soft pill behind loose text when a photo or pattern is drawn
/// behind the messages, so it stays readable.
class _OverBackground extends StatelessWidget {
  const _OverBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ChatPalette.of(context);
    if (!palette.hasBackground) return child;
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: palette.systemChip,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}
