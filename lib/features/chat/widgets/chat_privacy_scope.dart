import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/providers/core_providers.dart';
import 'package:couple_app/core/services/screen_privacy.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';

/// Wraps a screen that shows the conversation (the chat itself, and the
/// photos, videos, search and gallery opened from it).
///
/// While [enabled] and on screen, it holds a [ScreenPrivacyGuard] claim, so
/// a screenshot posts a [MessageType.screenshot] line about [subject], and
/// the couple's "block screenshots" switch puts the phone in secure mode.
///
/// "On screen" means its route is not covered by another full page, such
/// as a call screen. Dialogs, sheets and menus over it keep the claim, as
/// the conversation still shows behind them. The app going to the
/// background keeps it too, so the recent-apps preview stays hidden.
class ChatPrivacyScope extends ConsumerStatefulWidget {
  const ChatPrivacyScope({
    super.key,
    required this.child,
    this.subject = ScreenshotSubject.chat,
    this.enabled = true,
  });

  final Widget child;
  final ScreenshotSubject subject;
  final bool enabled;

  @override
  ConsumerState<ChatPrivacyScope> createState() => _ChatPrivacyScopeState();
}

class _ChatPrivacyScopeState extends ConsumerState<ChatPrivacyScope> {
  late final ScreenPrivacyGuard _guard;
  late final ChatService _chat;
  late final String _coupleId;
  late final String _myUid;

  /// The route's secondary animation runs while a full page is pushed on
  /// top of it. Popup routes (dialogs, sheets, menus) leave it alone.
  Animation<double>? _coverAnimation;
  bool _block = false;

  @override
  void initState() {
    super.initState();
    _guard = ref.read(screenPrivacyGuardProvider);
    _chat = ref.read(chatServiceProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
    ref.listenManual(blockScreenshotsProvider, (_, block) {
      _block = block;
      _sync();
    }, fireImmediately: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.secondaryAnimation;
    if (!identical(animation, _coverAnimation)) {
      _coverAnimation?.removeStatusListener(_onCoverChanged);
      _coverAnimation = animation?..addStatusListener(_onCoverChanged);
    }
    _sync();
  }

  @override
  void didUpdateWidget(covariant ChatPrivacyScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  @override
  void dispose() {
    _coverAnimation?.removeStatusListener(_onCoverChanged);
    _guard.release(this);
    super.dispose();
  }

  void _onCoverChanged(AnimationStatus _) => _sync();

  bool get _covered =>
      (_coverAnimation?.status ?? AnimationStatus.dismissed) !=
      AnimationStatus.dismissed;

  void _sync() {
    if (widget.enabled && !_covered) {
      _guard.claim(this, secure: _block, onScreenshot: _report);
    } else {
      _guard.release(this);
    }
  }

  void _report() {
    if (!mounted) return;
    _chat
        .sendScreenshotAlert(
          coupleId: _coupleId,
          senderId: _myUid,
          senderName: ref.read(myChatNameProvider),
          subject: widget.subject,
        )
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
