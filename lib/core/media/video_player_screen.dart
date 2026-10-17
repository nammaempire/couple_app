import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:couple_app/core/utils/duration_format.dart';

/// Full-screen playback of a chat video, with tap-to-show controls.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.videoUrl});

  final String videoUrl;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));

  bool _failed = false;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
    _controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {});
          _controller.play();
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final value = _controller.value;
    if (value.isPlaying) {
      _controller.pause();
    } else {
      if (value.position >= value.duration) _controller.seekTo(Duration.zero);
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;

    Widget body;
    if (_failed) {
      body = const Center(
        child: Text(
          'This video could not be played.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    } else if (!value.isInitialized) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = GestureDetector(
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
            ),
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: Stack(
                  children: [
                    Center(
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          padding: const EdgeInsets.all(14),
                        ),
                        iconSize: 40,
                        onPressed: _togglePlay,
                        icon: Icon(
                          value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            _Time(value.position),
                            const SizedBox(width: 10),
                            Expanded(
                              child: VideoProgressIndicator(
                                _controller,
                                allowScrubbing: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                colors: VideoProgressColors(
                                  playedColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  bufferedColor: Colors.white38,
                                  backgroundColor: Colors.white12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _Time(value.duration),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: body,
    );
  }
}

class _Time extends StatelessWidget {
  const _Time(this.value);

  final Duration value;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatDuration(value),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}
