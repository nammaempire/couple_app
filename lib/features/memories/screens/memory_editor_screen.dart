import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/memories/data/memory_service.dart';
import 'package:couple_app/features/memories/models/memory.dart';
import 'package:couple_app/features/memories/providers/memory_providers.dart';
import 'package:couple_app/features/memories/widgets/memory_add_media_sheet.dart';
import 'package:couple_app/features/memories/widgets/memory_album_picker.dart';
import 'package:couple_app/features/memories/widgets/memory_media_strip.dart';

/// Create a new memory, or edit an existing one when [memory] is given.
class MemoryEditorScreen extends ConsumerStatefulWidget {
  const MemoryEditorScreen({
    super.key,
    this.memory,
    this.existingAlbums = const [],
    this.initialAlbum,
  });

  final Memory? memory;
  final List<String> existingAlbums;
  final String? initialAlbum;

  @override
  ConsumerState<MemoryEditorScreen> createState() => _MemoryEditorScreenState();
}

class _MemoryEditorScreenState extends ConsumerState<MemoryEditorScreen> {
  late final String _coupleId;
  late final String _myUid;

  @override
  void initState() {
    super.initState();
    _coupleId = ref.read(currentCoupleIdProvider);
    _myUid = ref.read(currentUidProvider);
  }

  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  late final _title = TextEditingController(text: widget.memory?.title ?? '');
  late final _caption = TextEditingController(
    text: widget.memory?.caption ?? '',
  );
  late final _place = TextEditingController(text: widget.memory?.place ?? '');

  late DateTime _date = widget.memory?.date ?? DateTime.now();
  late String _album =
      widget.memory?.album ?? widget.initialAlbum ?? MemoryAlbums.randomMoments;

  late final List<MemoryMedia> _kept = [...?widget.memory?.media];
  final List<PendingMedia> _added = [];

  double? _progress;
  String? _error;

  bool get _isEditing => widget.memory != null;
  bool get _saving => _progress != null;
  int get _mediaCount => _kept.length + _added.length;

  List<String> get _albums {
    final list = [...MemoryAlbums.defaults];
    for (final a in widget.existingAlbums) {
      if (!list.contains(a)) list.add(a);
    }
    if (!list.contains(_album)) list.add(_album);
    return list;
  }

  @override
  void dispose() {
    _title.dispose();
    _caption.dispose();
    _place.dispose();
    super.dispose();
  }

  int get _room => MemoryService.maxMediaPerMemory - _mediaCount;

  Future<void> _addPhotos() async {
    if (_room <= 0) {
      context.showSnackMessage(
        'A memory can hold up to ${MemoryService.maxMediaPerMemory} '
        'photos and videos.',
      );
      return;
    }
    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 2400,
        limit: _room > 1 ? _room : null,
      );
      if (picked.isEmpty || !mounted) return;
      setState(() {
        for (final p in picked.take(_room)) {
          _added.add(PendingMedia(file: File(p.path), isVideo: false));
        }
      });
    } catch (_) {
      context.showSnackMessage('Could not open your photos.');
    }
  }

  Future<void> _addVideo(ImageSource source) async {
    if (_room <= 0) {
      context.showSnackMessage(
        'A memory can hold up to ${MemoryService.maxMediaPerMemory} '
        'photos and videos.',
      );
      return;
    }
    final XFile? picked;
    try {
      picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 3),
      );
    } catch (_) {
      if (mounted) {
        context.showSnackMessage(
          'Could not open ${source == ImageSource.camera ? 'the camera' : 'your videos'}.',
        );
      }
      return;
    }
    if (picked == null) return;

    final file = File(picked.path);
    Duration? duration;
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize().timeout(const Duration(seconds: 5));
      duration = controller.value.duration;
    } catch (_) {
      // Duration is optional.
    } finally {
      await controller.dispose();
    }
    if (!mounted) return;
    setState(
      () => _added.add(
        PendingMedia(file: file, isVideo: true, duration: duration),
      ),
    );
  }

  Future<void> _takePhoto() async {
    if (_room <= 0) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2400,
      );
      if (picked == null || !mounted) return;
      setState(
        () => _added.add(PendingMedia(file: File(picked.path), isVideo: false)),
      );
    } catch (_) {
      context.showSnackMessage('Could not open the camera.');
    }
  }

  Future<void> _openAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => MemoryAddMediaSheet(
        onPickPhotos: _addPhotos,
        onPickVideo: () => _addVideo(ImageSource.gallery),
        onTakePhoto: _takePhoto,
        onRecordVideo: () => _addVideo(ImageSource.camera),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1970),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'When did this happen?',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _newAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New album'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Goa 2026',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    // Disposed after the dialog's exit animation has finished.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      setState(() => _album = trimmed);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_mediaCount == 0 && _caption.text.trim().isEmpty) {
      setState(() => _error = 'Add a photo, a video or a few words.');
      return;
    }

    setState(() {
      _progress = 0;
      _error = null;
    });
    final memoryService = ref.read(memoryServiceProvider);
    try {
      if (_isEditing) {
        await memoryService.update(
          coupleId: _coupleId,
          memory: widget.memory!,
          title: _title.text,
          caption: _caption.text,
          date: _date,
          place: _place.text,
          album: _album,
          keptMedia: _kept,
          newMedia: _added,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
      } else {
        await memoryService.create(
          coupleId: _coupleId,
          createdBy: _myUid,
          title: _title.text,
          caption: _caption.text,
          date: _date,
          place: _place.text,
          album: _album,
          newMedia: _added,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on MemoryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save. Check your connection and '
              'that Firebase Storage is enabled.',
        );
      }
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit memory' : 'New memory'),
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                child: const Text('Save'),
              ),
            ),
          ],
          bottom: _saving
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                  ),
                )
              : null,
        ),
        body: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                MemoryMediaStrip(
                  kept: _kept,
                  added: _added,
                  onAdd: _openAddSheet,
                  onRemoveKept: (m) => setState(() => _kept.remove(m)),
                  onRemoveAdded: (m) => setState(() => _added.remove(m)),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Sunset at Nandi Hills',
                    counterText: '',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Give it a title'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _caption,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Caption',
                    hintText: 'What do you want to remember?',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(24),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date',
                            prefixIcon: Icon(Icons.event_outlined),
                          ),
                          child: Text(DateFormat.yMMMd().format(_date)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _place,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Place (optional)',
                    prefixIcon: Icon(Icons.place_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                Text('Album', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                MemoryAlbumPicker(
                  albums: _albums,
                  selected: _album,
                  onSelected: (album) => setState(() => _album = album),
                  onNewAlbum: _newAlbum,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
