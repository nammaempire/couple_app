import 'package:flutter_test/flutter_test.dart';

import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/couple/models/invite.dart';

void main() {
  group('InviteCode.extract', () {
    test('accepts a bare code, any case', () {
      expect(InviteCode.extract('ABC234'), 'ABC234');
      expect(InviteCode.extract('  abc234 '), 'ABC234');
    });

    test('reads the QR payload', () {
      expect(InviteCode.extract(InviteCode.qrPayload('XYZ789')), 'XYZ789');
    });

    test('finds the code in the shared invite message', () {
      const message =
          'Join me on Us 💞\n\nIt\'s a private space just for the '
          'two of us. Install the app, tap "I have an invite" and enter our '
          'code: HJK456';
      expect(InviteCode.extract(message), 'HJK456');
    });

    test('ignores six-letter words that are not labelled as a code', () {
      expect(InviteCode.extract('Please INVITE me'), isNull);
    });

    test('rejects ambiguous characters and wrong lengths', () {
      expect(InviteCode.extract('ABC10O'), isNull); // 1, 0 and O are excluded
      expect(InviteCode.extract('ABC23'), isNull);
      expect(InviteCode.extract('ABC2345'), isNull);
      expect(InviteCode.extract(null), isNull);
    });
  });

  group('AppUser onboarding flags', () {
    test('new profiles must go through onboarding', () {
      final user = AppUser.fromMap('u1', {
        'displayName': 'Asha',
        'coupleId': null,
        'profileComplete': false,
        'setupComplete': false,
      });
      expect(user.profileComplete, isFalse);
      expect(user.setupComplete, isFalse);
    });

    test('existing paired accounts skip onboarding', () {
      final user = AppUser.fromMap('u1', {
        'displayName': 'Asha',
        'coupleId': 'c1',
      });
      expect(user.profileComplete, isTrue);
      expect(user.setupComplete, isTrue);
    });

    test('existing unpaired accounts fill in their profile', () {
      final user = AppUser.fromMap('u1', {'displayName': 'Asha'});
      expect(user.profileComplete, isFalse);
    });

    test('notification prefs default on, and track whether reviewed', () {
      final fresh = AppUser.fromMap('u1', {'displayName': 'Asha'});
      expect(fresh.notificationPrefs.messages, isTrue);
      expect(fresh.notificationPrefs.quietHours, isFalse);
      expect(fresh.notificationsReviewed, isFalse);

      final saved = AppUser.fromMap('u1', {
        'displayName': 'Asha',
        'notificationPrefs': {'messages': false, 'quietHours': true},
      });
      expect(saved.notificationPrefs.messages, isFalse);
      expect(saved.notificationPrefs.quietHours, isTrue);
      expect(saved.notificationsReviewed, isTrue);
    });
  });
}
