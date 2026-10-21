import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/data/auth_service.dart';
import 'package:couple_app/features/auth/models/app_user.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/couple/data/couple_service.dart';
import 'package:couple_app/features/couple/models/couple.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/onboarding/widgets/notification_prefs_sheet.dart';
import 'package:couple_app/features/onboarding/widgets/privacy_sheet.dart';
import 'package:couple_app/features/onboarding/widgets/romance_kit.dart';

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
        preset: GradientPreset.blush,
        doneLabel: _startDate == null
            ? null
            : 'Since ${DateFormat.yMMMMd().format(_startDate!)}',
        todoLabel: 'Starts your days-together counter',
        onTap: _setAnniversary,
      ),
      _ChecklistItem(
        icon: Icons.cake_outlined,
        title: 'Your birthday',
        preset: GradientPreset.peach,
        doneLabel: me.birthday == null
            ? null
            : DateFormat.MMMMd().format(me.birthday!),
        todoLabel: 'So your partner never forgets it',
        onTap: _setBirthday,
      ),
      _ChecklistItem(
        icon: Icons.notifications_none,
        title: 'Notifications',
        preset: GradientPreset.ocean,
        doneLabel: me.notificationsReviewed ? 'Preferences saved' : null,
        todoLabel: 'Choose what you want to hear about',
        onTap: _setNotifications,
      ),
      _ChecklistItem(
        icon: Icons.shield_outlined,
        title: 'Privacy',
        preset: GradientPreset.mint,
        doneLabel: me.privacyReviewed ? 'Reviewed' : null,
        todoLabel: 'See who can see what',
        onTap: _reviewPrivacy,
      ),
    ];
    final doneCount = items.where((i) => i.isDone).length;
    final allDone = doneCount == items.length;

    final b = theme.brightness;
    final dark = b == Brightness.dark;
    const hero = GradientPreset.festive;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: staggered([
                  AnimatedGradientCard(
                    preset: hero,
                    radius: 30,
                    padding: EdgeInsets.zero,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        Positioned.fill(
                          child: FloatingHearts(
                            count: 10,
                            style: ParticleStyle.confetti,
                            opacity: dark ? .35 : .45,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
                          child: Column(
                            children: [
                              const GlowBadge(
                                preset: GradientPreset.blush,
                                size: 68,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'You\'re connected!',
                                textAlign: TextAlign.center,
                                style:
                                    romanceSerif(
                                      theme.textTheme.headlineMedium,
                                    ).copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontStyle: FontStyle.italic,
                                      color: hero.foreground(b),
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
                                  color: hero.foregroundMuted(b),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(
                                    alpha: dark ? .1 : .6,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: TweenAnimationBuilder<double>(
                                          tween: Tween(
                                            end: doneCount / items.length,
                                          ),
                                          duration: const Duration(
                                            milliseconds: 500,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          builder: (context, v, _) =>
                                              LinearProgressIndicator(
                                                value: v,
                                                minHeight: 8,
                                                color: dark
                                                    ? hero.accent(b)
                                                    : hero.ink,
                                                backgroundColor: hero
                                                    .foreground(b)
                                                    .withValues(alpha: .12),
                                              ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '$doneCount of ${items.length}',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: hero.foreground(b),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  ...items,
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _finishing ? null : _finish,
                    style: pillButtonStyle(context),
                    child: _finishing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(allDone ? 'Start exploring' : 'Continue'),
                  ),
                  if (!allDone) ...[
                    const SizedBox(height: 10),
                    Text(
                      'You can finish these any time from the Us tab.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ]),
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
    required this.preset,
    required this.doneLabel,
    required this.todoLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final GradientPreset preset;

  /// Summary once done; null means still to do.
  final String? doneLabel;
  final String todoLabel;
  final VoidCallback onTap;

  bool get isDone => doneLabel != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final accent = preset.isDarkIn(b) ? preset.accent(b) : preset.ink;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedGradientCard(
        preset: preset,
        onTap: onTap,
        radius: 22,
        sheen: !isDone,
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        child: Row(
          children: [
            IconTile(icon: icon, preset: preset),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: preset.foreground(b),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    doneLabel ?? todoLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: preset.foregroundMuted(b),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, a) =>
                  ScaleTransition(scale: a, child: child),
              child: isDone
                  ? Icon(
                      Icons.check_circle_rounded,
                      key: const ValueKey('done'),
                      color: accent,
                      size: 28,
                    )
                  : Icon(
                      Icons.radio_button_unchecked_rounded,
                      key: const ValueKey('todo'),
                      color: preset.foregroundMuted(b),
                      size: 26,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
