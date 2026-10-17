import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/chat/models/message.dart';
import 'package:couple_app/features/couple/models/couple.dart';

void main() {
  group('Couple', () {
    test('is incomplete until a second member joins', () {
      const solo = Couple(id: 'c1', inviteCode: 'AB12CD', memberIds: ['u1']);
      expect(solo.isComplete, isFalse);

      const paired = Couple(
        id: 'c1',
        inviteCode: 'AB12CD',
        memberIds: ['u1', 'u2'],
      );
      expect(paired.isComplete, isTrue);
    });

    test('resolves the partner id', () {
      const paired = Couple(
        id: 'c1',
        inviteCode: 'AB12CD',
        memberIds: ['u1', 'u2'],
      );
      expect(paired.partnerIdFor('u1'), 'u2');
      expect(paired.partnerIdFor('u2'), 'u1');
    });

    test('returns null partner when alone', () {
      const solo = Couple(id: 'c1', inviteCode: 'AB12CD', memberIds: ['u1']);
      expect(solo.partnerIdFor('u1'), isNull);
    });
  });

  group('Message', () {
    test('serializes a text message', () {
      const message = Message(
        id: 'm1',
        senderId: 'u1',
        type: MessageType.text,
        text: 'hello',
      );
      final map = message.toMap();

      expect(map['type'], 'text');
      expect(map['text'], 'hello');
      expect(map['senderId'], 'u1');
      expect(map['seen'], isFalse);
    });

    test('serializes an image message', () {
      const message = Message(
        id: 'm2',
        senderId: 'u2',
        type: MessageType.image,
        imageUrl: 'https://example.com/a.jpg',
        imageAspectRatio: 1.5,
      );
      final map = message.toMap();

      expect(map['type'], 'image');
      expect(map['imageUrl'], 'https://example.com/a.jpg');
      expect(map['imageAspectRatio'], 1.5);
    });
  });
}
