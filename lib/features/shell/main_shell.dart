import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/push/push_service.dart';
import 'package:couple_app/core/services/haptics.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/calls/widgets/incoming_call_listener.dart';
import 'package:couple_app/features/chat/screens/chat_screen.dart';
import 'package:couple_app/features/couple/providers/couple_providers.dart';
import 'package:couple_app/features/couple/providers/separation_providers.dart';
import 'package:couple_app/features/home/models/love_tap.dart';
import 'package:couple_app/features/home/models/nudge.dart';
import 'package:couple_app/features/home/providers/home_providers.dart';
import 'package:couple_app/features/home/screens/home_screen.dart';
import 'package:couple_app/features/home/widgets/love_burst.dart';
import 'package:couple_app/features/memories/screens/memories_screen.dart';
import 'package:couple_app/features/music/widgets/listening_banner.dart';
import 'package:couple_app/features/security/widgets/device_check_listener.dart';
import 'package:couple_app/features/security/widgets/security_banners.dart';
import 'package:couple_app/features/shell/tab_badges.dart';
import 'package:couple_app/features/plans/providers/date_plan_providers.dart';
import 'package:couple_app/features/premium/providers/premium_providers.dart';
import 'package:couple_app/features/play/game_catalog.dart';
import 'package:couple_app/features/play/models/game.dart';
import 'package:couple_app/features/play/providers/play_providers.dart';
import 'package:couple_app/features/play/screens/play_hub_screen.dart';
import 'package:couple_app/features/together/data/event_service.dart';
import 'package:couple_app/features/together/data/reminder_planner.dart';
import 'package:couple_app/features/together/data/reminder_service.dart';
import 'package:couple_app/features/together/models/love_note.dart';
import 'package:couple_app/features/together/providers/together_providers.dart';
import 'package:couple_app/features/together/screens/together_screen.dart';
import 'package:couple_app/features/us/screens/us_screen.dart';

