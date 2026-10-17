import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/data/chat_look_service.dart';
import 'package:couple_app/features/chat/models/chat_look.dart';
import 'package:couple_app/features/chat/providers/chat_look_providers.dart';
import 'package:couple_app/features/chat/widgets/background_photo_sheet.dart';
import 'package:couple_app/features/chat/widgets/chat_background_tiles.dart';
import 'package:couple_app/features/chat/widgets/chat_color_picker.dart';
import 'package:couple_app/features/chat/widgets/chat_look_preview.dart';
import 'package:couple_app/features/chat/widgets/chat_patterns.dart';
import 'package:couple_app/features/chat/widgets/upload_progress_bar.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

enum _PhotoChoice { gallery, memories, chat }

/// Chat colour and background, for both partners or just for me, with a
/// live preview of the result.
class ChatAppearanceScreen extends ConsumerStatefulWidget {
  const ChatAppearanceScreen({super.key});

  @override
  ConsumerState<ChatAppearanceScreen> createState() =>
      _ChatAppearanceScreenState();
}

class _ChatAppearanceScreenState extends ConsumerState<ChatAppearanceScreen> {
  late final ChatLookService _service;
  late final String _uid;
  late final String _coupleId;
  final _picker = ImagePicker();

  /// Set once both looks have loaded; later changes from the other phone
  /// don't overwrite what is being edited here.
  bool _ready = false;
  late ChatLookMode _initialMode;
  late ChatLookMode _mode;
  late ChatLook _savedShared;
  ChatLook? _savedPersonal;
  late ChatLook _sharedDraft;
  ChatLook? _personalDraft;

  /// Photos uploaded during this visit (Storage path → URL). Whatever the
  /// saved look doesn't use is deleted again.
  final _uploads = <String, String>{};

  bool _uploading = false;
  bool _saving = false;
  bool _saved = false;

  bool get _busy => _uploading || _saving;

  ChatLook get _draft =>
      _mode == ChatLookMode.personal ? _personalDraft! : _sharedDraft;

  ChatLook? get _savedForMode =>
      _mode == ChatLookMode.personal ? _savedPersonal : _savedShared;

  bool get _dirty =>
      _mode != _initialMode || _draft != (_savedForMode ?? ChatLook.standard);

  @override
  void initState() {
    super.initState();
    _service = ref.read(chatLookServiceProvider);
    _uid = ref.read(currentUidProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
  }

  @override
  void dispose() {
    // Left without saving: nothing uses this visit's uploads.
    if (!_saved) {
      for (final path in _uploads.keys) {
        unawaited(_service.deleteUploaded(path));
      }
    }
    super.dispose();
  }

  void _init(SharedChatLook shared, PersonalChatLook personal) {
    _ready = true;
    _initialMode = _mode = personal.mode;
    _savedShared = _sharedDraft = shared.look;
    _savedPersonal = personal.look;
    // In personal mode with no look stored, the chat shows the standard one.
    _personalDraft =
        personal.look ??
        (personal.mode == ChatLookMode.personal ? ChatLook.standard : null);
  }

  // ---- Editing ------------------------------------------------------------

  void _update(ChatLook look) {
    setState(() {
      if (_mode == ChatLookMode.personal) {
        _personalDraft = look;
      } else {
        _sharedDraft = look;
      }
    });
  }

  void _setMode(ChatLookMode mode) {
    setState(() {
      _mode = mode;
      if (mode == ChatLookMode.personal && _personalDraft == null) {
        // First personal look: start from the shared one. A photo the shared
        // look uploaded stays owned by it, so replacing it here later never
        // deletes the shared background.
        final bg = _sharedDraft.background;
        _personalDraft = ChatLook(
          colorValue: _sharedDraft.colorValue,
          background: bg.storagePath == _savedShared.background.storagePath
              ? _withoutStoragePath(bg)
              : bg,
        );
      }
    });
  }

  static ChatBackground _withoutStoragePath(ChatBackground bg) =>
      ChatBackground(
        kind: bg.kind,
        patternId: bg.patternId,
        photoUrl: bg.photoUrl,
        dim: bg.dim,
        blur: bg.blur,
      );

  void _setColor(int? value) =>
      _update(ChatLook(colorValue: value, background: _draft.background));

  void _setBackground(ChatBackground background) =>
      _update(ChatLook(colorValue: _draft.colorValue, background: background));

  void _setPhoto(String url, String? storagePath) {
    final current = _draft.background;
    _setBackground(
      ChatBackground(
        kind: ChatBackgroundKind.photo,
        photoUrl: url,
        storagePath: storagePath,
        dim: current.isPhoto ? current.dim : ChatBackground.defaultDim,
        blur: current.isPhoto ? current.blur : 0,
      ),
    );
  }

  void _setPhotoEffect({double? dim, double? blur}) {
    final bg = _draft.background;
    _setBackground(
      ChatBackground(
        kind: bg.kind,
        photoUrl: bg.photoUrl,
        storagePath: bg.storagePath,
        dim: dim ?? bg.dim,
        blur: blur ?? bg.blur,
      ),
    );
  }

  // ---- Photos -------------------------------------------------------------

  Future<void> _choosePhoto() async {
    final choice = await showModalBottomSheet<_PhotoChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, _PhotoChoice.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('From our memories'),
              onTap: () => Navigator.pop(sheetContext, _PhotoChoice.memories),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('From chat photos'),
              onTap: () => Navigator.pop(sheetContext, _PhotoChoice.chat),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _PhotoChoice.gallery:
        await _pickFromGallery();
      case _PhotoChoice.memories:
        await _pickExisting(BackgroundPhotoSource.memories);
      case _PhotoChoice.chat:
        await _pickExisting(BackgroundPhotoSource.chat);
    }
  }

