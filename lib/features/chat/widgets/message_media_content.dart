import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:couple_app/core/media/media_navigation.dart';
import 'package:couple_app/core/utils/duration_format.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/widgets/chat_privacy_scope.dart';
import 'package:couple_app/features/chat/widgets/message_meta_row.dart';

/// Photo, or video thumbnail with a play button and length.
class MessageMediaContent extends StatelessWidget {
  const MessageMediaContent({
    super.key,
    required this.message,
    required this.radius,
    required this.isMine,
  });

  final Message message;
  final BorderRadius radius;
  final bool isMine;

  bool get _isVideo => message.type == MessageType.video;

  void _open(BuildContext context) {
    if (_isVideo) {
      final url = message.mediaUrl;
      if (url == null) return;
      openVideo(
        context,
        url,
        wrap: (viewer) =>
            ChatPrivacyScope(subject: ScreenshotSubject.video, child: viewer),
      );
    } else {
      final url = message.imageUrl;
      if (url == null) return;
      openPhoto(
        context,
        url,
        wrap: (viewer) =>
            ChatPrivacyScope(subject: ScreenshotSubject.photo, child: viewer),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumb = message.imageUrl;
    if (!_isVideo && thumb == null) return const SizedBox.shrink();

    final placeholder = Container(
      color: _isVideo
          ? const Color(0xFF2A2124)
          : theme.colorScheme.surfaceContainerHighest,
    );

    Widget image = thumb == null
        ? placeholder
        : CachedNetworkImage(
            imageUrl: thumb,
            fit: BoxFit.cover,
            placeholder: (context, _) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            errorWidget: (context, _, _) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          );
    if (!_isVideo && thumb != null) image = Hero(tag: thumb, child: image);

    final duration = message.duration;

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        ClipRRect(
          borderRadius: radius,
          child: AspectRatio(
            aspectRatio: (message.imageAspectRatio ?? (_isVideo ? 16 / 9 : 1.0))
                .clamp(0.5, 1.8)
                .toDouble(),
            child: GestureDetector(
              onTap: () => _open(context),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  if (_isVideo)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  if (_isVideo && duration != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _OverlayChip(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.videocam,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatDuration(duration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: _OverlayChip(
            child: MessageMetaRow(
              message: message,
              isMine: isMine,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
