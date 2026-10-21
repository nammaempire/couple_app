import 'package:flutter/material.dart';

import 'package:couple_app/core/media/photo_viewer_screen.dart';
import 'package:couple_app/core/media/video_player_screen.dart';

/// Wraps a full-screen viewer, e.g. so the chat can keep screenshot
/// protection on while one of its photos is open.
typedef ViewerWrapper = Widget Function(Widget viewer);

/// Opens [url] full screen in the photo viewer.
Future<void> openPhoto(
  BuildContext context,
  String url, {
  ViewerWrapper? wrap,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) {
        final viewer = PhotoViewerScreen(imageUrl: url);
        return wrap == null ? viewer : wrap(viewer);
      },
    ),
  );
}

/// Opens [url] full screen in the video player.
Future<void> openVideo(
  BuildContext context,
  String url, {
  ViewerWrapper? wrap,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) {
        final viewer = VideoPlayerScreen(videoUrl: url);
        return wrap == null ? viewer : wrap(viewer);
      },
    ),
  );
}
