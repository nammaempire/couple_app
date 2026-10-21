import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/core/widgets/name_edit_dialog.dart';
import 'package:couple_app/features/app_lock/app_lock_controller.dart';
import 'package:couple_app/features/app_lock/widgets/app_lock_settings_sheet.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/providers/avatar_providers.dart';
import 'package:couple_app/features/avatar/screens/avatar_builder_screen.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/home/models/daily_question.dart';
import 'package:couple_app/features/home/providers/home_providers.dart';
import 'package:couple_app/features/onboarding/widgets/notification_prefs_sheet.dart';
import 'package:couple_app/features/onboarding/widgets/privacy_sheet.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';
import 'package:couple_app/features/us/widgets/archived_answer.dart';
import 'package:couple_app/features/us/widgets/settings_section_header.dart';
import 'package:couple_app/features/us/widgets/us_hero_card.dart';

/// Relationship settings and the archive of answered daily questions.
class UsScreen extends ConsumerWidget {
  const UsScreen({super.key});

  Future<void> _editMyName(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentUserProvider);
    final auth = ref.read(authServiceProvider);
    final name = await showNameEditDialog(
      context: context,
      title: 'Your name',
      label: 'Name',
      initialValue: me.displayName,
      helperText: 'This is what your partner sees by default.',
    );
    if (name == null || name.isEmpty) return;
    await auth.updateDisplayName(name);
  }

  Future<void> _editPartnerNickname(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentUserProvider);
    final couple = ref.read(coupleProvider).value!;
    final couples = ref.read(coupleServiceProvider);
    final nickname = await showNameEditDialog(
      context: context,
      title: 'What you call them',
      label: 'Nickname',
      initialValue: couple.nicknameChosenBy(me.uid),
      helperText:
          'Only changes what you see. They pick their own name for you.',
      allowEmpty: true,
    );
    if (nickname == null) return;
    await couples.setPartnerNickname(
      coupleId: couple.id,
      uid: me.uid,
      nickname: nickname,
    );
  }

  Future<void> _editCoupleName(BuildContext context, WidgetRef ref) async {
    final couple = ref.read(coupleProvider).value!;
    final couples = ref.read(coupleServiceProvider);
    final name = await showNameEditDialog(
      context: context,
      title: 'Name your space',
      label: 'Couple name',
      initialValue: couple.coupleName,
      helperText: 'You both see this name.',
      allowEmpty: true,
    );
    if (name == null) return;
    await couples.setCoupleName(coupleId: couple.id, name: name);
  }

  Future<void> _editNotifications(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentUserProvider);
    final auth = ref.read(authServiceProvider);
    final prefs = await showNotificationPrefsSheet(
      context,
      me.notificationPrefs,
    );
    if (prefs == null) return;
    await auth.saveNotificationPrefs(prefs);
  }

  Future<void> _showPrivacy(BuildContext context, WidgetRef ref) async {
    final alreadyReviewed = ref.read(currentUserProvider).privacyReviewed;
    final auth = ref.read(authServiceProvider);
    final ok = await showPrivacySheet(context);
    if (ok == true && !alreadyReviewed) await auth.markPrivacyReviewed();
  }

  Future<void> _pickDate(
    BuildContext context, {
    required String helpText,
    required DateTime? initial,
    required DateTime firstDate,
    required DateTime lastDate,
    required Future<void> Function(DateTime?) onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
    );
    if (picked == null) return;
    await onPicked(picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Services are fixed for the app's lifetime. Taken here so date-picker
    // callbacks, which run after an await, don't touch `ref` late.
    final auth = ref.read(authServiceProvider);
    final couples = ref.read(coupleServiceProvider);
    // MainShell only shows this tab once the couple has loaded.
    final couple = ref.watch(coupleProvider).value;
    if (couple == null) return const SizedBox.shrink();
    final me = ref.watch(currentUserProvider);
    final partnerName = ref.watch(partnerNameProvider);
    final history = ref.watch(questionHistoryProvider);
    final partnerUid = couple.partnerIdFor(me.uid);
    final appLock = ref.watch(appLockControllerProvider);
    final partner = ref.watch(partnerProvider).value;

    final theme = Theme.of(context);
    final startDate = couple.startDate;
    final meetup = couple.nextMeetup;

    var i = 0;
    Widget enter(Widget child) => EntranceAnimation(index: i++, child: child);

    return Scaffold(
      appBar: AppBar(title: const Text('Us')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          enter(
            UsHeroCard(
              title: couple.coupleName ?? '${me.displayName} & $partnerName',
              myName: me.displayName,
              partnerName: partnerName,
              me: me,
              partner: partner,
              startDate: startDate,
            ),
          ),

          enter(const SettingsSectionHeader(label: 'Our dates')),
          enter(
            GradientGroup(
              preset: GradientPreset.peach,
              children: [
                ListTile(
                  leading: const Icon(Icons.favorite_outline),
                  title: const Text('The day we started'),
                  subtitle: Text(
                    startDate == null
                        ? 'Not set'
                        : DateFormat.yMMMMd().format(startDate),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickDate(
                    context,
                    helpText: 'When did you two start?',
                    initial: startDate,
                    firstDate: DateTime(1970),
                    lastDate: DateTime.now(),
                    onPicked: (date) =>
                        couples.setStartDate(coupleId: couple.id, date: date),
                  ),
                ),

                ListTile(
                  leading: const Icon(Icons.flight_takeoff),
                  title: const Text('Next time we meet'),
                  subtitle: Text(
                    meetup == null
                        ? 'Not set'
                        : DateFormat.yMMMMd().format(meetup),
                  ),
                  trailing: meetup == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear',
                          onPressed: () => ref
                              .read(coupleServiceProvider)
                              .setNextMeetup(coupleId: couple.id, date: null),
                        ),
                  onTap: () => _pickDate(
                    context,
                    helpText: 'When do you see each other next?',
                    initial: meetup,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    onPicked: (date) =>
                        couples.setNextMeetup(coupleId: couple.id, date: date),
                  ),
                ),
              ],
            ),
          ),

          enter(const SettingsSectionHeader(label: 'Names')),
          enter(
            GradientGroup(
              preset: GradientPreset.lavender,
              children: [
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Our space'),
                  subtitle: Text(couple.coupleName ?? 'Not named yet'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editCoupleName(context, ref),
                ),

                ListTile(
                  leading: const Icon(Icons.favorite),
                  title: const Text('What you call them'),
                  subtitle: Text(
                    couple.nicknameChosenBy(me.uid) ?? partnerName,
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  enabled: couple.isComplete,
                  onTap: () => _editPartnerNickname(context, ref),
                ),

                ListTile(
                  leading: const Icon(Icons.local_florist_outlined),
                  title: const Text('What they call you'),
                  subtitle: Text(
                    partnerUid == null
                        ? 'Not paired yet'
                        : couple.nicknameChosenBy(partnerUid) ??
                              'They haven\'t picked one',
                  ),
                ),
              ],
            ),
          ),

          enter(const SettingsSectionHeader(label: 'Answered questions')),
          enter(
            GradientGroup(
              preset: GradientPreset.sunny,
              children: [
                Builder(
                  builder: (context) {
                    // Like a StreamBuilder's data: dropped after an error.
                    final entries = history.hasError
                        ? const <DailyQuestionEntry>[]
                        : history.value ?? const <DailyQuestionEntry>[];
                    if (entries.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Text(
                          'Once you both answer a daily question, it will be kept here.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: entries.map((entry) {
                        return ExpansionTile(
                          title: Text(
                            entry.prompt,
                            style: theme.textTheme.bodyMedium,
                          ),
                          subtitle: Text(
                            entry.dateKey,
                            style: theme.textTheme.labelSmall,
                          ),
                          children: [
                            ArchivedAnswer(
                              label: 'You',
                              text: entry.answerFor(me.uid)?.text ?? '',
                            ),
                            ArchivedAnswer(
                              label: partnerName,
                              text: partnerUid == null
                                  ? ''
                                  : entry.answerFor(partnerUid)?.text ?? '',
                            ),
                          ],
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          enter(const SettingsSectionHeader(label: 'Account')),
          enter(
            GradientGroup(
              preset: GradientPreset.ocean,
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Your name'),
                  subtitle: Text(me.displayName),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editMyName(context, ref),
                ),

                ListTile(
                  leading: me.avatar == null
                      ? const Icon(Icons.face_outlined)
                      : AvatarView(config: me.avatar!, size: 40),
                  title: const Text('Your avatar'),
                  subtitle: Text(
                    me.avatar == null ? 'Make your avatar' : 'Change your look',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AvatarBuilderScreen(),
                    ),
                  ),
                ),

                if (me.avatar != null)
                  SwitchListTile(
                    secondary: const Icon(Icons.account_circle_outlined),
                    title: const Text('Use avatar as profile picture'),
                    subtitle: Text(
                      me.photoUrl == null
                          ? 'Shown wherever your picture appears'
                          : 'Instead of your photo',
                    ),
                    value: me.showsAvatar,
                    onChanged: (value) async {
                      final avatars = ref.read(avatarServiceProvider);
                      try {
                        await avatars.setAsProfilePicture(
                          uid: me.uid,
                          value: value,
                        );
                      } catch (_) {
                        if (context.mounted) {
                          context.showSnackMessage(
                            'Couldn\'t update. Try again.',
                          );
                        }
                      }
                    },
                  ),

                ListTile(
                  leading: const Icon(Icons.cake_outlined),
                  title: const Text('Your birthday'),
                  subtitle: Text(
                    me.birthday == null
                        ? 'Not set'
                        : DateFormat.MMMMd().format(me.birthday!),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    final now = DateTime.now();
                    _pickDate(
                      context,
                      helpText: 'Your birthday',
                      initial:
                          me.birthday ??
                          DateTime(now.year - 25, now.month, now.day),
                      firstDate: DateTime(1920),
                      lastDate: now,
                      onPicked: auth.setBirthday,
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  title: const Text('Notifications'),
                  subtitle: const Text('Choose what you hear about'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editNotifications(context, ref),
                ),

                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Privacy'),
                  subtitle: const Text('Who can see what'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showPrivacy(context, ref),
                ),

                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('App lock'),
                  subtitle: Text(
                    appLock.enabled
                        ? 'On · ${appLock.delay.label.toLowerCase()}'
                        : 'Off',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showAppLockSheet(context),
                ),

                ListTile(
                  leading: const Icon(Icons.qr_code),
                  title: const Text('Invite code'),
                  subtitle: Text(couple.inviteCode),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: couple.inviteCode));
                      context.showSnackMessage('Code copied');
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          enter(
            Material(
              color: theme.colorScheme.errorContainer.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ListTileTheme(
                  data: const ListTileThemeData(
                    contentPadding: EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.logout,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(
                          'Sign out',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                        onTap: () => ref.read(authServiceProvider).signOut(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
