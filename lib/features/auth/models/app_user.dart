import 'package:couple_app/core/backend/backend.dart';

import 'package:couple_app/features/avatar/models/avatar_config.dart';

/// Which kinds of notification this user wants. Saved during onboarding so
/// they are ready when push notifications ship.
class NotificationPrefs {
  final bool messages;
  final bool mood;
  final bool dailyQuestion;
  final bool dates;

  /// Silence everything between 22:00 and 07:00.
  final bool quietHours;

  const NotificationPrefs({
    this.messages = true,
    this.mood = true,
    this.dailyQuestion = true,
    this.dates = true,
    this.quietHours = false,
  });

  factory NotificationPrefs.fromMap(Map<String, dynamic>? map) {
    final m = map ?? const <String, dynamic>{};
    return NotificationPrefs(
      messages: (m['messages'] as bool?) ?? true,
      mood: (m['mood'] as bool?) ?? true,
      dailyQuestion: (m['dailyQuestion'] as bool?) ?? true,
      dates: (m['dates'] as bool?) ?? true,
      quietHours: (m['quietHours'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'messages': messages,
    'mood': mood,
    'dailyQuestion': dailyQuestion,
    'dates': dates,
    'quietHours': quietHours,
  };

  NotificationPrefs copyWith({
    bool? messages,
    bool? mood,
    bool? dailyQuestion,
    bool? dates,
    bool? quietHours,
  }) {
    return NotificationPrefs(
      messages: messages ?? this.messages,
      mood: mood ?? this.mood,
      dailyQuestion: dailyQuestion ?? this.dailyQuestion,
      dates: dates ?? this.dates,
      quietHours: quietHours ?? this.quietHours,
    );
  }
}

/// A signed-in user of the app.
class AppUser {
  final String uid;
  final String displayName;
  final String? photoUrl;

  /// What this person likes to be called, if different from their name.
  final String? nickname;

  final DateTime? birthday;

  /// Id of the couple document this user belongs to, or null if unpaired.
  final String? coupleId;

  /// Finished the "about you" onboarding step.
  final bool profileComplete;

  /// Finished (or skipped) the post-pairing setup checklist.
  final bool setupComplete;

  /// Has opened the privacy explainer in the setup checklist.
  final bool privacyReviewed;

  final NotificationPrefs notificationPrefs;

  /// Notification preferences have been reviewed at least once.
  final bool notificationsReviewed;

  /// Their cartoon avatar, if they have made one (`users/{uid}.avatar`).
  final AvatarConfig? avatar;

  /// Show the avatar instead of the photo as their profile picture. When
  /// unset, the avatar is used only if there is no photo.
  final bool? avatarAsPhoto;

  /// "Clear chat for me": messages sent at or before this (server time) are
  /// hidden on this account only.
  final DateTime? chatClearedAt;

  /// When they confirmed they are 18 or older, for the private vault, if
  /// they have no birthday set (`users/{uid}.adultConfirmedAt`).
  final DateTime? adultConfirmedAt;

  /// Their verified mobile number in E.164 form (`+919876543210`), if they
  /// signed in with it or added it.
  final String? phone;

  /// "Mute my partner" while a pairing is ending: no alerts, banners or
  /// badges for the partner's activity, and their calls are not rung.
  final bool mutePartner;

  /// Set by the server when this user's pairing ended; cleared once they
  /// have seen the "your pairing has ended" screen.
  final DateTime? pairingEndedAt;

  /// How it ended: `agreed`, `oneSided` or `leftNow`.
  final String? pairingEndedHow;

  /// Whether their profile picture should be drawn as the avatar.
  bool get showsAvatar =>
      avatar != null && (avatarAsPhoto ?? (photoUrl == null));

  const AppUser({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.nickname,
    this.birthday,
    this.coupleId,
    this.profileComplete = true,
    this.setupComplete = true,
    this.privacyReviewed = false,
    this.notificationPrefs = const NotificationPrefs(),
    this.notificationsReviewed = false,
    this.avatar,
    this.avatarAsPhoto,
    this.chatClearedAt,
    this.adultConfirmedAt,
    this.phone,
    this.mutePartner = false,
    this.pairingEndedAt,
    this.pairingEndedHow,
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUser.fromMap(doc.id, doc.data() ?? <String, dynamic>{});
  }

  /// Accounts created before onboarding existed have no `profileComplete` or
  /// `setupComplete` fields. Anyone already paired is treated as done, so
  /// existing couples are not sent back through the flow.
  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    final coupleId = data['coupleId'] as String?;
    final legacyDone = coupleId != null;
    final prefs = data['notificationPrefs'];

    return AppUser(
      uid: uid,
      displayName: (data['displayName'] as String?) ?? 'Me',
      photoUrl: data['photoUrl'] as String?,
      nickname: data['nickname'] as String?,
      birthday: (data['birthday'] as Timestamp?)?.toDate(),
      coupleId: coupleId,
      profileComplete: (data['profileComplete'] as bool?) ?? legacyDone,
      setupComplete: (data['setupComplete'] as bool?) ?? legacyDone,
      privacyReviewed: (data['privacyReviewed'] as bool?) ?? false,
      notificationPrefs: NotificationPrefs.fromMap(
        prefs is Map<String, dynamic> ? prefs : null,
      ),
      notificationsReviewed: prefs is Map<String, dynamic>,
      avatar: AvatarConfig.fromMap(data['avatar']),
      avatarAsPhoto: data['avatarAsPhoto'] as bool?,
      chatClearedAt: (data['chatClearedAt'] as Timestamp?)?.toDate(),
      adultConfirmedAt: (data['adultConfirmedAt'] as Timestamp?)?.toDate(),
      phone: data['phone'] as String?,
      mutePartner: (data['mutePartner'] as bool?) ?? false,
      pairingEndedAt: (data['pairingEndedAt'] as Timestamp?)?.toDate(),
      pairingEndedHow: data['pairingEndedHow'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'photoUrl': photoUrl,
    'coupleId': coupleId,
  };

  AppUser copyWith({String? displayName, String? photoUrl, String? coupleId}) {
    return AppUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      nickname: nickname,
      birthday: birthday,
      coupleId: coupleId ?? this.coupleId,
      profileComplete: profileComplete,
      setupComplete: setupComplete,
      privacyReviewed: privacyReviewed,
      notificationPrefs: notificationPrefs,
      notificationsReviewed: notificationsReviewed,
      avatar: avatar,
      avatarAsPhoto: avatarAsPhoto,
      chatClearedAt: chatClearedAt,
      adultConfirmedAt: adultConfirmedAt,
      phone: phone,
      mutePartner: mutePartner,
      pairingEndedAt: pairingEndedAt,
      pairingEndedHow: pairingEndedHow,
    );
  }
}