  /// A photo the couple already has: no upload, nothing to delete later.
  Future<void> _pickExisting(BackgroundPhotoSource source) async {
    final url = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BackgroundPhotoSheet(source: source),
    );
    if (!mounted || url == null) return;
    _setPhoto(url, null);
  }

  Future<void> _pickFromGallery() async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 82,
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage('Could not open your photos.');
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final result = await _service.uploadBackground(
        file: File(picked.path),
        coupleId: _coupleId,
        uid: _uid,
        personal: _mode == ChatLookMode.personal,
      );
      if (!mounted) {
        unawaited(_service.deleteUploaded(result.path));
        return;
      }
      _uploads[result.path] = result.url;
      _setPhoto(result.url, result.path);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      context.showSnackMessage(
        e.plugin == 'firebase_storage'
            ? 'Photo backgrounds need Firebase Storage enabled on this project.'
            : 'Could not upload that photo. Check your connection.',
      );
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage(
        'Could not upload that photo. Check your connection.',
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---- Saving -------------------------------------------------------------

  Future<void> _save() async {
    final mode = _mode;
    final look = _draft;
    setState(() => _saving = true);
    try {
      if (mode == ChatLookMode.shared) {
        if (look != _savedShared) {
          await _service.saveShared(coupleId: _coupleId, uid: _uid, look: look);
        }
        if (_initialMode != ChatLookMode.shared) {
          // Back to the shared look; the personal one is kept for next time.
          await _service.savePersonal(uid: _uid, mode: ChatLookMode.shared);
        }
      } else {
        await _service.savePersonal(
          uid: _uid,
          mode: ChatLookMode.personal,
          look: look,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage(
        'Could not save the chat theme. Check your connection.',
      );
      return;
    }

    _saved = true;
    _deleteUnused(mode, look);
    if (!mounted) return;
    context.showSnackMessage('Chat theme updated');
    Navigator.of(context).pop();
  }

  /// Removes uploads the saved [look] no longer uses: this visit's spare
  /// uploads and the photo it replaced. Only touches the look being edited,
  /// and never a photo my other look still shows.
  void _deleteUnused(ChatLookMode mode, ChatLook look) {
    final old = (mode == ChatLookMode.shared ? _savedShared : _savedPersonal)
        ?.background;
    final other = (mode == ChatLookMode.shared ? _savedPersonal : _savedShared)
        ?.background;
    final candidates = <String, String?>{
      ..._uploads,
      if (old?.storagePath != null) old!.storagePath!: old.photoUrl,
    };
    for (final MapEntry(key: path, value: url) in candidates.entries) {
      final inUse =
          path == look.background.storagePath ||
          path == other?.storagePath ||
          (url != null &&
              (url == look.background.photoUrl || url == other?.photoUrl));
      if (!inUse) unawaited(_service.deleteUploaded(path));
    }
  }

  // ---- Build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final shared = ref.watch(sharedChatLookProvider);
    final personal = ref.watch(personalChatLookProvider);
    final partnerName = ref.watch(partnerNameProvider);

    if (!_ready && shared.value != null && personal.value != null) {
      _init(shared.value!, personal.value!);
    }

    final Widget body;
    if (_ready) {
      body = _editor(context, partnerName, shared.value);
    } else if (shared.hasError || personal.hasError) {
      body = const EmptyState(
        icon: Icons.cloud_off,
        text: 'Could not load the chat theme. Check your connection.',
        padding: EdgeInsets.all(24),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chat theme'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _saving
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: _ready && _dirty && !_busy ? _save : null,
                      child: const Text('Save'),
                    ),
            ),
          ],
        ),
        body: body,
      ),
    );
  }

  Widget _editor(
    BuildContext context,
    String partnerName,
    SharedChatLook? shared,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final look = _draft;
    final bg = look.background;
    final height = MediaQuery.sizeOf(context).height;

    return Column(
      children: [
        if (_uploading)
          const UploadProgressBar(label: 'Uploading photo…', progress: null)
        else if (_saving)
          const UploadProgressBar(label: 'Saving…', progress: null),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: ChatLookPreview(
            look: look,
            partnerName: partnerName,
            height: math.min(240, height * .32),
          ),
        ),
        Expanded(
          child: AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ChatLookMode>(
                    segments: const [
                      ButtonSegment(
                        value: ChatLookMode.shared,
                        icon: Icon(Icons.favorite_outline),
                        label: Text('Both of us'),
                      ),
                      ButtonSegment(
                        value: ChatLookMode.personal,
                        icon: Icon(Icons.person_outline),
                        label: Text('Just me'),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => _setMode(s.first),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _caption(shared, partnerName),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                _SectionTitle(
                  title: 'Colour',
                  trailing: ChatColorPicker.labelFor(look.colorValue),
                ),
                const SizedBox(height: 12),
                ChatColorPicker(
                  selected: look.colorValue,
                  onSelected: _setColor,
                ),
                const SizedBox(height: 24),
                _SectionTitle(
                  title: 'Background',
                  trailing: bg.isPhoto
                      ? 'Photo'
                      : ChatPatterns.byId(
                              bg.isPattern ? bg.patternId : null,
                            )?.label ??
                            'None',
                ),
                const SizedBox(height: 12),
                ChatBackgroundTiles(
                  look: look,
                  onNone: () => _setBackground(ChatBackground.none),
                  onPattern: (id) => _setBackground(
                    ChatBackground(
                      kind: ChatBackgroundKind.pattern,
                      patternId: id,
                    ),
                  ),
                  onPhoto: _choosePhoto,
                ),
                if (bg.isPhoto) ...[
                  const SizedBox(height: 20),
                  _EffectSlider(
                    icon: Icons.brightness_6_outlined,
                    label: 'Dim',
                    valueLabel: '${(bg.dim * 100).round()}%',
                    value: bg.dim,
                    max: ChatBackground.maxDim,
                    onChanged: (v) => _setPhotoEffect(dim: v),
                  ),
                  _EffectSlider(
                    icon: Icons.blur_on,
                    label: 'Blur',
                    valueLabel: bg.blur.round().toString(),
                    value: bg.blur,
                    max: ChatBackground.maxBlur,
                    onChanged: (v) => _setPhotoEffect(blur: v),
                  ),
                ],
                const SizedBox(height: 20),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset to default'),
                    onPressed: look.isStandard
                        ? null
                        : () => _update(ChatLook.standard),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _caption(SharedChatLook? shared, String partnerName) {
    if (_mode == ChatLookMode.personal) {
      return 'Only you see this. $partnerName keeps seeing the shared theme.';
    }
    final by = shared?.updatedBy;
    if (by == null) return 'You both see this theme.';
    final who = by == _uid ? 'You' : partnerName;
    final at = shared?.updatedAt;
    return at == null
        ? '$who changed this'
        : '$who changed this ${_ago(at, DateTime.now())}';
  }

  static String _ago(DateTime at, DateTime now) {
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return 'on ${DateFormat.yMMMd().format(at)}';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            trailing,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _EffectSlider extends StatelessWidget {
  const _EffectSlider({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(
          width: 40,
          child: Text(label, style: theme.textTheme.labelLarge),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            semanticFormatterCallback: (_) => valueLabel,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            valueLabel,
            textAlign: TextAlign.end,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
