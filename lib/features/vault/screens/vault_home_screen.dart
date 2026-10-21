import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/vault/models/vault_event.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/models/vault_meta.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';
import 'package:couple_app/features/vault/screens/vault_code_change_screen.dart';
import 'package:couple_app/features/vault/screens/vault_photo_viewer.dart';
import 'package:couple_app/features/vault/vault_session.dart';
import 'package:couple_app/features/vault/widgets/vault_banners.dart';
import 'package:couple_app/features/vault/widgets/vault_devices_sheet.dart';
import 'package:couple_app/features/vault/widgets/vault_items.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';
import 'package:couple_app/features/vault/widgets/vault_policy.dart';

/// The open vault: photos and a private chat, with approval and alert
/// banners and the ⋮ menu. The real and decoy vaults use this same screen.
class VaultHomeScreen extends ConsumerStatefulWidget {
  const VaultHomeScreen({super.key, this.initialTab = 0});

  /// 0 for Photos, 1 for Chat.
  final int initialTab;

  @override
  ConsumerState<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends ConsumerState<VaultHomeScreen> {
  /// Phones the user said "Not now" to, this session.
  final _later = <String>{};
  String? _approving;
  String? _uploadLabel;
  double? _upload;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ---- Photos ---------------------------------------------------------------

  Future<void> _addPhoto() async {
    final source = await showVaultSheet<ImageSource>(
      context,
      (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final photos = ref.read(vaultPhotoSourceProvider);
    final session = ref.read(vaultSessionProvider.notifier);
    final appLock = ref.read(appLockControllerProvider.notifier);
    Uint8List? raw;
    try {
      raw = await session.suspendWhile(
        appLock.suspendWhile(photos.pick(source)),
      );
    } catch (_) {
      _snack(
        'Could not open ${source == ImageSource.camera ? 'the camera' : 'your photos'}.',
      );
      return;
    }
    if (raw == null || !mounted || !session.isUnlocked) return;

    setState(() {
      _uploadLabel = 'Getting it ready…';
      _upload = null;
    });
    final prepared = await photos.prepare(raw).whenComplete(() {
      raw!.fillRange(0, raw.length, 0);
    });
    if (!mounted) return;
    setState(() => _uploadLabel = null);

    final preview = MemoryImage(prepared.thumb);
    final policy = await showVaultPolicyPicker(
      context,
      current: VaultPolicy.keep,
      confirmLabel: 'Add to Private',
      preview: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image(image: preview, height: 140, fit: BoxFit.cover),
      ),
    );
    preview.evict();
    if (policy == null || !mounted || !session.isUnlocked) return;

    setState(() {
      _uploadLabel = 'Encrypting and sending…';
      _upload = 0;
    });
    try {
      await session.addPhoto(
        prepared,
        policy,
        onProgress: (p) {
          if (mounted) setState(() => _upload = p);
        },
      );
    } catch (_) {
      _snack('Couldn\'t add the photo. Try again.');
    } finally {
      prepared.photo.fillRange(0, prepared.photo.length, 0);
      if (mounted) {
        setState(() {
          _uploadLabel = null;
          _upload = null;
        });
      }
    }
  }

  Future<bool> _confirmDelete() async {
    final ok = await showVaultDialog<bool>(
      context,
      (context) => AlertDialog(
        title: const Text('Delete for both of you?'),
        content: const Text('It\'s removed from both phones for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(88, 40),
              backgroundColor: vaultBlush,
              foregroundColor: const Color(0xFF2A1430),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _delete(VaultItem item) async {
    if (!await _confirmDelete()) return;
    try {
      await ref.read(vaultSessionProvider.notifier).deleteItem(item);
    } catch (_) {
      _snack('Couldn\'t delete it. Try again.');
    }
  }

  void _openPhoto(VaultItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VaultPhotoViewer(
          item: item,
          onDelete: () async {
            if (!await _confirmDelete()) return;
            if (!mounted) return;
            Navigator.of(context).pop();
            try {
              await ref.read(vaultSessionProvider.notifier).deleteItem(item);
            } catch (_) {
              _snack('Couldn\'t delete it. Try again.');
            }
          },
        ),
      ),
    );
  }

  // ---- Chat -----------------------------------------------------------------

  Future<bool> _send(String text, VaultPolicy policy) async {
    try {
      await ref.read(vaultSessionProvider.notifier).sendMessage(text, policy);
      return true;
    } catch (_) {
      _snack('Couldn\'t send. Try again.');
      return false;
    }
  }

  Future<void> _openOnceMessage(VaultItem item) async {
    final session = ref.read(vaultSessionProvider.notifier);
    await session.markViewed(item);
    String text;
    try {
      text = await session.messageText(item);
    } catch (_) {
      text = 'Can\'t open this message.';
    }
    if (!mounted) return;
    await showVaultDialog<void>(
      context,
      (context) => AlertDialog(
        title: const Text('👁  Viewing once'),
        content: Text(text, style: const TextStyle(fontSize: 16, height: 1.4)),
        actions: [
          FilledButton(
            style: vaultButtonStyle(context, minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    await session.finishViewOnce(item);
  }

  // ---- Menu -----------------------------------------------------------------

  Future<void> _menu(String choice) async {
    switch (choice) {
      case 'code':
      case 'decoy':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VaultCodeChangeScreen(decoy: choice == 'decoy'),
          ),
        );
      case 'devices':
        await showVaultDevicesSheet(context);
      case 'wipe':
        await _wipe();
    }
  }

  Future<void> _wipe() async {
    final partner = ref.read(partnerNameProvider);
    final ok = await showVaultDialog<bool>(
      context,
      (context) => _WipeDialog(partnerName: partner),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    try {
      await ref.read(vaultSessionProvider.notifier).wipe();
      // Out of the vault altogether.
      navigator.maybePop();
    } catch (_) {
      _snack('Couldn\'t delete the vault. Check your connection.');
    }
  }

  Future<void> _approve(VaultDevice device) async {
    setState(() => _approving = device.id);
    try {
      await ref.read(vaultSessionProvider.notifier).approve(device);
    } catch (_) {
      _snack('Couldn\'t approve that phone. Try again.');
    } finally {
      if (mounted) setState(() => _approving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(vaultItemsProvider);
    final myUid = ref.watch(currentUidProvider);
    final partnerUid = ref.watch(
      coupleProvider.select((c) => c.value?.partnerIdFor(myUid)),
    );
    final partnerName = ref.watch(partnerNameProvider);
    final pending = [
      for (final d in ref.watch(vaultPendingDevicesProvider))
        if (!_later.contains(d.id)) d,
    ];
    final alerts = [
      for (final e in ref.watch(vaultAlertsProvider))
        // A new phone's own banner already says it.
        if (e.type != VaultEventType.deviceAdded || pending.isEmpty) e,
    ];
    final photos = [
      for (final i in items)
        if (i.kind == VaultItemKind.photo) i,
    ];
    final messages = [
      for (final i in items.reversed)
        if (i.kind == VaultItemKind.message) i,
    ];

    final banners = <Widget>[
      for (final d in pending)
        VaultApproveBanner(
          key: ValueKey('approve-${d.id}'),
          device: d,
          owner: d.uid == myUid ? 'your' : '$partnerName\'s',
          busy: _approving == d.id,
          onApprove: () => _approve(d),
          onLater: () => setState(() => _later.add(d.id)),
        ),
      for (final e in alerts)
        VaultAlertBanner(
          key: ValueKey('alert-${e.id}'),
          event: e,
          partnerName: partnerName,
          onDismiss: () =>
              ref.read(vaultSessionProvider.notifier).dismissEvent(e),
        ),
      if (_uploadLabel != null)
        VaultProgressBanner(label: _uploadLabel!, progress: _upload),
    ];

    return VaultBackdrop(
      stars: 10,
      child: DefaultTabController(
        length: 2,
        initialIndex: widget.initialTab,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 18, color: vaultGold),
                SizedBox(width: 8),
                VaultTitle('Private', size: 24, center: false),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.lock_outline),
                tooltip: 'Lock',
                onPressed: () => ref.read(vaultSessionProvider.notifier).lock(),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onSelected: _menu,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'code', child: Text('Change code')),
                  PopupMenuItem(
                    value: 'decoy',
                    child: Text('Change decoy code'),
                  ),
                  PopupMenuItem(value: 'devices', child: Text('Devices')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'wipe',
                    child: Text(
                      'Delete vault for both',
                      style: TextStyle(color: vaultBlush),
                    ),
                  ),
                ],
              ),
            ],
            bottom: const TabBar(
              indicatorColor: vaultGold,
              labelColor: Colors.white,
              unselectedLabelColor: vaultMuted,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                Tab(text: 'Photos'),
                Tab(text: 'Chat'),
              ],
            ),
          ),
          body: Column(
            children: [
              if (banners.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .4,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
                    itemCount: banners.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => banners[i],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    _PhotosTab(
                      photos: photos,
                      myUid: myUid,
                      partnerUid: partnerUid,
                      onAdd: _uploadLabel == null ? _addPhoto : null,
                      onOpen: _openPhoto,
                      onDelete: _delete,
                    ),
                    _ChatTab(
                      messages: messages,
                      myUid: myUid,
                      partnerUid: partnerUid,
                      partnerName: partnerName,
                      onSend: _send,
                      onOpenOnce: _openOnceMessage,
                      onDelete: _delete,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotosTab extends StatelessWidget {
  const _PhotosTab({
    required this.photos,
    required this.myUid,
    required this.partnerUid,
    required this.onAdd,
    required this.onOpen,
    required this.onDelete,
  });

  final List<VaultItem> photos;
  final String myUid;
  final String? partnerUid;
  final VoidCallback? onAdd;
  final ValueChanged<VaultItem> onOpen;
  final ValueChanged<VaultItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (photos.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.fromLTRB(40, 0, 40, 80),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('🌙', style: TextStyle(fontSize: 44)),
                  SizedBox(height: 12),
                  VaultTitle('Nothing here yet', size: 24),
                  SizedBox(height: 8),
                  VaultText(
                    'Photos are encrypted on this phone before they leave, '
                    'and never touch your gallery.',
                    size: 14,
                  ),
                ],
              ),
            ),
          )
        else
          GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) {
              final item = photos[photos.length - 1 - i];
              return VaultPhotoTile(
                key: ValueKey(item.id),
                item: item,
                myUid: myUid,
                partnerUid: partnerUid,
                onTap: () => onOpen(item),
                onLongPress: () => onDelete(item),
              );
            },
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Center(
            child: FilledButton.icon(
              style: vaultButtonStyle(
                context,
                minimumSize: const Size(160, 50),
              ),
              onPressed: onAdd,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Add photo'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatTab extends StatelessWidget {
  const _ChatTab({
    required this.messages,
    required this.myUid,
    required this.partnerUid,
    required this.partnerName,
    required this.onSend,
    required this.onOpenOnce,
    required this.onDelete,
  });

  /// Newest first.
  final List<VaultItem> messages;
  final String myUid;
  final String? partnerUid;
  final String partnerName;
  final Future<bool> Function(String, VaultPolicy) onSend;
  final ValueChanged<VaultItem> onOpenOnce;
  final ValueChanged<VaultItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('💌', style: TextStyle(fontSize: 44)),
                        const SizedBox(height: 12),
                        const VaultTitle('Just between you', size: 24),
                        const SizedBox(height: 8),
                        VaultText(
                          'Only you and $partnerName can read what\'s said '
                          'here.',
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final item = messages[i];
                    return VaultMessageBubble(
                      key: ValueKey(item.id),
                      item: item,
                      mine: item.senderId == myUid,
                      partnerUid: partnerUid,
                      onOpenOnce: () => onOpenOnce(item),
                      onLongPress: () => onDelete(item),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: VaultComposer(onSend: onSend),
          ),
        ),
      ],
    );
  }
}

/// "Delete vault for both": typed confirmation.
class _WipeDialog extends StatefulWidget {
  const _WipeDialog({required this.partnerName});

  final String partnerName;

  @override
  State<_WipeDialog> createState() => _WipeDialogState();
}

class _WipeDialogState extends State<_WipeDialog> {
  static const phrase = 'DELETE';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches => _controller.text.trim().toUpperCase() == phrase;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: vaultBlush),
      title: const Text('Delete the vault for both of you?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Every photo and message in Private is deleted for you and '
            '${widget.partnerName}, on every phone. This can\'t be undone.',
          ),
          const SizedBox(height: 14),
          const Text('Type DELETE to confirm.'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('vault-wipe-confirm'),
            controller: _controller,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: phrase),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(88, 40),
            backgroundColor: vaultBlush,
            foregroundColor: const Color(0xFF2A1430),
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete for both'),
        ),
      ],
    );
  }
}
