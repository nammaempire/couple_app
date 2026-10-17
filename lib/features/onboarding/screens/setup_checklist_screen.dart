import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/notification_prefs_sheet.dart';
import 'package:couple_app/features/onboarding/widgets/privacy_sheet.dart';

/// Shown once, right after both partners connect: a short checklist of
/// things that make the space feel like theirs. Everything is skippable.
class SetupChecklistScreen extends ConsumerStatefulWidget {
  const SetupChecklistScreen({
    super.key,
    required this.me,
    required this.couple,
  });

  /// Live profile; the checklist ticks items off as they are saved.
  final AppUser me;
  final Couple couple;

  @override
  ConsumerState<SetupChecklistScreen> createState() =>
      _SetupChecklistScreenState();
}

class _SetupChecklistScreenState extends ConsumerState<SetupChecklistScreen> {
  late final AuthService _auth;
  late final CoupleService _couples;

  @override
  void initState() {
    super.initState();
    _auth = ref.read(authServiceProvider);
    _couples = ref.read(coupleServiceProvider);
  }

  // The couple document is watched by AuthGate, but the anniversary is shown
  // optimistically so the tick appears immediately.
  DateTime? _startDateOverride;
  bool _finishing = false;

  DateTime? get _startDate => _startDateOverride ?? widget.couple.startDate;

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      context.showSnackMessage('Could not save that. Try again.');
    }
  }

  Future<void> _setAnniversary() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
      helpText: 'When did you two start?',
    );
    if (picked == null) return;
    setState(() => _startDateOverride = picked);
    await _guard(
      () => _couples.setStartDate(coupleId: widget.couple.id, date: picked),
    );
  }

  Future<void> _setBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          widget.me.birthday ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Your birthday',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (picked == null) return;
    await _guard(() => _auth.setBirthday(picked));
  }

  Future<void> _setNotifications() async {
    final prefs = await showNotificationPrefsSheet(
      context,
      widget.me.notificationPrefs,
    );
    if (prefs == null) return;
    await _guard(() => _auth.saveNotificationPrefs(prefs));
  }

  Future<void> _reviewPrivacy() async {
    final ok = await showPrivacySheet(context);
    if (ok != true) return;
    await _guard(_auth.markPrivacyReviewed);
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    await _guard(_auth.completeSetup);
    // AuthGate moves to the main app once `setupComplete` lands.
    if (mounted) setState(() => _finishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = widget.me;

    final items = [
      _ChecklistItem(
        icon: Icons.favorite_outline,
        title: 'Your anniversary',
        doneLabel: _startDate == null
            ? null
            : 'Since ${DateFormat.yMMMMd().format(_startDate!)}',
        todoLabel: 'Starts your days-together counter',
        onTap: _setAnniversary,
      ),
      _ChecklistItem(
        icon: Icons.cake_outlined,
        title: 'Your birthday',
        doneLabel: me.birthday == null
            ? null
            : DateFormat.MMMMd().format(me.birthday!),
        todoLabel: 'So your partner never forgets it',
        onTap: _setBirthday,
      ),
      _ChecklistItem(
        icon: Icons.notifications_none,
        title: 'Notifications',
        doneLabel: me.notificationsReviewed ? 'Preferences saved' : null,
        todoLabel: 'Choose what you want to hear about',
        onTap: _setNotifications,
      ),
      _ChecklistItem(
        icon: Icons.shield_outlined,
        title: 'Privacy',
        doneLabel: me.privacyReviewed ? 'Reviewed' : null,
        todoLabel: 'See who can see what',
        onTap: _reviewPrivacy,
      ),
    ];
    final doneCount = items.where((i) => i.isDone).length;
    final allDone = doneCount == items.length;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.favorite,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You\'re connected!',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.couple.coupleName == null
                        ? 'A few quick things to make this space yours.'
                        : 'A few quick things to make '
                              '“${widget.couple.coupleName}” yours.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: doneCount / items.length,
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$doneCount of ${items.length}',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...items,
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _finishing ? null : _finish,
                    child: _finishing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(allDone ? 'Start exploring' : 'Continue'),
                  ),
                  if (!allDone) ...[
                    const SizedBox(height: 8),
                    Text(
                      'You can finish these any time from the Us tab.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.icon,
    required this.title,
    required this.doneLabel,
    required this.todoLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;

  /// Summary once done; null means still to do.
  final String? doneLabel;
  final String todoLabel;
  final VoidCallback onTap;

  bool get isDone => doneLabel != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isDone
            ? scheme.primaryContainer.withValues(alpha: .45)
            : scheme.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        doneLabel ?? todoLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isDone
                      ? Icon(
                          Icons.check_circle,
                          key: const ValueKey('done'),
                          color: scheme.primary,
                        )
                      : Icon(
                          Icons.radio_button_unchecked,
                          key: const ValueKey('todo'),
                          color: scheme.outline,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
