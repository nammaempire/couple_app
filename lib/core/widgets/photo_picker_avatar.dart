import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';

/// A round photo slot that opens camera or gallery when tapped.
///
/// Shows, in order of preference: a freshly picked [file], an existing
/// [imageUrl], or a placeholder [icon].
class PhotoPickerAvatar extends ConsumerWidget {
  const PhotoPickerAvatar({
    super.key,
    required this.onPicked,
    this.file,
    this.imageUrl,
    this.size = 112,
    this.icon = Icons.person_outline,
    this.label = 'Add photo',
  });

  final ValueChanged<File> onPicked;
  final File? file;
  final String? imageUrl;
  final double size;
  final IconData icon;
  final String label;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    // Read up front: the widget may be gone by the time the picker returns.
    final appLock = ref.read(appLockControllerProvider.notifier);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final picked = await appLock.suspendWhile(
        ImagePicker().pickImage(
          source: source,
          imageQuality: 85,
          maxWidth: 1080,
        ),
      );
      if (picked != null) onPicked(File(picked.path));
    } catch (_) {
      if (!context.mounted) return;
      context.showSnackMessage('Could not open your photos.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    Widget content;
    if (file != null) {
      content = Image.file(file!, fit: BoxFit.cover);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      content = CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => Icon(icon, size: size * .4),
      );
    } else {
      content = Icon(
        icon,
        size: size * .4,
        color: theme.colorScheme.onPrimaryContainer,
      );
    }

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () => _pick(context, ref),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer,
              ),
              child: content,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary,
                  border: Border.all(
                    color: theme.scaffoldBackgroundColor,
                    width: 3,
                  ),
                ),
                child: Icon(
                  Icons.photo_camera,
                  size: 16,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
