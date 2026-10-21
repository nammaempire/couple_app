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
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/motion_policy.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/widgets/profile_avatar.dart';
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
import 'package:couple_app/features/chat/widgets/chat_chrome.dart';
import 'package:couple_app/features/chat/widgets/chat_date_divider.dart';
import 'package:couple_app/features/chat/widgets/chat_input.dart';
import 'package:couple_app/features/chat/widgets/chat_palette.dart';
import 'package:couple_app/features/chat/widgets/chat_privacy_scope.dart';
import 'package:couple_app/features/chat/widgets/clear_chat_sheet.dart';
import 'package:couple_app/features/chat/widgets/message_actions_sheet.dart';
import 'package:couple_app/features/chat/widgets/message_bubble.dart';
import 'package:couple_app/features/chat/widgets/pinned_message_bar.dart';
import 'package:couple_app/features/chat/widgets/pinned_messages_sheet.dart';
import 'package:couple_app/features/chat/widgets/screenshot_privacy_sheet.dart';
import 'package:couple_app/features/chat/widgets/system_message_line.dart';
import 'package:couple_app/features/chat/widgets/upload_progress_bar.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/couple/widgets/separation_banner.dart';
import 'package:couple_app/features/stickers/widgets/sticker_picker_sheet.dart';

enum _MenuAction { search, media, pinned, theme, screenshots, clear }

