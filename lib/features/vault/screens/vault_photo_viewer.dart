import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/vault_session.dart';
import 'package:couple_app/features/vault/widgets/vault_items.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';

/// A vault photo, full screen, from bytes in memory.
///
/// A view-once photo sent by the partner says "Viewing once"; it is marked
/// viewed when opened and deleted (item and files) when this closes.
class VaultPhotoViewer extends ConsumerStatefulWidget {
  const VaultPhotoViewer({super.key, required this.item, this.onDelete});

  final VaultItem item;

  /// Deletes the photo for both (after asking).
  final Future<void> Function()? onDelete;

  @override
  ConsumerState<VaultPhotoViewer> createState() => _VaultPhotoViewerState();
}

class _VaultPhotoViewerState extends ConsumerState<VaultPhotoViewer> {
  late final VaultSession _session;
  late final bool _once;

  @override
  void initState() {
    super.initState();
    _session = ref.read(vaultSessionProvider.notifier);
    _once = _session.isViewOnceForMe(widget.item);
    if (_once) _session.markViewed(widget.item);
  }

  @override
  void dispose() {
    if (_once) _session.finishViewOnce(widget.item);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final myUid = ref.watch(currentUidProvider);
    final partnerUid = ref.watch(
      coupleProvider.select((c) => c.value?.partnerIdFor(myUid)),
    );
    final partnerName = ref.watch(partnerNameProvider);
    final sentOnce = item.policy == VaultPolicy.once && item.senderId == myUid;
    final seen = partnerUid != null && item.viewedByUid(partnerUid);

    final String? label;
    if (_once) {
      label = '👁  Viewing once';
    } else if (sentOnce) {
      label = seen ? '👁  $partnerName viewed it' : '👁  Not viewed yet';
    } else if (item.policy == VaultPolicy.day) {
      label = '⏳  Gone after a day';
    } else {
      label = null;
    }

    return VaultTheme(
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.black38,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: label == null
              ? null
              : Text(
                  label,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                ),
          actions: [
            if (widget.onDelete != null && !_once)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete for both',
                onPressed: widget.onDelete,
              ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: VaultSecureImage(
              item: item,
              full: true,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