/// Bottom-navigation shell: Home, Chat, Memories, Together, Play and Us.
///
/// It keeps the couple, partner, calendar and love-note providers alive, and
/// owns the incoming-nudge and call listeners and the on-device reminder
/// sync, so all of them work no matter which tab is on screen.
///
/// While the partner is muted ([mutePartnerProvider]) their nudges, game
/// invites and listening banner stay quiet, the Play badge is hidden and
/// their calls are not rung. It also finishes an ending pairing on the
/// server once its date has passed ([SeparationFinalizer]).
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  static const _homeTab = 0;
  static const _chatTab = 1;
  static const _memoriesTab = 2;
  static const _togetherTab = 3;
  static const _playTab = 4;

  int _tabIndex = _homeTab;
  final _togetherKey = GlobalKey<TogetherScreenState>();

  /// The auth gate rebuilds the shell under a new key when the user or the
  /// couple changes, so both stay fixed for this state's lifetime.
  late final String _myUid;
  late final String _coupleId;

  Timer? _reminderDebounce;
  String? _lastReminderSignature;

  StreamSubscription<Nudge?>? _nudgeSub;
  String? _lastNudgeId;

  @override
  void initState() {
    super.initState();
    _myUid = ref.read(currentUidProvider);
    _coupleId = ref.read(currentCoupleIdProvider);
    _listenForNudges();
    _listenForGameInvites();
    _listenForPlans();
    _listenForSeparation();
    _listenForLoveNotes();
    _listenForBadges();
    // Lets the partner's love taps, messages and calls buzz this phone
    // even when the app is closed.
    unawaited(PushService.instance.start(_myUid));
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markOpenTabSeen();
      unawaited(ref.read(separationFinalizerProvider.notifier).check());
      // Paid purchases the server couldn't confirm yet.
      unawaited(
        ref
            .read(purchaseControllerProvider.notifier)
            .retryPending()
            .catchError((Object _) {}),
      );
    }
  }

  /// Finishes an ending pairing once its date has passed (on open, on every
  /// change, and on coming back to the app), and clears pushed screens once
  /// this user is no longer paired, so nothing is left over the next one.
  void _listenForSeparation() {
    void check() {
      if (!mounted) return;
      unawaited(ref.read(separationFinalizerProvider.notifier).check());
    }

    // Keeps the finalizer (and its retry timer) alive with the shell.
    ref.listenManual(separationFinalizerProvider, (_, _) {});
    ref.listenManual(
      coupleProvider.select(
        (c) => (c.value?.separation?.effectiveAt, c.value?.ending != null),
      ),
      (_, _) => check(),
    );
    // Not during initState: the first check may update the finalizer.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      check();
      // Listen for purchases, send any still waiting for the server, and
      // re-verify an active subscription in case a renewal was missed.
      if (!mounted) return;
      unawaited(
        ref
            .read(purchaseControllerProvider.notifier)
            .start(_coupleId, refresh: true)
            .catchError((Object _) {}),
      );
    });

    ref.listenManual(currentUserProvider.select((u) => u.coupleId), (
      _,
      coupleId,
    ) {
      if (coupleId == null && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  /// Re-plans reminders whenever anything they depend on changes: the
  /// user's own profile (notification preferences, birthday), the couple
  /// (anniversary, meetup, nickname), the partner's profile, calendar events
  /// and incoming love notes.
  void _listenForPlans() {
    void schedule(Object? previous, Object? next) => _scheduleReminderSync();
    void ignore(Object error, StackTrace stack) {}
    ref.listenManual(currentUserProvider, schedule, onError: ignore);
    ref.listenManual(coupleProvider, schedule, onError: ignore);
    ref.listenManual(partnerProvider, schedule, onError: ignore);
    ref.listenManual(eventsProvider, schedule, onError: ignore);
    ref.listenManual(incomingNotesProvider, schedule, onError: ignore);
    ref.listenManual(datePlanCalendarEventsProvider, schedule, onError: ignore);
  }

  /// Re-plans this phone's reminders shortly after anything they depend on
  /// changes, batching bursts of updates.
  void _scheduleReminderSync() {
    _reminderDebounce?.cancel();
    _reminderDebounce = Timer(const Duration(seconds: 2), _syncReminders);
  }

  Future<void> _syncReminders() async {
    if (!mounted) return;
    final couple = ref.read(coupleProvider).value;
    if (couple == null) return;

    final me = ref.read(currentUserProvider);
    final partnerName = ref.read(partnerNameProvider);
    final reminders = ReminderPlanner.plan(
      now: DateTime.now(),
      events: [
        ...ref.read(eventsProvider).value ?? const [],
        ...ref.read(datePlanCalendarEventsProvider),
        ...EventService.automaticEvents(
          couple: couple,
          me: me,
          partner: ref.read(partnerProvider).value,
          partnerName: partnerName,
        ),
      ],
      incomingNotes: ref.read(incomingNotesProvider).value ?? const [],
      prefs: me.notificationPrefs,
      partnerName: partnerName,
    );

    // Skip the platform work when nothing changed.
    final signature = reminders
        .map((r) => '${r.id}@${r.at.millisecondsSinceEpoch}:${r.title}')
        .join('|');
    if (signature == _lastReminderSignature) return;
    final ok = await ReminderService.instance.sync(reminders);
    // Remembered only once applied, so a failed sync is retried next time.
    if (ok) _lastReminderSignature = signature;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nudgeSub?.cancel();
    _reminderDebounce?.cancel();
    super.dispose();
  }

  void _listenForNudges() {
    final nudges = ref.read(nudgeServiceProvider);
    _nudgeSub = nudges.watchLatest(_coupleId).listen((nudge) {
      if (nudge == null || !mounted) return;

      // Ignore the first value on start-up and our own nudges, and only react
      // to ones that arrived just now rather than replaying history.
      final isFirstEmission = _lastNudgeId == null;
      final isNew = nudge.id != _lastNudgeId;
      _lastNudgeId = nudge.id;

      if (isFirstEmission || !isNew) return;
      if (nudge.senderId == _myUid) return;
      if (!nudge.isFresh) return;
      if (ref.read(mutePartnerProvider)) return;

      _playNudge(nudge.kind);
    });
  }

  /// A love note from the partner while the app is open: a buzz and a
  /// banner (with the app closed, the push notification plays its chime).
  void _listenForLoveNotes() {
    Set<String>? known;
    ref.listenManual(incomingNotesProvider, (previous, next) {
      final notes = next.value;
      if (notes == null) return;
      final ids = notes.map((n) => n.id).toSet();
      final fresh = known == null
          ? const <LoveNote>[]
          : notes.where((n) => !known!.contains(n.id)).toList();
      known = ids;
      if (fresh.isEmpty || !mounted) return;
      if (ref.read(mutePartnerProvider)) return;
      final note = fresh.first;
      final partnerName = ref.read(partnerNameProvider);
      final now = DateTime.now();
      unawaited(Haptics.buzz());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Text(
            note.isDelivered(now)
                ? '💌  $partnerName sent you a love note'
                : '💌  $partnerName sealed a love note for you',
          ),
          action: SnackBarAction(
            label: note.isDelivered(now) ? 'Read' : 'See',
            onPressed: () {
              if (!mounted) return;
              setState(() => _tabIndex = _togetherTab);
              _togetherKey.currentState?.showTab(
                TogetherScreenState.loveNotesTab,
              );
            },
          ),
        ),
      );
    }, onError: (error, stack) {});
  }

  /// Starts each badge section's clock the first time, and clears the
  /// Memories badge when something new arrives while Memories is open.
  void _listenForBadges() {
    ref.listenManual(tabSeenAtProvider, (previous, next) {
      final seen = next.value;
      if (seen == null) return;
      final missing = BadgeSection.all.where((s) => !seen.containsKey(s));
      if (missing.isNotEmpty) unawaited(markSectionSeen(_myUid, missing));
    }, fireImmediately: true);
    ref.listenManual(memoriesBadgeProvider, (previous, next) {
      if (next > 0) _markOpenTabSeen();
    });
  }

  /// Clears the badge of the tab on screen (Together handles its own
  /// sections; Chat marks messages seen itself).
  void _markOpenTabSeen() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    if (_tabIndex == _memoriesTab && ref.read(memoriesBadgeProvider) > 0) {
      unawaited(markSectionSeen(_myUid, const [BadgeSection.memories]));
    }
  }

  void _selectTab(int index) {
    setState(() => _tabIndex = index);
    _markOpenTabSeen();
  }

  /// Shows a snack bar when the partner invites this user to a game while
  /// the app is open. Games already waiting when the app starts are left to
  /// the Play tab's badge.
  void _listenForGameInvites() {
    Set<String>? known;
    ref.listenManual(gamesProvider, (previous, next) {
      final games = next.value;
      if (games == null) return;
      final invites = games
          .where((g) => g.isInvite && g.invitee == _myUid)
          .toList();
      final ids = invites.map((g) => g.id).toSet();
      final fresh = known == null
          ? const <Game>[]
          : invites.where((g) => !known!.contains(g.id)).toList();
      known = ids;
      if (fresh.isEmpty || !mounted) return;
      if (ref.read(mutePartnerProvider)) return;
      // The hub already shows invites; anywhere else (including a game
      // screen pushed on top of it) gets a snack bar.
      final hubOnScreen =
          _tabIndex == _playTab && (ModalRoute.of(context)?.isCurrent ?? true);
      if (hubOnScreen) return;
      final game = fresh.first;
      final partnerName = ref.read(partnerNameProvider);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Text(
            '${game.type.emoji}  $partnerName wants to play ${game.type.label}',
          ),
          action: SnackBarAction(
            label: 'Play',
            onPressed: () {
              if (mounted) GameCatalog.open(context, game);
            },
          ),
        ),
      );
    }, onError: (error, stack) {});
  }

  /// A love tap from the partner while the app is open: the love burst with
  /// their avatar pulling the tap's face, a double buzz and a banner (with
  /// the app closed, the push notification buzzes instead).
  Future<void> _playNudge(LoveTap kind) async {
    final partner = ref.read(partnerProvider).value;
    LoveBurst.play(
      kind,
      avatar: partner?.avatar,
      overlay: Overlay.of(context, rootOverlay: true),
    );
    if (partner != null) AvatarReactions.react(partner.uid, kind.expression);
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    await HapticFeedback.heavyImpact();

    if (!mounted) return;
    final partnerName = ref.read(partnerNameProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('${kind.emoji}  $partnerName ${kind.receivedText}'),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  List<Widget> get _tabs => [
    HomeScreen(
      onOpenChat: _openChat,
      onOpenMemories: () => _selectTab(_memoriesTab),
      onOpenCalendar: () {
        setState(() => _tabIndex = _togetherTab);
        _togetherKey.currentState?.showTab(TogetherScreenState.calendarTab);
      },
    ),
    ChatScreen(isActive: _tabIndex == _chatTab),
    const MemoriesScreen(),
    TogetherScreen(key: _togetherKey, isActive: _tabIndex == _togetherTab),
    const PlayHubScreen(),
    UsScreen(onOpenChat: _openChat),
  ];

  void _openChat() => setState(() => _tabIndex = _chatTab);

  @override
  Widget build(BuildContext context) {
    final couple = ref.watch(coupleProvider).value;
    final muted = ref.watch(mutePartnerProvider);
    // Muted: no badges for the partner's activity.
    final waitingOnMe = muted ? 0 : ref.watch(gamesWaitingOnMeProvider);
    final unreadChat = ref.watch(chatBadgeProvider).value ?? 0;
    final newMemories = ref.watch(memoriesBadgeProvider);
    final newTogether = ref.watch(togetherBadgeProvider);
    if (couple == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DeviceCheckListener(
      child: IncomingCallListener(
        child: Scaffold(
          body: IndexedStack(
            index: _tabIndex,
            // IndexedStack keeps hidden tabs' tickers running; pause them so
            // looping decorations (gradients, hearts) only animate on screen.
            children: [
              for (final (i, tab) in _tabs.indexed)
                TickerMode(enabled: i == _tabIndex, child: tab),
            ],
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Listening together: on every tab while a session is live
              // (unless the partner is muted).
              const SecurityBanners(),
              if (!muted) const ListeningBanner(),
              NavigationBar(
                selectedIndex: _tabIndex,
                onDestinationSelected: _selectTab,
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home',
                  ),
                  _badged(
                    count: unreadChat,
                    icon: Icons.chat_bubble_outline,
                    selectedIcon: Icons.chat_bubble,
                    label: 'Chat',
                  ),
                  _badged(
                    count: newMemories,
                    icon: Icons.photo_album_outlined,
                    selectedIcon: Icons.photo_album,
                    label: 'Memories',
                  ),
                  _badged(
                    count: newTogether,
                    icon: Icons.calendar_month_outlined,
                    selectedIcon: Icons.calendar_month,
                    label: 'Together',
                  ),
                  _badged(
                    count: waitingOnMe,
                    icon: Icons.sports_esports_outlined,
                    selectedIcon: Icons.sports_esports,
                    label: 'Play',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.favorite_outline),
                    selectedIcon: Icon(Icons.favorite),
                    label: 'Us',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A bottom-bar item with a count badge (hidden at 0), like Play's.
  NavigationDestination _badged({
    required int count,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    Widget withBadge(IconData i) => Badge(
      isLabelVisible: count > 0,
      label: Text(badgeLabel(count)),
      child: Icon(i),
    );
    return NavigationDestination(
      icon: withBadge(icon),
      selectedIcon: withBadge(selectedIcon),
      label: label,
      tooltip: count > 0 ? '$label, $count new' : label,
    );
  }
}
