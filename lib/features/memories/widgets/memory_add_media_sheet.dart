import 'package:flutter/material.dart';

/// Bottom sheet listing the ways to add photos and videos to a memory.
/// Closes itself before running the chosen action.
class MemoryAddMediaSheet extends StatelessWidget {
  const MemoryAddMediaSheet({
    super.key,
    required this.onPickPhotos,
    required this.onPickVideo,
    required this.onTakePhoto,
    required this.onRecordVideo,
  });

  final Future<void> Function() onPickPhotos;
  final Future<void> Function() onPickVideo;
  final Future<void> Function() onTakePhoto;
  final Future<void> Function() onRecordVideo;

  @override
  Widget build(BuildContext context) {
    void run(Future<void> Function() action) {
      Navigator.pop(context);
      action();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photos from gallery'),
            subtitle: const Text('Pick several at once'),
            onTap: () => run(onPickPhotos),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Video from gallery'),
            subtitle: const Text('Up to 3 minutes, 100 MB'),
            onTap: () => run(onPickVideo),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => run(onTakePhoto),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Record a video'),
            onTap: () => run(onRecordVideo),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
