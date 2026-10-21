import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/features/vault/models/vault_item.dart';
import 'package:couple_app/features/vault/providers/vault_providers.dart';
import 'package:couple_app/features/vault/vault_session.dart';
import 'package:couple_app/features/vault/widgets/vault_look.dart';
import 'package:couple_app/features/vault/widgets/vault_policy.dart';

/// A vault photo decrypted into memory (never a file or the disk cache):
/// the thumbnail, or the full photo when [full].
class VaultSecureImage extends ConsumerStatefulWidget {
  const VaultSecureImage({
    super.key,
    required this.item,
    this.full = false,
    this.fit = BoxFit.cover,
  });

  final VaultItem item;
  final bool full;
  final BoxFit fit;

  @override
  ConsumerState<VaultSecureImage> createState() => _VaultSecureImageState();
}

class _VaultSecureImageState extends ConsumerState<VaultSecureImage> {
  late Future<MemoryImage> _image;

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(VaultSecureImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id || oldWidget.full != widget.full) {
      _image = _load();
    }
  }

  Future<MemoryImage> _load() {
    final session = ref.read(vaultSessionProvider.notifier);
    return widget.full
        ? session.photo(widget.item)
        : session.thumbnail(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MemoryImage>(
      future: _image,
      builder: (context, snap) {
        final image = snap.data;
        if (image != null) {
          return Image(
            image: image,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const _ImageProblem(),
          );
        }
        if (snap.hasError) return const _ImageProblem();
        return const Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: vaultGold),
          ),
        );
      },
    );
  }
}

class _ImageProblem extends StatelessWidget {
  const _ImageProblem();

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(Icons.lock_clock_outlined, color: Colors.white38, size: 28),
  );
}

/// One square in the photo grid: the decrypted thumbnail with a 👁 / ⏳
/// badge. A view-once photo for this user stays covered until opened.
class VaultPhotoTile extends StatelessWidget {
  const VaultPhotoTile({
    super.key,
    required this.item,
    required this.myUid,
    required this.partnerUid,
    required this.onTap,
    required this.onLongPress,
  });

  final VaultItem item;
  final String myUid;
  final String? partnerUid;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final covered = item.policy == VaultPolicy.once && item.senderId != myUid;
    final partner = partnerUid;
    final seen =
        item.senderId == myUid &&
        item.policy == VaultPolicy.once &&
        partner != null &&
        item.viewedByUid(partner);

    return Semantics(
      button: true,
      label: covered ? 'View-once photo' : 'Photo',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.white.withValues(alpha: .06),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (covered)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3C2F7E), Color(0xFF5C2A47)],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('👁', style: TextStyle(fontSize: 26)),
                        SizedBox(height: 4),
                        Text(
                          'View once',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  VaultSecureImage(item: item),
                if (!covered && item.policy != VaultPolicy.keep)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: VaultPolicyBadge(policy: item.policy, size: 24),
                  ),
                if (seen)
                  const Positioned(
                    left: 6,
                    bottom: 6,
                    child: _Chip(label: 'Viewed'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xCC15173A),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontSize: 11),
    ),
  );
}

/// A message bubble. A view-once message for this user shows "Tap to read
/// once" and is only decrypted when opened.
class VaultMessageBubble extends ConsumerStatefulWidget {
  const VaultMessageBubble({
    super.key,
    required this.item,
    required this.mine,
    required this.partnerUid,
    required this.onOpenOnce,
    required this.onLongPress,
  });

  final VaultItem item;
  final bool mine;
  final String? partnerUid;
  final VoidCallback onOpenOnce;
  final VoidCallback onLongPress;

  @override
  ConsumerState<VaultMessageBubble> createState() => _VaultMessageBubbleState();
}

class _VaultMessageBubbleState extends ConsumerState<VaultMessageBubble> {
  Future<String>? _text;

  bool get _covered => !widget.mine && widget.item.policy == VaultPolicy.once;

  @override
  void initState() {
    super.initState();
    if (!_covered) {
      _text = ref.read(vaultSessionProvider.notifier).messageText(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final mine = widget.mine;
    final now = ref.watch(vaultClockProvider)();
    final partner = widget.partnerUid;
    final seen =
        mine &&
        item.policy == VaultPolicy.once &&
        partner != null &&
        item.viewedByUid(partner);

    final meta = <String>[
      if (item.createdAt != null) DateFormat.jm().format(item.createdAt!),
      if (item.policy == VaultPolicy.day && item.expiresAt != null)
        '⏳ ${vaultTimeLeft(item.expiresAt!, now)}',
      if (mine && item.policy == VaultPolicy.once)
        seen ? '👁 Viewed' : '👁 View once',
    ];

    final Widget body;
    if (_covered) {
      body = const Text(
        '👁  Tap to read once',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      );
    } else {
      body = FutureBuilder<String>(
        future: _text,
        builder: (context, snap) => Text(
          snap.data ?? (snap.hasError ? 'Can\'t open this message' : '…'),
          style: TextStyle(
            color: mine ? const Color(0xFF2A1430) : Colors.white,
            fontSize: 15,
            height: 1.35,
          ),
        ),
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .76,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Material(
                color: mine
                    ? vaultBlush
                    : _covered
                    ? const Color(0xFF4A3480)
                    : Colors.white.withValues(alpha: .1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(mine ? 20 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 20),
                  ),
                  side: mine
                      ? BorderSide.none
                      : BorderSide(color: Colors.white.withValues(alpha: .12)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _covered ? widget.onOpenOnce : null,
                  onLongPress: widget.onLongPress,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: body,
                  ),
                ),
              ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 3, 6, 0),
                  child: Text(
                    meta.join(' · '),
                    style: const TextStyle(color: vaultMuted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The chat's text field, a "how long" button and send.
class VaultComposer extends StatefulWidget {
  const VaultComposer({super.key, required this.onSend});

  /// Sends; resolves to false if it failed (the text is kept).
  final Future<bool> Function(String text, VaultPolicy policy) onSend;

  @override
  State<VaultComposer> createState() => _VaultComposerState();
}

class _VaultComposerState extends State<VaultComposer> {
  final _controller = TextEditingController();
  VaultPolicy _policy = VaultPolicy.keep;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickPolicy() async {
    final picked = await showVaultPolicyPicker(context, current: _policy);
    if (picked != null && mounted) setState(() => _policy = picked);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final ok = await widget.onSend(text, _policy);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        _controller.clear();
        _policy = VaultPolicy.keep;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return VaultCard(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'How long it lasts: ${_policy.label}',
            onPressed: _pickPolicy,
            icon: _policy.badge == null
                ? const Icon(Icons.all_inclusive, color: vaultMuted)
                : Text(_policy.badge!, style: const TextStyle(fontSize: 20)),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              maxLength: VaultMessageContent.maxLength,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _policy == VaultPolicy.keep
                    ? 'Message'
                    : 'Message · ${_policy.label.toLowerCase()}',
                hintStyle: const TextStyle(color: Colors.white38),
                counterText: '',
                filled: false,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          IconButton(
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send_rounded, color: vaultGold),
          ),
        ],
      ),
    );
  }
}
