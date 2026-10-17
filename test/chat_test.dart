import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/core/utils/duration_format.dart';
import 'package:couple_app/features/chat/models/message.dart';

void main() {
  group('Message.previewText', () {
    test('describes each type', () {
      expect(
        const Message(
          id: '1',
          senderId: 'u',
          type: MessageType.text,
          text: 'hi',
        ).previewText,
        'hi',
      );
      expect(
        const Message(
          id: '1',
          senderId: 'u',
          type: MessageType.image,
        ).previewText,
        '📷 Photo',
      );
      expect(
        const Message(
          id: '1',
          senderId: 'u',
          type: MessageType.video,
        ).previewText,
        '🎥 Video',
      );
      expect(
        const Message(
          id: '1',
          senderId: 'u',
          type: MessageType.voice,
          durationMs: 65000,
        ).previewText,
        '🎤 Voice message (1:05)',
      );
      expect(
        const Message(
          id: '1',
          senderId: 'u',
          type: MessageType.call,
          isVideoCall: true,
          callOutcome: CallOutcome.missed,
        ).previewText,
        '📞 Missed video call',
      );
    });
  });

  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 7)), '0:07');
    expect(formatDuration(const Duration(minutes: 3, seconds: 24)), '3:24');
    expect(
      formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  group('Message.toMap', () {
    test('a reply carries a snapshot of the original', () {
      const original = Message(
        id: 'm1',
        senderId: 'u1',
        type: MessageType.voice,
        durationMs: 4000,
      );
      final reply = Message(
        id: '',
        senderId: 'u2',
        type: MessageType.text,
        text: 'aww',
        replyTo: ReplyPreview.of(original),
      );
      final map = reply.toMap();
      expect(map['replyTo'], {
        'messageId': 'm1',
        'senderId': 'u1',
        'type': 'voice',
        'text': '🎤 Voice message (0:04)',
      });
      expect(ReplyPreview.fromMap(map['replyTo'])!.type, MessageType.voice);
    });

    test('call records store type and outcome; others do not', () {
      const call = Message(
        id: '',
        senderId: 'u1',
        type: MessageType.call,
        callOutcome: CallOutcome.completed,
        durationMs: 60000,
      );
      final map = call.toMap();
      expect(map['type'], 'call');
      expect(map['callType'], 'voice');
      expect(map['callOutcome'], 'completed');
      expect(map['durationMs'], 60000);

      const text = Message(id: '', senderId: 'u1', type: MessageType.text);
      expect(text.toMap().containsKey('callType'), isFalse);
      expect(text.toMap().containsKey('replyTo'), isFalse);
    });
  });

  test('unknown types and outcomes fall back safely', () {
    expect(MessageType.fromId('hologram'), MessageType.text);
    expect(MessageType.fromId(null), MessageType.text);
    expect(CallOutcome.fromId('weird'), CallOutcome.missed);
  });

  test('couple reactions match the product spec', () {
    expect(CoupleReaction.values.map((r) => r.label), [
      'Love',
      'Miss you',
      'Hug',
      'Kiss',
      'Laugh',
    ]);
  });
}