/// The conversation between the two partners.
///
/// Messages hidden by "clear chat" ([chatClearedAtProvider]) are left out
/// of the list, the pinned bar and paging. While the chat is on screen,
/// screenshots are reported to the partner, and blocked when the couple
/// has turned that on (see [ChatPrivacyScope]).
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

  /// The loaded messages "clear chat" has not hidden.
  List<Message> _loaded = const [];

  /// How many messages the current page fetched, hidden ones included.
  int _fetched = 0;

  /// The page reached a message hidden by "clear chat"; everything older is
  /// hidden too, so there is nothing more to page in.
  bool _reachedClear = false;

  bool get _hasMore => _fetched >= _limit && !_reachedClear;
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

  /// Ids of every message the list has shown, and the newest of them, so
  /// messages that arrive while the chat is open can slide in once.
  final _shownIds = <String>{};
  String? _newestShownId;

  /// Messages that arrived after the first page loaded and have not yet
  /// played their entrance.
  final _arrivals = <String>{};

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

  /// Opens a chat sheet in the chat's own colours, over a soft wash of the
  /// chat colour, with a gradient handle drawn by the sheet itself
  /// ([ChatSheetHeader]).
  Future<T?> _showChatSheet<T>(
    WidgetBuilder builder, {
    bool isScrollControlled = false,
    bool useSafeArea = false,
  }) {
    final theme = _chatTheme?.theme ?? Theme.of(context);
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      clipBehavior: Clip.antiAlias,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) => Theme(
        data: theme,
        child: ChatSheetBackground(child: Builder(builder: builder)),
      ),
    );
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
        .markSeen(
          coupleId: _coupleId,
          partnerId: partnerId,
          clearedAt: ref.read(chatClearedAtProvider),
        )
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

  /// Called from the list's builder with each result of the current query:
  /// the [visible] messages out of [fetched].
  void _onMessages(
    List<Message> visible, {
    required int fetched,
    required bool reachedClear,
    required bool fromCache,
    required bool isCurrentQuery,
  }) {
    // Right after the limit grows, StreamBuilder replays the previous
    // query's result; ignore that for paging purposes.
    if (!isCurrentQuery) return;
    _loaded = visible;
    _fetched = fetched;
    _reachedClear = reachedClear;

    if (!_loadingMore) return;
    // A cache-only answer may be missing older messages the server has, so
    // only a short server answer means "no more". Reaching the clear point
    // means no more either.
    final pageFilled = fetched >= _limit || reachedClear;
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
      picked = await ref
          .read(appLockControllerProvider.notifier)
          .suspendWhile(
            _picker.pickImage(source: source, imageQuality: 82, maxWidth: 2000),
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
      picked = await ref
          .read(appLockControllerProvider.notifier)
          .suspendWhile(
            _picker.pickVideo(
              source: source,
              maxDuration: const Duration(minutes: 3),
            ),
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
    await _showChatSheet<void>((sheetContext) {
      void pick(Future<void> Function() action) {
        Navigator.pop(sheetContext);
        action();
      }

      return SafeArea(
        // Scrolls rather than overflowing with large text.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ChatSheetHeader(
                title: 'Share a moment',
                icon: Icons.auto_awesome,
              ),
              ChatSheetOption(
                icon: Icons.image_outlined,
                title: 'Photo from gallery',
                onTap: () => pick(() => _sendPhoto(ImageSource.gallery)),
              ),
              ChatSheetOption(
                icon: Icons.video_library_outlined,
                title: 'Video from gallery',
                subtitle: 'Up to 3 minutes, 100 MB',
                onTap: () => pick(() => _sendVideo(ImageSource.gallery)),
              ),
              ChatSheetOption(
                icon: Icons.videocam_outlined,
                title: 'Record a video',
                onTap: () => pick(() => _sendVideo(ImageSource.camera)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    });
  }

  /// Opens the sticker picker, which sends the sticker itself (as a reply,
  /// if one is in progress) and reports whether it did.
  Future<void> _openStickers() async {
    final reply = _replyingTo == null ? null : ReplyPreview.of(_replyingTo!);
    final sent = await _showChatSheet<bool>(
      (_) => StickerPickerSheet(replyTo: reply),
      isScrollControlled: true,
      useSafeArea: true,
    );
    if (sent == true && mounted && _replyingTo != null) {
      setState(() => _replyingTo = null);
    }
  }

  // ---- Message actions ----------------------------------------------------

  Future<void> _openMessageActions(Message message) async {
    // The partner's system lines have no actions at all.
    if (message.isSystem && message.senderId != _myUid) return;
    await _showChatSheet<void>(
      (_) => MessageActionsSheet(
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
        allowCopy: !ref.read(separationActiveProvider),
      ),
      isScrollControlled: true,
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
            style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
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
      case _MenuAction.screenshots:
        await _openScreenshotSettings();
      case _MenuAction.clear:
        await _openClearChat();
    }
  }

  // ---- Screenshots --------------------------------------------------------

  Future<void> _openScreenshotSettings() {
    return _showChatSheet<void>(
      (_) => ScreenshotPrivacySheet(
        partnerName: ref.read(partnerNameProvider),
        onChanged: _setScreenshotBlocking,
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _setScreenshotBlocking(bool blocked) async {
    try {
      await _chat.setScreenshotBlocking(
        coupleId: _coupleId,
        senderId: _myUid,
        senderName: ref.read(myChatNameProvider),
        blocked: blocked,
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage(
        'Could not ${blocked ? 'turn on' : 'turn off'} screenshot blocking.',
      );
    }
  }

  // ---- Clearing the chat --------------------------------------------------

  Future<void> _openClearChat() async {
    final choice = await _showChatSheet<ClearChatChoice>(
      (_) => ClearChatSheet(partnerName: ref.read(partnerNameProvider)),
      isScrollControlled: true,
    );
    switch (choice) {
      case ClearChatChoice.forMe:
        await _clearForMe();
      case ClearChatChoice.forBoth:
        await _clearForBoth();
      case null:
        return;
    }
  }

  Future<void> _clearForMe() async {
    try {
      await _chat.clearForMe(uid: _myUid);
      if (!mounted) return;
      if (_replyingTo != null) setState(() => _replyingTo = null);
      context.showSnackMessage('Chat cleared for you.');
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage('Could not clear the chat. Try again.');
    }
  }

  /// Runs "clear for both" behind a progress dialog. If it fails part way,
  /// choosing it again finishes the job.
  Future<void> _clearForBoth() async {
    final deleted = ValueNotifier<int>(0);
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Clearing the chat…'),
          content: ValueListenableBuilder<int>(
            valueListenable: deleted,
            builder: (context, count, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  count == 0
                      ? 'Deleting messages, photos and videos.'
                      : 'Deleted $count '
                            '${count == 1 ? 'message' : 'messages'} so far.',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    String result;
    try {
      await _chat.clearForBoth(
        coupleId: _coupleId,
        senderId: _myUid,
        senderName: ref.read(myChatNameProvider),
        onProgress: (count) => deleted.value = count,
      );
      result = 'Chat cleared for both of you.';
      if (mounted && _replyingTo != null) setState(() => _replyingTo = null);
    } catch (_) {
      result =
          'Could not finish clearing the chat. Check your connection and '
          'choose Clear for both again to finish.';
    }
    navigator.pop();
    deleted.dispose();
    if (!mounted) return;
    context.showSnackMessage(result);
  }

  Future<void> _openPinnedSheet() async {
    final id = await _showChatSheet<String>(
      // A fresh stream: Firestore streams are broadcast, so a second listener
      // on the pinned bar's stream would get nothing until the next change.
      (_) => PinnedMessagesSheet(
        pinnedStream: _chat.watchPinned(_coupleId).map(_visiblePins),
        nameFor: _nameFor,
        onUnpin: (m) => _setPinned(m, false),
      ),
      isScrollControlled: true,
    );
    if (id != null) await _jumpTo(id);
  }

  /// Pins that "clear chat" has not hidden.
  List<Message> _visiblePins(List<Message> pinned) {
    final clearedAt = ref.read(chatClearedAtProvider);
    return pinned
        .where((m) => !m.isSystem && !m.isClearedBy(clearedAt))
        .toList();
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final partnerName = ref.watch(partnerNameProvider);
    final couple = ref.watch(coupleProvider).value;
    final look = ref.watch(effectiveChatLookProvider);
    final clearedAt = ref.watch(chatClearedAtProvider);

    return ChatPrivacyScope(
      enabled: widget.isActive,
      child: AnimatedTheme(
        data: _themeFor(Theme.of(context), look),
        child: Builder(
          builder: (context) =>
              _buildScaffold(context, partnerName, couple, look, clearedAt),
        ),
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    String partnerName,
    Couple? couple,
    ChatLook look,
    DateTime? clearedAt,
  ) {
    final theme = Theme.of(context);
    final palette = ChatPalette.of(context);
    final scheme = theme.colorScheme;

    PopupMenuItem<_MenuAction> item(
      _MenuAction value,
      IconData icon,
      String label,
    ) => PopupMenuItem(
      value: value,
      child: ListTile(
        leading: Icon(icon, color: scheme.primary),
        title: Text(label),
        contentPadding: EdgeInsets.zero,
      ),
    );

    final actionStyle = IconButton.styleFrom(
      backgroundColor: palette.glass,
      foregroundColor: scheme.onSurface,
      side: BorderSide(color: palette.glassBorder),
      minimumSize: const Size(42, 42),
      fixedSize: const Size(42, 42),
      padding: EdgeInsets.zero,
    );

    return Scaffold(
      // The background runs behind the rounded header and the floating
      // composer.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 16,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        scrolledUnderElevation: 6,
        shadowColor: palette.glow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
        ),
        clipBehavior: Clip.antiAlias,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: ChatPalette.diagonal(palette.headerGradient),
          ),
          child: const SizedBox.expand(),
        ),
        // Two lines in a fixed-height bar: cap the scaling so very large
        // text can't overflow it.
        title: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: _ChatTitle(partnerName: partnerName, couple: couple),
        ),
        actions: [
          IconButton(
            tooltip: 'Voice call',
            style: actionStyle,
            icon: const Icon(Icons.call_outlined, size: 21),
            onPressed: () => _call(CallType.voice),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Video call',
            style: actionStyle,
            icon: const Icon(Icons.videocam_outlined, size: 22),
            onPressed: () => _call(CallType.video),
          ),
          PopupMenuButton<_MenuAction>(
            tooltip: 'More',
            onSelected: _onMenu,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            color: scheme.surfaceContainerLow,
            itemBuilder: (_) => [
              item(_MenuAction.search, Icons.search, 'Search'),
              item(
                _MenuAction.media,
                Icons.photo_library_outlined,
                'Photos & videos',
              ),
              item(
                _MenuAction.pinned,
                Icons.push_pin_outlined,
                'Pinned messages',
              ),
              item(_MenuAction.theme, Icons.palette_outlined, 'Chat theme'),
              item(
                _MenuAction.screenshots,
                Icons.screenshot_outlined,
                'Screenshots',
              ),
              item(
                _MenuAction.clear,
                Icons.cleaning_services_outlined,
                'Clear chat',
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ChatBackgroundLayer(background: look.background),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // While the pairing is ending: a one-line strip.
                const SeparationBanner(compact: true),
                StreamBuilder<List<Message>>(
                  stream: _pinnedStream,
                  builder: (context, snap) {
                    final pinned = _visiblePins(snap.data ?? const <Message>[]);
                    if (pinned.isEmpty) return const SizedBox.shrink();
                    return PinnedMessageBar(
                      latest: pinned.first,
                      count: pinned.length,
                      onTap: () => _jumpTo(pinned.first.id),
                      onShowAll: _openPinnedSheet,
                    );
                  },
                ),
                Expanded(child: _buildMessages(partnerName, clearedAt)),
                if (_uploadProgress != null)
                  UploadProgressBar(
                    label: _uploadLabel ?? 'Sending…',
                    progress: _uploadProgress == 0 ? null : _uploadProgress,
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
          ),
        ],
      ),
    );
  }

  void _call(CallType type) {
    placeCall(context, ref, type: type);
  }

  Widget _buildMessages(String partnerName, DateTime? clearedAt) {
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
        final part = ChatService.visiblePart(page.messages, clearedAt);
        final messages = part.visible;
        _onMessages(
          messages,
          fetched: page.messages.length,
          reachedClear: part.reachedClear,
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

        _trackArrivals(messages);
        final hasMore = _hasMore;

        return ListView.builder(
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
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

            final Widget row = message.isSystem
                ? SystemMessageLine(
                    message: message,
                    myUid: _myUid,
                    partnerName: partnerName,
                    onLongPress: isMine
                        ? () => _openMessageActions(message)
                        : null,
                  )
                : message.type == MessageType.call
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
              child: _Arrival(
                animate: _arrivals.contains(message.id),
                fromRight: isMine,
                onDone: () => _arrivals.remove(message.id),
                child: Column(
                  children: [
                    if (showDate) ChatDateDivider(date: message.sentAt),
                    row,
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Marks messages newer than the newest one already shown as arrivals,
  /// so they slide in once. Older pages and the first load don't animate.
  void _trackArrivals(List<Message> messages) {
    final previousNewest = _newestShownId;
    if (previousNewest != null) {
      for (final m in messages.take(6)) {
        if (m.id == previousNewest) break;
        if (!_shownIds.contains(m.id)) _arrivals.add(m.id);
      }
    }
    for (final m in messages) {
      _shownIds.add(m.id);
    }
    _newestShownId = messages.first.id;
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

/// The header's avatar, name and status line.
class _ChatTitle extends ConsumerWidget {
  const _ChatTitle({required this.partnerName, required this.couple});

  final String partnerName;
  final Couple? couple;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = ChatPalette.of(context);
    final scheme = theme.colorScheme;
    final partner = ref.watch(partnerProvider).value;
    final waiting = couple != null && !couple!.isComplete;

    return Row(
      children: [
        // Gradient ring around the partner's face.
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: ChatPalette.diagonal(palette.accentGradient),
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.headerGradient.first,
            ),
            child: ProfileAvatar(
              user: partner,
              size: 38,
              fallbackName: partnerName,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                partnerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              if (waiting)
                Text(
                  'Waiting for your partner · code ${couple!.inviteCode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                Row(
                  children: [
                    RepaintBoundary(
                      child: Pulse(
                        duration: const Duration(milliseconds: 1400),
                        builder: (context, v, child) =>
                            Transform.scale(scale: 1 + v * .25, child: child),
                        child: Icon(
                          Icons.favorite,
                          size: 11,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Just the two of you',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slides and fades a newly arrived message into place once. Keeps the same
/// widget in the tree whether or not it animates, so the row's state is
/// never rebuilt when the entrance ends.
class _Arrival extends StatefulWidget {
  const _Arrival({
    required this.animate,
    required this.fromRight,
    required this.onDone,
    required this.child,
  });

  final bool animate;
  final bool fromRight;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_Arrival> createState() => _ArrivalState();
}

class _ArrivalState extends State<_Arrival>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || !widget.animate) return;
    if (!MotionPolicy.enabled(context)) {
      widget.onDone();
      return;
    }
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    final curve = CurvedAnimation(parent: c, curve: Curves.easeOutBack);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: c,
        child: widget.child,
        builder: (context, child) {
          final v = curve.value;
          if (c.isCompleted) return child!;
          return Opacity(
            opacity: c.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(
                (widget.fromRight ? 1 : -1) * (1 - v) * 24,
                (1 - v) * 16,
              ),
              child: Transform.scale(
                scale: .92 + .08 * v,
                alignment: widget.fromRight
                    ? Alignment.bottomRight
                    : Alignment.bottomLeft,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }
}
