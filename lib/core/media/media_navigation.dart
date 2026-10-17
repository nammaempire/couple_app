import 'package:flutter/material.dart';

import 'package:couple_app/core/media/photo_viewer_screen.dart';
import 'package:couple_app/core/media/video_player_screen.dart';

/// Opens [url] full screen in the photo viewer.
Future<void> openPhoto(BuildContext context, String url) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PhotoViewerScreen(imageUrl: url)),
  );
}

/// Opens [url] full screen in the video player.
Future<void> openVideo(BuildContext context, String url) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => VideoPlayerScreen(videoUrl: url)),
  );
}
