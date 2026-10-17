import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/widgets/empty_state.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/chat/data/chat_service.dart';
import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/chat/providers/chat_providers.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';

/// Searches the conversation's text messages. Pops with the id of the
/// message the user taps, so the chat can jump to it.
///
/// Firestore has no full-text search, so the most recent
/// [ChatService.searchWindow] messages are loaded once and matched on the
/// device.
class ChatSearchScreen extends ConsumerStatefulWidget {
  const ChatSearchScreen({super.key});

  @override
  ConsumerState<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends ConsumerState<ChatSearchScreen> {
  final _query = TextEditingController();
  late final String _myUid;
  late final Future<List<Message>> _messages = ref
      .read(chatServiceProvider)
      .fetchRecent(ref.read(currentCoupleIdProvider));

  @override
  void initState() {
    super.initState();
    _myUid = ref.read(currentUidProvider);
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<Message> _filter(List<Message> all) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return all
        .where(
          (m) =>
              (m.type == MessageType.text || m.type == MessageType.sticker) &&
              m.text.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final partnerName = ref.watch(partnerNameProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search messages',
            filled: false,
            border: InputBorder.none,
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: _query.clear,
                  ),
          ),
        ),
      ),
      body: FutureBuilder<List<Message>>(
        future: _messages,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const EmptyState(
              icon: Icons.cloud_off,
              text: 'Could not load messages to search.',
              padding: EdgeInsets.all(32),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_query.text.trim().isEmpty) {
            return const EmptyState(
              icon: Icons.search,
              text: 'Find words from your conversation.',
              padding: EdgeInsets.all(32),
            );
          }

          final results = _filter(snapshot.data!);
          if (results.isEmpty) {
            return EmptyState(
              icon: Icons.search_off,
              text: 'No messages with “${_query.text.trim()}”.',
              padding: const EdgeInsets.all(32),
            );
          }

          return ListView.separated(
            itemCount: results.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 16),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    '${results.length} '
                    '${results.length == 1 ? 'result' : 'results'}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              final message = results[index - 1];
              final who = message.senderId == _myUid ? 'You' : partnerName;
              final when = message.sentAt == null
                  ? ''
                  : DateFormat.yMMMd().add_jm().format(message.sentAt!);

              return ListTile(
                title: _Highlighted(
                  text: message.text,
                  query: _query.text.trim(),
                ),
                subtitle: Text('$who · $when'),
                onTap: () => Navigator.pop(context, message.id),
              );
            },
          );
        },
      ),
    );
  }
}

/// [text] with every case-insensitive match of [query] in bold.
class _Highlighted extends StatelessWidget {
  const _Highlighted({required this.text, required this.query});

  final String text;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final spans = <TextSpan>[];

    var start = 0;
    while (q.isNotEmpty) {
      final hit = lower.indexOf(q, start);
      if (hit < 0) break;
      if (hit > start) spans.add(TextSpan(text: text.substring(start, hit)));
      spans.add(
        TextSpan(
          text: text.substring(hit, hit + q.length),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      );
      start = hit + q.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));

    return Text.rich(
      TextSpan(style: theme.textTheme.bodyLarge, children: spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
